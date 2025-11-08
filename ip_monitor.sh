#!/bin/bash

# IP Change Notification Script for Discord
# This script monitors IP address changes and sends notifications to Discord

# Default configuration path
CONFIG_PATH="${1:-./config.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${RED}Error: Configuration file not found: $CONFIG_PATH${NC}" >&2
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed. Please install it: sudo apt install jq${NC}" >&2
        exit 1
    fi
    
    DISCORD_WEBHOOK_URL=$(jq -r '.discord_webhook_url' "$CONFIG_PATH")
    CHECK_INTERVAL=$(jq -r '.check_interval_seconds' "$CONFIG_PATH")
    LOG_FILE=$(jq -r '.log_file' "$CONFIG_PATH")
    
    if [ -z "$DISCORD_WEBHOOK_URL" ] || [ "$DISCORD_WEBHOOK_URL" = "null" ]; then
        echo -e "${RED}Error: discord_webhook_url not found in configuration${NC}" >&2
        exit 1
    fi
}

# Get current IP addresses (excluding loopback and link-local)
get_current_ip_addresses() {
    local result=""
    
    # Get all network interfaces with IP addresses
    while IFS= read -r line; do
        # Extract interface name
        interface=$(echo "$line" | awk '{print $2}' | sed 's/://')
        
        # Skip loopback
        if [ "$interface" = "lo" ]; then
            continue
        fi
        
        # Get IPv4 addresses for this interface
        ip_addresses=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^169\.254\.')
        
        if [ -n "$ip_addresses" ]; then
            # Check if interface is up
            state=$(cat "/sys/class/net/$interface/operstate" 2>/dev/null)
            if [ "$state" = "up" ]; then
                while IFS= read -r ip; do
                    if [ -n "$result" ]; then
                        result="${result}|"
                    fi
                    result="${result}${interface}:${ip}"
                done <<< "$ip_addresses"
            fi
        fi
    done < <(ip -o link show)
    
    echo "$result"
}

# Send notification to Discord
send_discord_notification() {
    local hostname="$1"
    local old_ips="$2"
    local new_ips="$3"
    local change_type="$4"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local description="**Hostname:** $hostname\n**Time:** $timestamp\n\n"
    local title=""
    local color=""
    
    if [ "$change_type" = "Initial" ]; then
        title="[INFO] IP Monitor Started"
        color=3447003  # Blue
        description="${description}**Current IP Addresses:**\n"
        
        IFS='|' read -ra ADDR <<< "$new_ips"
        for i in "${ADDR[@]}"; do
            interface=$(echo "$i" | cut -d':' -f1)
            ip=$(echo "$i" | cut -d':' -f2)
            description="${description}- **${interface}**: ${ip}\n"
        done
    else
        title="[CHANGE] IP Address Changed"
        color=15844367  # Orange
        description="${description}**IP Address Change Detected**\n\n"
        
        if [ -n "$old_ips" ]; then
            description="${description}**Previous IPs:**\n"
            IFS='|' read -ra ADDR <<< "$old_ips"
            for i in "${ADDR[@]}"; do
                interface=$(echo "$i" | cut -d':' -f1)
                ip=$(echo "$i" | cut -d':' -f2)
                description="${description}- **${interface}**: ${ip}\n"
            done
            description="${description}\n"
        fi
        
        description="${description}**New IPs:**\n"
        IFS='|' read -ra ADDR <<< "$new_ips"
        for i in "${ADDR[@]}"; do
            interface=$(echo "$i" | cut -d':' -f1)
            ip=$(echo "$i" | cut -d':' -f2)
            description="${description}- **${interface}**: ${ip}\n"
        done
    fi
    
    # Create JSON payload
    local iso_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local payload=$(cat <<EOF
{
  "embeds": [{
    "title": "$title",
    "description": "$description",
    "color": $color,
    "footer": {
      "text": "IP Change Monitor"
    },
    "timestamp": "$iso_timestamp"
  }]
}
EOF
)
    
    # Send to Discord
    local response=$(curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL")
    
    if [ "$response" = "204" ] || [ "$response" = "200" ]; then
        echo -e "${GREEN}[OK] Discord notification sent successfully${NC}"
        return 0
    else
        echo -e "${YELLOW}Warning: Failed to send Discord notification (HTTP $response)${NC}" >&2
        return 1
    fi
}

# Write log entry
write_log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Main monitoring loop
start_ip_monitoring() {
    echo -e "${CYAN}=== IP Change Notification Monitor ===${NC}"
    echo -e "${YELLOW}Loading configuration...${NC}"
    
    load_config
    
    local hostname=$(hostname)
    local previous_ips=""
    local is_first_run=true
    
    echo -e "${GREEN}Configuration loaded successfully${NC}"
    echo -e "${CYAN}Hostname: $hostname${NC}"
    echo -e "${CYAN}Check interval: $CHECK_INTERVAL seconds${NC}"
    echo -e "\n${YELLOW}Starting monitoring...${NC}"
    echo -e "${GRAY}Press Ctrl+C to stop${NC}\n"
    
    while true; do
        current_ips=$(get_current_ip_addresses)
        
        if [ "$is_first_run" = true ]; then
            # Send initial notification
            echo -e "${YELLOW}Sending initial notification...${NC}"
            write_log "Monitor started. Current IPs: $current_ips"
            
            send_discord_notification "$hostname" "" "$current_ips" "Initial"
            
            previous_ips="$current_ips"
            is_first_run=false
        elif [ "$previous_ips" != "$current_ips" ]; then
            # IP changed - send notification
            echo -e "\n${YELLOW}[WARNING] IP Address change detected!${NC}"
            write_log "IP change detected. Old: $previous_ips | New: $current_ips"
            
            send_discord_notification "$hostname" "$previous_ips" "$current_ips" "Change"
            
            previous_ips="$current_ips"
        else
            # No change
            local timestamp=$(date '+%H:%M:%S')
            echo -e "${GRAY}[$timestamp] No IP change detected${NC}"
        fi
        
        # Wait before next check
        sleep "$CHECK_INTERVAL"
    done
}

# Handle script termination
trap 'echo -e "\n${YELLOW}Monitoring stopped${NC}"; exit 0' INT TERM

# Start the monitoring
start_ip_monitoring
