# IP Change Notification Script for Discord
# This script monitors IP address changes and sends notifications to Discord

param(
    [string]$ConfigPath = ".\config.json"
)

# File to store last notified IP
$LastIPFile = ".last_notified_ip.json"

# Load configuration
function Load-Config {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Error "Configuration file not found: $Path"
        exit 1
    }
    
    try {
        $config = Get-Content $Path -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        exit 1
    }
}

# Load last notified IP from file
function Load-LastNotifiedIP {
    if (Test-Path $LastIPFile) {
        try {
            $lastIPs = Get-Content $LastIPFile -Raw | ConvertFrom-Json
            return $lastIPs
        }
        catch {
            Write-Warning "Failed to load last notified IP: $_"
            return @()
        }
    }
    return @()
}

# Save last notified IP to file
function Save-LastNotifiedIP {
    param([array]$IPs)
    
    try {
        $IPs | ConvertTo-Json -Depth 10 | Set-Content -Path $LastIPFile
    }
    catch {
        Write-Warning "Failed to save last notified IP: $_"
    }
}

# Get current IP addresses (excluding loopback and link-local)
function Get-CurrentIPAddresses {
    $ipAddresses = @()
    
    $adapters = Get-NetIPAddress -AddressFamily IPv4 | 
                Where-Object { 
                    $_.IPAddress -notmatch '^127\.' -and 
                    $_.IPAddress -notmatch '^169\.254\.' -and
                    $_.AddressState -eq 'Preferred'
                }
    
    foreach ($adapter in $adapters) {
        $interface = Get-NetAdapter | Where-Object { $_.ifIndex -eq $adapter.InterfaceIndex }
        
        if ($interface.Status -eq 'Up') {
            $ipAddresses += @{
                InterfaceName = $interface.Name
                IPAddress = $adapter.IPAddress
                InterfaceAlias = $adapter.InterfaceAlias
            }
        }
    }
    
    return $ipAddresses
}

# Send notification to Discord
function Send-DiscordNotification {
    param(
        [string]$WebhookUrl,
        [string]$Hostname,
        [array]$OldIPs,
        [array]$NewIPs,
        [string]$ChangeType
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Build the message
    $description = "**Hostname:** $Hostname`n**Time:** $timestamp`n`n"
    
    if ($ChangeType -eq "Initial") {
        $description += "**Current IP Addresses:**`n"
        foreach ($ip in $NewIPs) {
            $description += "- **$($ip.InterfaceAlias)**: $($ip.IPAddress)`n"
        }
    }
    else {
        $description += "**IP Address Change Detected**`n`n"
        
        if ($OldIPs.Count -gt 0) {
            $description += "**Previous IPs:**`n"
            foreach ($ip in $OldIPs) {
                $description += "- **$($ip.InterfaceAlias)**: $($ip.IPAddress)`n"
            }
            $description += "`n"
        }
        
        $description += "**New IPs:**`n"
        foreach ($ip in $NewIPs) {
            $description += "- **$($ip.InterfaceAlias)**: $($ip.IPAddress)`n"
        }
    }
    
    # Create Discord embed
    $embed = @{
        title = if ($ChangeType -eq "Initial") { "[INFO] IP Monitor Started" } else { "[CHANGE] IP Address Changed" }
        description = $description
        color = if ($ChangeType -eq "Initial") { 3447003 } else { 15844367 }  # Blue for initial, Orange for change
        footer = @{
            text = "IP Change Monitor"
        }
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
    
    $payload = @{
        embeds = @($embed)
    } | ConvertTo-Json -Depth 10 -Compress
    
    try {
        $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payloadBytes -ContentType 'application/json; charset=utf-8' | Out-Null
        Write-Host "[OK] Discord notification sent successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to send Discord notification: $_"
        return $false
    }
}

# Write log entry
function Write-Log {
    param(
        [string]$Message,
        [string]$LogPath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logMessage
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

# Compare IP address lists
function Compare-IPAddresses {
    param(
        [array]$Old,
        [array]$New
    )
    
    if ($Old.Count -ne $New.Count) {
        return $true
    }
    
    $oldSorted = $Old | Sort-Object -Property IPAddress
    $newSorted = $New | Sort-Object -Property IPAddress
    
    for ($i = 0; $i -lt $oldSorted.Count; $i++) {
        if ($oldSorted[$i].IPAddress -ne $newSorted[$i].IPAddress) {
            return $true
        }
    }
    
    return $false
}

# Main monitoring loop
function Start-IPMonitoring {
    param(
        [string]$ConfigPath
    )
    
    Write-Host "=== IP Change Notification Monitor ===" -ForegroundColor Cyan
    Write-Host "Loading configuration..." -ForegroundColor Yellow
    
    $config = Load-Config -Path $ConfigPath
    $hostname = $env:COMPUTERNAME
    $lastNotifiedIPs = Load-LastNotifiedIP
    
    Write-Host "Configuration loaded successfully" -ForegroundColor Green
    Write-Host "Hostname: $hostname" -ForegroundColor Cyan
    Write-Host "Check interval: $($config.check_interval_seconds) seconds" -ForegroundColor Cyan
    
    if ($lastNotifiedIPs.Count -gt 0) {
        Write-Host "Last notified IP loaded from previous session" -ForegroundColor Cyan
    }
    else {
        Write-Host "No previous IP notification found - will notify on first detection" -ForegroundColor Yellow
    }
    
    Write-Host "`nStarting monitoring..." -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray
    
    while ($true) {
        try {
            $currentIPs = Get-CurrentIPAddresses
            
            # Only notify if IPs are different from last notified IPs
            if ($currentIPs.Count -gt 0 -and (Compare-IPAddresses -Old $lastNotifiedIPs -New $currentIPs)) {
                # IP changed - send notification
                Write-Host "`n[CHANGE] IP Address change detected!" -ForegroundColor Yellow
                Write-Log -Message "IP change detected. Old: $($lastNotifiedIPs | ConvertTo-Json -Compress) | New: $($currentIPs | ConvertTo-Json -Compress)" -LogPath $config.log_file
                
                if ($lastNotifiedIPs.Count -eq 0) {
                    # First time notification
                    Write-Host "Sending initial IP notification..." -ForegroundColor Yellow
                    $sent = Send-DiscordNotification -WebhookUrl $config.discord_webhook_url `
                                                     -Hostname $hostname `
                                                     -OldIPs @() `
                                                     -NewIPs $currentIPs `
                                                     -ChangeType "Initial"
                }
                else {
                    # IP actually changed
                    $sent = Send-DiscordNotification -WebhookUrl $config.discord_webhook_url `
                                                     -Hostname $hostname `
                                                     -OldIPs $lastNotifiedIPs `
                                                     -NewIPs $currentIPs `
                                                     -ChangeType "Change"
                }
                
                # Save the new IP as last notified
                Save-LastNotifiedIP -IPs $currentIPs
                $lastNotifiedIPs = $currentIPs
            }
            elseif ($currentIPs.Count -eq 0) {
                # No network connection
                $timestamp = Get-Date -Format "HH:mm:ss"
                Write-Host "[$timestamp] No network connection detected" -ForegroundColor Gray
            }
            else {
                # No change from last notification
                $timestamp = Get-Date -Format "HH:mm:ss"
                Write-Host "[$timestamp] IP unchanged (no notification needed)" -ForegroundColor Gray
            }
            
            # Wait before next check
            Start-Sleep -Seconds $config.check_interval_seconds
        }
        catch {
            Write-Error "Error in monitoring loop: $_"
            Write-Log -Message "Error: $_" -LogPath $config.log_file
            Start-Sleep -Seconds 10
        }
    }
}

# Start the monitoring
Start-IPMonitoring -ConfigPath $ConfigPath
