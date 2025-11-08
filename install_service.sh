#!/bin/bash

# Install IP Monitor as a systemd service on Linux
# Run this script with sudo

# Configuration
SERVICE_NAME="ip-change-monitor"
SERVICE_DISPLAY_NAME="IP Change Discord Notifier"
SERVICE_DESCRIPTION="Monitors IP address changes and sends notifications to Discord"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}" >&2
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MONITOR_SCRIPT="$SCRIPT_DIR/ip_monitor.sh"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Validate files exist
if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo -e "${RED}Error: Monitor script not found: $MONITOR_SCRIPT${NC}" >&2
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}" >&2
    exit 1
fi

# Check for required dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}jq is not installed. Installing...${NC}"
    apt-get update && apt-get install -y jq
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to install jq${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}jq installed successfully${NC}"
fi

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}curl is not installed. Installing...${NC}"
    apt-get update && apt-get install -y curl
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to install curl${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}curl installed successfully${NC}"
fi

# Make the monitor script executable
chmod +x "$MONITOR_SCRIPT"

# Create systemd service file
SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo -e "${YELLOW}Creating systemd service file...${NC}"

cat > "$SYSTEMD_SERVICE_FILE" << EOF
[Unit]
Description=$SERVICE_DESCRIPTION
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash $MONITOR_SCRIPT $CONFIG_FILE
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Run as the user who owns the script directory
User=$(stat -c '%U' "$SCRIPT_DIR")
Group=$(stat -c '%G' "$SCRIPT_DIR")

# Working directory
WorkingDirectory=$SCRIPT_DIR

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create systemd service file${NC}" >&2
    exit 1
fi

echo -e "${GREEN}Systemd service file created: $SYSTEMD_SERVICE_FILE${NC}"

# Reload systemd daemon
echo -e "${YELLOW}Reloading systemd daemon...${NC}"
systemctl daemon-reload

# Enable the service to start on boot
echo -e "${YELLOW}Enabling service to start on boot...${NC}"
systemctl enable "$SERVICE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to enable service${NC}" >&2
    exit 1
fi

# Start the service
echo -e "${YELLOW}Starting service...${NC}"
systemctl start "$SERVICE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start service${NC}" >&2
    echo -e "${CYAN}Checking service status...${NC}"
    systemctl status "$SERVICE_NAME" --no-pager
    echo -e "\n${CYAN}Checking recent logs...${NC}"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    exit 1
fi

# Wait a moment for the service to start
sleep 2

# Check service status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "\n${GREEN}=== Installation Complete ===${NC}"
    echo -e "${GREEN}The IP monitor service is now running and will start automatically on boot.${NC}"
    echo -e "\n${CYAN}Useful commands:${NC}"
    echo -e "  Check status:  ${YELLOW}sudo systemctl status $SERVICE_NAME${NC}"
    echo -e "  Stop service:  ${YELLOW}sudo systemctl stop $SERVICE_NAME${NC}"
    echo -e "  Start service: ${YELLOW}sudo systemctl start $SERVICE_NAME${NC}"
    echo -e "  View logs:     ${YELLOW}sudo journalctl -u $SERVICE_NAME -f${NC}"
    echo -e "  Uninstall:     ${YELLOW}sudo bash $SCRIPT_DIR/uninstall_service.sh${NC}"
else
    echo -e "${RED}Error: Service failed to start${NC}" >&2
    echo -e "${CYAN}Service status:${NC}"
    systemctl status "$SERVICE_NAME" --no-pager
    echo -e "\n${CYAN}Recent logs:${NC}"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    exit 1
fi
