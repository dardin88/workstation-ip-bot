# IP Change Notification via Discord

This project monitors IP address changes on both **Windows** and **Linux (Xubuntu 24.04)** machines and sends notifications to Discord with both the hostname and IP address information.

## Features

- 🔍 Monitors all active network interfaces for IP changes
- 📢 Sends formatted Discord notifications with hostname and IP details
- 🔄 Runs continuously in the background
- 📝 Logs all IP changes to a file
- ⚙️ Easy to configure via JSON
- 🚀 Can run as a Windows Service or Linux systemd service
- 🎨 Beautiful Discord embeds with color coding
- 🖥️ Cross-platform support (Windows & Linux)

## Prerequisites

### Windows
- Windows 10/11 (fully tested on Windows 11)
- PowerShell 5.1 or higher (included in Windows 11)
- Discord webhook URL

### Linux (Xubuntu 24.04)
- Xubuntu 24.04 or compatible Ubuntu-based distribution
- Bash shell
- `jq` (will be installed automatically by the install script)
- `curl` (will be installed automatically by the install script)
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

#### Windows

```powershell
# Open PowerShell and navigate to the script directory
cd "C:\path\to\ip_change_notification_via_discord"

# Run the script
.\ip_monitor.ps1
```

#### Linux

```bash
# Open terminal and navigate to the script directory
cd /path/to/ip_change_notification_via_discord

# Make the script executable
chmod +x ip_monitor.sh

# Run the script
./ip_monitor.sh
```

You should see:
- Initial notification sent to Discord
- Console output showing monitoring status
- Press Ctrl+C to stop

### 4. Install as a Service (Recommended)

To run the monitor automatically on system startup:

#### Windows

##### Option A: Using NSSM (Recommended)

1. Download NSSM from https://nssm.cc/download
2. Extract and add to PATH or place in script directory
3. Run PowerShell as Administrator:

```powershell
cd "C:\path\to\ip_change_notification_via_discord"
.\install_service.ps1
```

##### Option B: Using Scheduled Task (Alternative)

If NSSM is not available, the install script will automatically create a scheduled task instead.

```powershell
# Run PowerShell as Administrator
cd "C:\path\to\ip_change_notification_via_discord"
.\install_service.ps1
```

#### Linux

```bash
# Open terminal and navigate to the script directory
cd /path/to/ip_change_notification_via_discord

# Make the install script executable
chmod +x install_service.sh

# Run the install script with sudo
sudo ./install_service.sh
```

The script will automatically:
- Install required dependencies (`jq` and `curl` if not present)
- Create a systemd service
- Enable the service to start on boot
- Start the service immediately

### 5. Verify Installation

Check if the service is running:

#### Windows

```powershell
# For NSSM service:
Get-Service -Name "IPChangeMonitor"

# For scheduled task:
Get-ScheduledTask -TaskName "IPChangeMonitor"
```

#### Linux

```bash
# Check service status
sudo systemctl status ip-change-monitor

# View real-time logs
sudo journalctl -u ip-change-monitor -f
```

## Usage

### Manual Execution

#### Windows

Run the script directly in PowerShell:

```powershell
.\ip_monitor.ps1
```

With custom config path:

```powershell
.\ip_monitor.ps1 -ConfigPath "C:\custom\path\config.json"
```

#### Linux

Run the script directly in terminal:

```bash
./ip_monitor.sh
```

With custom config path:

```bash
./ip_monitor.sh /custom/path/config.json
```

### Service Management

#### Windows

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

#### Linux

Start the service:
```bash
sudo systemctl start ip-change-monitor
```

Stop the service:
```bash
sudo systemctl stop ip-change-monitor
```

Restart the service:
```bash
sudo systemctl restart ip-change-monitor
```

Check service status:
```bash
sudo systemctl status ip-change-monitor
```

View logs:
```bash
# View all logs
sudo journalctl -u ip-change-monitor

# Follow logs in real-time
sudo journalctl -u ip-change-monitor -f

# View last 50 lines
sudo journalctl -u ip-change-monitor -n 50
```

### Uninstall

To remove the service:

#### Windows

```powershell
# Run PowerShell as Administrator
cd "C:\path\to\ip_change_notification_via_discord"
.\uninstall_service.ps1
```

#### Linux

```bash
# Navigate to script directory
cd /path/to/ip_change_notification_via_discord

# Make the uninstall script executable (if not already)
chmod +x uninstall_service.sh

# Run with sudo
sudo ./uninstall_service.sh
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

The script maintains logs in different locations depending on the platform:

### Windows
1. **ip_monitor.log** - Application log with IP change history
2. **service_output.log** - Service stdout (if running as NSSM service)
3. **service_error.log** - Service stderr (if running as NSSM service)

### Linux
1. **ip_monitor.log** - Application log with IP change history (in script directory)
2. **systemd journal** - Service logs accessible via `journalctl`
   ```bash
   # View all logs for the service
   sudo journalctl -u ip-change-monitor
   ```

## Troubleshooting

### Script doesn't send notifications

- Verify the Discord webhook URL is correct
- Check network connectivity
- Review the log file for errors
- **Linux**: Ensure `curl` and `jq` are installed

### Service won't start

#### Windows
- Ensure you ran the install script as Administrator
- Check the service error log
- Verify PowerShell execution policy allows scripts:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
  ```

#### Linux
- Check service status: `sudo systemctl status ip-change-monitor`
- View logs: `sudo journalctl -u ip-change-monitor -n 50`
- Verify script has execute permissions: `chmod +x ip_monitor.sh`
- Check if required packages are installed: `which jq curl`

### Multiple notifications for the same IP

- Increase `check_interval_seconds` in config.json
- Check if network adapters are changing state frequently

## Security Considerations

- Keep your Discord webhook URL private
- The webhook URL is stored in plain text in `config.json`
- Consider encrypting sensitive configuration if needed
- **Windows**: The service runs with SYSTEM privileges when installed
- **Linux**: The service runs with the user privileges of the script directory owner

## Platform-Specific Notes

### Windows
- Uses PowerShell scripts (`.ps1` files)
- Can run as Windows Service (via NSSM) or Scheduled Task
- Tested on Windows 11

### Linux (Xubuntu 24.04)
- Uses Bash scripts (`.sh` files)
- Runs as systemd service
- Requires `jq` and `curl` (auto-installed by install script)
- Uses `ip` command to detect network interfaces

## File Structure

```
ip_change_notification_via_discord/
├── config.json                 # Configuration file (shared)
├── ip_monitor.ps1              # Windows PowerShell monitor script
├── install_service.ps1         # Windows service installer
├── uninstall_service.ps1       # Windows service uninstaller
├── ip_monitor.sh               # Linux Bash monitor script
├── install_service.sh          # Linux systemd service installer
├── uninstall_service.sh        # Linux systemd service uninstaller
└── README.md                   # This file
```

## License

This project is provided as-is for personal and educational use.

## Support

For issues or questions, please check:
- Log files for error messages
- Discord webhook status in Discord server settings
- Windows Event Viewer for service-related errors

---

**Note**: This script monitors IPv4 addresses only and excludes loopback (127.x.x.x) and link-local (169.254.x.x) addresses.
