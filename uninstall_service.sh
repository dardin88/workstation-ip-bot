#!/bin/bash

# Uninstall IP Monitor Service from systemd
# Run this script with sudo

# Configuration
SERVICE_NAME="ip-change-monitor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Attempting to uninstall IP Monitor service...${NC}"

SYSTEMD_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Check if service exists
if systemctl list-units --full -all | grep -Fq "$SERVICE_NAME.service"; then
    # Stop the service
    echo -e "${YELLOW}Stopping service...${NC}"
    systemctl stop "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service stopped${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to stop service (it may not be running)${NC}"
    fi
    
    # Disable the service
    echo -e "${YELLOW}Disabling service...${NC}"
    systemctl disable "$SERVICE_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service disabled${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to disable service${NC}"
    fi
else
    echo -e "${GRAY}Service not found in systemd${NC}"
fi

# Remove service file
if [ -f "$SYSTEMD_SERVICE_FILE" ]; then
    echo -e "${YELLOW}Removing service file...${NC}"
    rm -f "$SYSTEMD_SERVICE_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service file removed: $SYSTEMD_SERVICE_FILE${NC}"
    else
        echo -e "${RED}Error: Failed to remove service file${NC}" >&2
    fi
else
    echo -e "${GRAY}Service file not found${NC}"
fi

# Reload systemd daemon
echo -e "${YELLOW}Reloading systemd daemon...${NC}"
systemctl daemon-reload

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Systemd daemon reloaded${NC}"
fi

# Reset failed state if any
systemctl reset-failed "$SERVICE_NAME" 2>/dev/null

echo -e "\n${GREEN}=== Uninstallation Complete ===${NC}"
echo -e "${CYAN}The IP monitor service has been removed.${NC}"
echo -e "${CYAN}Note: Configuration files and logs have been preserved.${NC}"
