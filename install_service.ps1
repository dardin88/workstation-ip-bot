# Install IP Monitor as a Windows Service
# Run this script as Administrator

param(
    [string]$ServiceName = "IPChangeMonitor",
    [string]$DisplayName = "IP Change Discord Notifier",
    [string]$Description = "Monitors IP address changes and sends notifications to Discord",
    [string]$ScriptPath = $null
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
                Write-Warning "Download failed from $url: $_"
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
        & $nssmExe remove $ServiceName confirm
    }
    
    # Install the service
    & $nssmExe install $ServiceName "powershell.exe" "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`""
    & $nssmExe set $ServiceName AppDirectory $PSScriptRoot
    & $nssmExe set $ServiceName DisplayName $DisplayName
    & $nssmExe set $ServiceName Description $Description
    & $nssmExe set $ServiceName Start SERVICE_AUTO_START
    & $nssmExe set $ServiceName AppStdout (Join-Path $PSScriptRoot "service_output.log")
    & $nssmExe set $ServiceName AppStderr (Join-Path $PSScriptRoot "service_error.log")
    
    Write-Host "Service installed successfully!" -ForegroundColor Green
    Write-Host "Starting service..." -ForegroundColor Yellow
    Start-Service -Name $ServiceName
    Write-Host "Service started!" -ForegroundColor Green
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
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
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
