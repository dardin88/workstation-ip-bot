# Install IP Monitor as a Windows Service
# Run this script as Administrator

param(
    [string]$ServiceName = "IPChangeMonitor",
    [string]$DisplayName = "IP Change Discord Notifier",
    [string]$Description = "Monitors IP address changes and sends notifications to Discord",
    [string]$ScriptPath = $null,
    [switch]$NoServiceStart,
    [switch]$DebugTest
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator!"
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Determine script path
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = Join-Path $PSScriptRoot "ip_monitor.ps1"
}

$ConfigPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Script not found: $ScriptPath"
    exit 1
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath"
    exit 1
}

# Resolve a stable Windows PowerShell 5.1 path for services
$WinPSExe = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
if (-not (Test-Path $WinPSExe)) {
    # Fallback to whatever "powershell.exe" resolves to
    $psCmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $WinPSExe = if ($psCmd) { $psCmd.Source } else { 'powershell.exe' }
}

function Get-NssmExecutablePath {
    # Try PATH first
    $cmd = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Path }

    # Try local bin folder
    $localPath = Join-Path $PSScriptRoot "bin/nssm.exe"
    if (Test-Path $localPath) { return $localPath }

    return $null
}

function Ensure-NssmInstalled {
    param(
        [string]$DestinationDir
    )
    
    $existing = Get-NssmExecutablePath
    if ($existing) { return $existing }

    Write-Host "NSSM not found. Attempting to download and install..." -ForegroundColor Yellow

    $urls = @(
        'https://nssm.cc/release/nssm-2.24.zip',
        'https://github.com/hn256/nssm/releases/download/v2.24/nssm-2.24.zip'
    )

    $tempZip = Join-Path $env:TEMP ("nssm-" + [guid]::NewGuid().Guid + ".zip")
    $tempDir = Join-Path $env:TEMP ("nssm-" + [guid]::NewGuid().Guid)

    try {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

        $downloaded = $false
        foreach ($url in $urls) {
            try {
                Write-Host "Downloading NSSM from: $url" -ForegroundColor Cyan
                Invoke-WebRequest -Uri $url -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
                $downloaded = $true
                break
            }
            catch {
                # Avoid parsing issues with colon after variable; use -f formatting
                Write-Warning ("Download failed from {0}: {1}" -f $url, $_)
            }
        }

        if (-not $downloaded) {
            throw "Unable to download NSSM from all sources."
        }

        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

        $is64 = ((Get-CimInstance Win32_OperatingSystem).OSArchitecture -like '*64*')
        $archFolder = if ($is64) { 'win64' } else { 'win32' }

        $extractedPath = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like 'nssm-*' } | Select-Object -First 1
        if (-not $extractedPath) { throw "Unexpected NSSM archive layout." }

        $srcExe = Join-Path $extractedPath.FullName (Join-Path $archFolder 'nssm.exe')
        if (-not (Test-Path $srcExe)) { throw "nssm.exe not found in extracted archive." }

        New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
        $dstExe = Join-Path $DestinationDir 'nssm.exe'
        Copy-Item -Path $srcExe -Destination $dstExe -Force

        Write-Host "NSSM installed to: $dstExe" -ForegroundColor Green
        return $dstExe
    }
    catch {
        Write-Warning "Automatic NSSM installation failed: $_"
        return $null
    }
    finally {
        # Cleanup temp files
        try { if (Test-Path $tempZip) { Remove-Item $tempZip -Force } } catch {}
        try { if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force } } catch {}
    }
}

# Ensure NSSM is available (recommended method)
$nssmExe = Get-NssmExecutablePath
if (-not $nssmExe) {
    $nssmExe = Ensure-NssmInstalled -DestinationDir (Join-Path $PSScriptRoot 'bin')
}

if ($nssmExe) {
    Write-Host "Installing service using NSSM..." -ForegroundColor Yellow
    
    # Remove existing service if it exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Removing existing service..." -ForegroundColor Yellow
        
        # Stop the service first if it's running
        if ($existingService.Status -eq 'Running') {
            Write-Host "Stopping running service..." -ForegroundColor Yellow
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        
        # Remove the service
        & $nssmExe remove $ServiceName confirm | Out-Null
        
        # Wait for Windows to fully remove the service (critical on Windows)
        Write-Host "Waiting for service deletion to complete..." -ForegroundColor Yellow
        $maxWait = 30
        $waited = 0
        while ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) -and ($waited -lt $maxWait)) {
            Start-Sleep -Seconds 1
            $waited++
        }
        
        if ($waited -ge $maxWait) {
            Write-Warning "Service still exists after $maxWait seconds. You may need to restart your computer."
            Write-Host "Press Enter to continue anyway, or Ctrl+C to abort..." -ForegroundColor Yellow
            Read-Host
        }
        else {
            Write-Host "Service removed successfully." -ForegroundColor Green
            # Extra buffer time to ensure Windows releases all handles
            Start-Sleep -Seconds 2
        }
    }
    
    # Install the service with retry logic
    Write-Host "Creating new service..." -ForegroundColor Yellow
    $installAttempts = 0
    $maxAttempts = 3
    $installed = $false
    
    while (-not $installed -and $installAttempts -lt $maxAttempts) {
        $installAttempts++
        
        $result = & $nssmExe install $ServiceName $WinPSExe "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`"" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $installed = $true
            Write-Host "Service created successfully." -ForegroundColor Green
        }
        elseif ($result -like "*marked for deletion*" -or $result -like "*segnato per l'eliminazione*") {
            if ($installAttempts -lt $maxAttempts) {
                Write-Host "Service still marked for deletion. Waiting 5 seconds before retry $installAttempts/$maxAttempts..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
            else {
                Write-Error "Failed to create service after $maxAttempts attempts. Please restart your computer and try again."
                exit 1
            }
        }
        else {
            Write-Error "Failed to install service: $result"
            exit 1
        }
    }
    & $nssmExe set $ServiceName AppDirectory $PSScriptRoot
    & $nssmExe set $ServiceName DisplayName $DisplayName
    & $nssmExe set $ServiceName Description $Description
    & $nssmExe set $ServiceName Start SERVICE_AUTO_START
    & $nssmExe set $ServiceName AppStdout (Join-Path $PSScriptRoot "service_output.log")
    & $nssmExe set $ServiceName AppStderr (Join-Path $PSScriptRoot "service_error.log")
    & $nssmExe set $ServiceName AppStopMethodSkip 0
    & $nssmExe set $ServiceName AppThrottle 1500
    
    Write-Host "Service installed successfully!" -ForegroundColor Green

    if ($DebugTest) {
        Write-Host "Running one-shot debug test (not as a service)..." -ForegroundColor Cyan
        Start-Process -FilePath $WinPSExe -ArgumentList @('-ExecutionPolicy','Bypass','-NoProfile','-File',"$ScriptPath",'-ConfigPath',"$ConfigPath") -WindowStyle Hidden
        Start-Sleep -Seconds 3
        Write-Host "(Launched a background process for test; check Discord or logs.)" -ForegroundColor DarkGray
    }

    if ($NoServiceStart) {
        Write-Host "Skipping service start due to -NoServiceStart switch." -ForegroundColor Yellow
    }
    else {
        Write-Host "Starting service..." -ForegroundColor Yellow
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Host "Service started!" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to start service '$ServiceName'. $_"
            $errLog = Join-Path $PSScriptRoot 'service_error.log'
            $outLog = Join-Path $PSScriptRoot 'service_output.log'
            if (Test-Path $errLog) {
                Write-Host "Last 50 lines of service_error.log:" -ForegroundColor Yellow
                Get-Content -Path $errLog -Tail 50 | ForEach-Object { Write-Host $_ }
            }
            if (Test-Path $outLog) {
                Write-Host "Last 20 lines of service_output.log:" -ForegroundColor Yellow
                Get-Content -Path $outLog -Tail 20 | ForEach-Object { Write-Host $_ }
            }
            Write-Host "Troubleshooting tips:" -ForegroundColor Cyan
            Write-Host "  1. Run the script manually: $WinPSExe -ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`"" -ForegroundColor Cyan
            Write-Host "  2. Verify 'config.json' is valid JSON and webhook reachable." -ForegroundColor Cyan
            Write-Host "  3. Check Event Viewer → Windows Logs → Application for NSSM entries." -ForegroundColor Cyan
            Write-Host "  4. Ensure antivirus/security software isn't blocking PowerShell." -ForegroundColor Cyan
            Write-Host "  5. Re-run installer with -DebugTest to validate the script in foreground." -ForegroundColor Cyan
        }
    }
}
else {
    Write-Host "NSSM is unavailable. Creating scheduled task instead..." -ForegroundColor Yellow
    
    # Create a scheduled task as an alternative
    $taskName = $ServiceName
    
    # Remove existing task if it exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "Removing existing task..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    
    # Create the action
    $action = New-ScheduledTaskAction -Execute $WinPSExe `
                                      -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`""
    
    # Create the trigger (at startup)
    $trigger = New-ScheduledTaskTrigger -AtStartup
    
    # Create the principal (run as SYSTEM)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Create the settings
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                              -DontStopIfGoingOnBatteries `
                                              -StartWhenAvailable `
                                              -RestartCount 3 `
                                              -RestartInterval (New-TimeSpan -Minutes 1)
    
    # Register the task
    Register-ScheduledTask -TaskName $taskName `
                          -Action $action `
                          -Trigger $trigger `
                          -Principal $principal `
                          -Settings $settings `
                          -Description $Description
    
    # Start the task
    Start-ScheduledTask -TaskName $taskName
    
    Write-Host "Scheduled task created and started successfully!" -ForegroundColor Green
    Write-Host "`nNote: For better service management, install NSSM when possible. This script will attempt it automatically on next run." -ForegroundColor Yellow
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
Write-Host "The IP monitor is now running and will start automatically on boot." -ForegroundColor Green
