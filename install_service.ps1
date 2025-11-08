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

# Check if NSSM is available (recommended method)
$nssmPath = Get-Command nssm.exe -ErrorAction SilentlyContinue

if ($nssmPath) {
    Write-Host "Installing service using NSSM..." -ForegroundColor Yellow
    
    # Remove existing service if it exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Removing existing service..." -ForegroundColor Yellow
        & nssm remove $ServiceName confirm
    }
    
    # Install the service
    & nssm install $ServiceName "powershell.exe" "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`""
    & nssm set $ServiceName AppDirectory $PSScriptRoot
    & nssm set $ServiceName DisplayName $DisplayName
    & nssm set $ServiceName Description $Description
    & nssm set $ServiceName Start SERVICE_AUTO_START
    & nssm set $ServiceName AppStdout (Join-Path $PSScriptRoot "service_output.log")
    & nssm set $ServiceName AppStderr (Join-Path $PSScriptRoot "service_error.log")
    
    Write-Host "Service installed successfully!" -ForegroundColor Green
    Write-Host "Starting service..." -ForegroundColor Yellow
    Start-Service -Name $ServiceName
    Write-Host "Service started!" -ForegroundColor Green
}
else {
    Write-Host "NSSM not found. Creating scheduled task instead..." -ForegroundColor Yellow
    
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
    Write-Host "`nNote: For better service management, consider installing NSSM (Non-Sucking Service Manager)" -ForegroundColor Yellow
    Write-Host "Download from: https://nssm.cc/download" -ForegroundColor Cyan
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
Write-Host "The IP monitor is now running and will start automatically on boot." -ForegroundColor Green
