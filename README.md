# IP Change Notification via Discord

This project monitors IP address changes on Windows machines and sends notifications to Discord with both the hostname and IP address information.

## Features

- 🔍 Monitors all active network interfaces for IP changes
- 📢 Sends formatted Discord notifications with hostname and IP details
- 🔄 Runs continuously in the background
- 📝 Logs all IP changes to a file
- ⚙️ Easy to configure via JSON
- 🚀 Can run as a Windows Service or Scheduled Task
- 🎨 Beautiful Discord embeds with color coding

## Prerequisites

- Windows 10/11 (fully tested on Windows 11)
- PowerShell 5.1 or higher (included in Windows 11)
- Discord webhook URL

## Setup Instructions

### 1. Create a Discord Webhook

1. Open your Discord server
2. Go to Server Settings → Integrations → Webhooks
3. Click "New Webhook"
4. Give it a name (e.g., "IP Monitor")
5. Select the channel where notifications should be sent
6. Copy the Webhook URL

### 2. Configure the Monitor

1. Open `config.json` in a text editor
2. Replace `YOUR_DISCORD_WEBHOOK_URL_HERE` with your actual webhook URL
3. Adjust `check_interval_seconds` if desired (default: 60 seconds)
4. Save the file

Example `config.json`:
```json
{
  "discord_webhook_url": "https://discord.com/api/webhooks/123456789/abcdefg",
  "check_interval_seconds": 60,
  "log_file": "ip_monitor.log"
}
```

### 3. Test the Script

Before installing as a service, test the script manually:

```powershell
# Open PowerShell and navigate to the script directory
cd "C:\path\to\ip_change_notification_via_discord"

# Run the script
.\ip_monitor.ps1
```

You should see:
- Initial notification sent to Discord
- Console output showing monitoring status
- Press Ctrl+C to stop

### 4. Install as a Service (Recommended)

To run the monitor automatically on system startup:

#### Option A: Using NSSM (Recommended)

1. Download NSSM from https://nssm.cc/download
2. Extract and add to PATH or place in script directory
3. Run PowerShell as Administrator:

```powershell
cd "C:\path\to\ip_change_notification_via_discord"
.\install_service.ps1
```

#### Option B: Using Scheduled Task (Alternative)

If NSSM is not available, the install script will automatically create a scheduled task instead.

```powershell
# Run PowerShell as Administrator
cd "C:\path\to\ip_change_notification_via_discord"
.\install_service.ps1
```

### 5. Verify Installation

Check if the service is running:

```powershell
# For NSSM service:
Get-Service -Name "IPChangeMonitor"

# For scheduled task:
Get-ScheduledTask -TaskName "IPChangeMonitor"
```

## Usage

### Manual Execution

Run the script directly in PowerShell:

```powershell
.\ip_monitor.ps1
```

With custom config path:

```powershell
.\ip_monitor.ps1 -ConfigPath "C:\custom\path\config.json"
```

### Service Management

Start the service:
```powershell
Start-Service -Name "IPChangeMonitor"
# OR
Start-ScheduledTask -TaskName "IPChangeMonitor"
```

Stop the service:
```powershell
Stop-Service -Name "IPChangeMonitor"
# OR
Stop-ScheduledTask -TaskName "IPChangeMonitor"
```

Check service status:
```powershell
Get-Service -Name "IPChangeMonitor"
# OR
Get-ScheduledTask -TaskName "IPChangeMonitor"
```

### Uninstall

To remove the service:

```powershell
# Run PowerShell as Administrator
cd "C:\path\to\ip_change_notification_via_discord"
.\uninstall_service.ps1
```

## Discord Notification Format

Notifications include:

- **🔵 Initial Notification** (when monitoring starts):
  - Hostname
  - Timestamp
  - Current IP addresses for all interfaces

- **🔄 Change Notification** (when IP changes):
  - Hostname
  - Timestamp
  - Previous IP addresses
  - New IP addresses
  - Interface names for each IP

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `discord_webhook_url` | Your Discord webhook URL | Required |
| `check_interval_seconds` | How often to check for changes (in seconds) | 60 |
| `log_file` | Path to log file | ip_monitor.log |

## Logs

The script maintains two types of logs:

1. **ip_monitor.log** - Application log with IP change history
2. **service_output.log** - Service stdout (if running as NSSM service)
3. **service_error.log** - Service stderr (if running as NSSM service)

## Troubleshooting

### Script doesn't send notifications

- Verify the Discord webhook URL is correct
- Check network connectivity
- Review the log file for errors

### Service won't start

- Ensure you ran the install script as Administrator
- Check the service error log
- Verify PowerShell execution policy allows scripts:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
  ```

### Multiple notifications for the same IP

- Increase `check_interval_seconds` in config.json
- Check if network adapters are changing state frequently

## Security Considerations

- Keep your Discord webhook URL private
- The webhook URL is stored in plain text in `config.json`
- Consider encrypting sensitive configuration if needed
- The service runs with SYSTEM privileges when installed

## License

This project is provided as-is for personal and educational use.

## Support

For issues or questions, please check:
- Log files for error messages
- Discord webhook status in Discord server settings
- Windows Event Viewer for service-related errors

---

**Note**: This script monitors IPv4 addresses only and excludes loopback (127.x.x.x) and link-local (169.254.x.x) addresses.
