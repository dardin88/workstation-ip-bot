# Uninstall IP Monitor Service
# Run this script as Administrator

param(
    [string]$ServiceName = "IPChangeMonitor"
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator!"
    Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Attempting to uninstall IP Monitor..." -ForegroundColor Yellow

# Try to remove NSSM service
$nssmPath = Get-Command nssm.exe -ErrorAction SilentlyContinue
if ($nssmPath) {
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Host "Stopping service..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        
        Write-Host "Removing service..." -ForegroundColor Yellow
        & nssm remove $ServiceName confirm
        Write-Host "Service removed successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "Service not found." -ForegroundColor Gray
    }
}

# Try to remove scheduled task
$existingTask = Get-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Stopping task..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName $ServiceName -ErrorAction SilentlyContinue
    
    Write-Host "Removing scheduled task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $ServiceName -Confirm:$false
    Write-Host "Scheduled task removed successfully!" -ForegroundColor Green
}
else {
    Write-Host "Scheduled task not found." -ForegroundColor Gray
}

Write-Host "`n=== Uninstallation Complete ===" -ForegroundColor Green
