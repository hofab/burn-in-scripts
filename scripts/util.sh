#!/bin/bash
#
# utils.sh - Utility functions for disk burn-in testing
#
# This script provides system checks, drive discovery, and validation
# functions for the disk burn-in system.
#
# Usage: source this script in your main burn-in script
#

#
# Required applications for burn-in testing
#
REQUIRED_APPS=(
    "smartctl"      # SMART monitoring and testing
    "badblocks"     # Bad block scanning
    "lsblk"         # Block device listing
    "hdparm"        # Hard disk parameters
    "sync"          # File system sync
    "grep"          # Text processing
    "awk"           # Text processing
    "sed"           # Text processing
)

# Optional applications (will warn if missing but won't fail)
OPTIONAL_APPS=(
    "nvme"          # NVMe specific tools
    "sg_inq"        # SCSI inquiry (part of sg3-utils)
)

#
# System validation functions
#

# Check if all required applications are installed
check_required_apps() {
    local missing_apps=()
    local missing_optional=()

    echo "Checking required applications..."

    # Check required apps
    for app in "${REQUIRED_APPS[@]}"; do
        if ! command -v "$app" &> /dev/null; then
            missing_apps+=("$app")
        else
            echo "  ✓ $app found"
        fi
    done

    # Check optional apps
    for app in "${OPTIONAL_APPS[@]}"; do
        if ! command -v "$app" &> /dev/null; then
            missing_optional+=("$app")
        else
            echo "  ✓ $app found (optional)"
        fi
    done

    # Report missing required apps
    if [[ ${#missing_apps[@]} -gt 0 ]]; then
        echo ""
        echo "ERROR: Missing required applications:"
        for app in "${missing_apps[@]}"; do
            echo "  ✗ $app"
        done
        echo ""
        echo "Please install missing applications before running burn-in tests."
        return 1
    fi

    # Report missing optional apps
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo ""
        echo "WARNING: Missing optional applications:"
        for app in "${missing_optional[@]}"; do
            echo "  ! $app (some features may not be available)"
        done
        echo ""
    fi

    echo "Application check completed successfully."
    return 0
}

# Check if running as root (required for most disk operations)
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root for disk operations."
        echo "Please run with sudo or as root user."
        return 1
    fi

    echo "✓ Running with root privileges"
    return 0
}

# Check available disk space for logs
check_log_space() {
    local log_dir="$1"
    local min_space_mb="${2:-100}"  # Default 100MB minimum

    # Create log directory if it doesn't exist
    mkdir -p "$log_dir"

    # Get available space in MB
    local available_mb
    available_mb=$(df -m "$log_dir" | awk 'NR==2 {print $4}')

    if [[ "$available_mb" -lt "$min_space_mb" ]]; then
        echo "WARNING: Low disk space for logs. Available: ${available_mb}MB, Recommended: ${min_space_mb}MB"
        return 1
    fi

    echo "✓ Sufficient log space available: ${available_mb}MB"
    return 0
}

#
# Drive discovery and validation functions
#

# Get all block devices (excluding partitions, loop devices, etc.)
get_all_block_devices() {
    # Use lsblk to get all block devices, exclude partitions and special devices
    lsblk -ndo NAME,TYPE | grep -E "disk$" | awk '{print "/dev/" $1}' | sort
}

# Check if a drive has any partitions or file systems
is_drive_unformatted() {
    local device="$1"

    # Check if device exists
    if [[ ! -b "$device" ]]; then
        return 1
    fi

    # Use lsblk to check for partitions and filesystems
    # Get all information about the device and its children
    local lsblk_output
    lsblk_output=$(lsblk -no NAME,TYPE,FSTYPE,MOUNTPOINT "$device" 2>/dev/null)

    # Check if there are any partitions (TYPE=part)
    if echo "$lsblk_output" | grep -q "part"; then
        return 1
    fi

    # Check if there's any filesystem on the main device
    local fstype
    fstype=$(echo "$lsblk_output" | grep "disk" | awk '{print $3}')
    if [[ -n "$fstype" ]]; then
        return 1
    fi

    # Check if anything is mounted
    if echo "$lsblk_output" | grep -q "/"; then
        return 1
    fi

    # If we get here, drive appears unformatted
    return 0
}

# Get all unformatted drives
get_unformatted_drives() {
    local all_devices
    local unformatted_drives=()

    echo "Discovering unformatted drives..."

    # Get all block devices
    mapfile -t all_devices < <(get_all_block_devices)

    if [[ ${#all_devices[@]} -eq 0 ]]; then
        echo "No block devices found."
        return 1
    fi

    # Check each device
    for device in "${all_devices[@]}"; do
        echo "  Checking $device..."

        if is_drive_unformatted "$device"; then
            unformatted_drives+=("$device")
            echo "    ✓ Unformatted"
        else
            echo "    ✗ Has partitions/filesystem"
        fi
    done

    # Return results
    if [[ ${#unformatted_drives[@]} -eq 0 ]]; then
        echo "No unformatted drives found."
        return 1
    fi

    echo ""
    echo "Found ${#unformatted_drives[@]} unformatted drive(s):"
    for drive in "${unformatted_drives[@]}"; do
        echo "  $drive"
    done

    # Return drives as array (caller should use: mapfile -t drives < <(get_unformatted_drives))
    printf '%s\n' "${unformatted_drives[@]}"
    return 0
}

# Get drive information (size, model, serial)
get_drive_info() {
    local device="$1"

    if [[ ! -b "$device" ]]; then
        echo "ERROR: Device $device does not exist"
        return 1
    fi

    echo "Drive Information for $device:"

    # Get basic info from lsblk
    local size model
    size=$(lsblk -ndo SIZE "$device" 2>/dev/null)
    model=$(lsblk -ndo MODEL "$device" 2>/dev/null)

    echo "  Size: ${size:-Unknown}"
    echo "  Model: ${model:-Unknown}"

    # Get SMART info if available
    if command -v smartctl &> /dev/null; then
        local smart_info
        smart_info=$(smartctl -i "$device" 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            local serial vendor family
            serial=$(echo "$smart_info" | grep "Serial Number" | awk -F: '{print $2}' | xargs)
            vendor=$(echo "$smart_info" | grep "Vendor" | awk -F: '{print $2}' | xargs)
            family=$(echo "$smart_info" | grep "Product Family" | awk -F: '{print $2}' | xargs)

            echo "  Serial: ${serial:-Unknown}"
            echo "  Vendor: ${vendor:-Unknown}"
            echo "  Family: ${family:-Unknown}"
        else
            echo "  SMART: Not available"
        fi
    fi

    # Get partition table info using lsblk
    echo "  Partition info:"
    local partition_info
    partition_info=$(lsblk -o NAME,SIZE,TYPE,FSTYPE "$device" 2>/dev/null)
    if [[ -n "$partition_info" ]]; then
        echo "$partition_info" | sed 's/^/    /'
    else
        echo "    No partition information available"
    fi

    return 0
}

# Validate that a drive is safe for testing
validate_drive_for_testing() {
    local device="$1"
    local force="${2:-false}"

    echo "Validating $device for burn-in testing..."

    # Check if device exists
    if [[ ! -b "$device" ]]; then
        echo "ERROR: Device $device does not exist"
        return 1
    fi

    # Check if device is mounted
    if mount | grep -q "^$device"; then
        echo "ERROR: Device $device is currently mounted"
        echo "Please unmount before testing."
        return 1
    fi

    # Check for partitions (unless forced)
    if [[ "$force" != "true" ]] && ! is_drive_unformatted "$device"; then
        echo "ERROR: Device $device appears to have partitions or filesystem"
        echo "Use --force to override this safety check."
        return 1
    fi

    # Check if device is busy
    if lsof "$device" 2>/dev/null | grep -q "$device"; then
        echo "ERROR: Device $device is currently in use by another process"
        return 1
    fi

    # Check SMART availability
    if command -v smartctl &> /dev/null; then
        local smart_available
        smart_available=$(smartctl -i "$device" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "WARNING: SMART not available for $device"
        else
            echo "  ✓ SMART available"
        fi
    fi

    echo "  ✓ Device $device validated for testing"
    return 0
}

#
# System information functions
#

# Get system information
get_system_info() {
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "OS: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo "Memory: $(free -h | grep "Mem:" | awk '{print $2}')"
    echo "Date: $(date)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo "=========================="
}

# Check system load and resources
check_system_resources() {
    local max_load="${1:-4.0}"  # Default max load average
    local min_memory_gb="${2:-1}"  # Default minimum memory in GB

    echo "Checking system resources..."

    # Check load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F, '{print $1}' | xargs)

    if (( $(echo "$load_avg > $max_load" | bc -l) )); then
        echo "WARNING: High system load: $load_avg (threshold: $max_load)"
    else
        echo "  ✓ System load acceptable: $load_avg"
    fi

    # Check available memory
    local available_gb
    available_gb=$(free -g | grep "Mem:" | awk '{print $7}')

    if [[ "$available_gb" -lt "$min_memory_gb" ]]; then
        echo "WARNING: Low available memory: ${available_gb}GB (minimum: ${min_memory_gb}GB)"
    else
        echo "  ✓ Available memory sufficient: ${available_gb}GB"
    fi

    return 0
}

#
# Utility helper functions
#

# Convert seconds to human readable format
seconds_to_human() {
    local seconds="$1"
    local days hours minutes

    days=$((seconds / 86400))
    hours=$(((seconds % 86400) / 3600))
    minutes=$(((seconds % 3600) / 60))
    seconds=$((seconds % 60))

    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m ${seconds}s"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m ${seconds}s"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Get device short name (e.g., /dev/sda -> sda)
get_device_short_name() {
    local device="$1"
    basename "$device"
}

# Check if device supports SMART
supports_smart() {
    local device="$1"

    if ! command -v smartctl &> /dev/null; then
        return 1
    fi

    smartctl -i "$device" &>/dev/null
    return $?
}

# Prompt user for confirmation
confirm_action() {
    local message="$1"
    local default="${2:-n}"  # Default to 'no'

    if [[ "$default" == "y" ]]; then
        read -p "$message [Y/n]: " -r response
        [[ -z "$response" || "$response" =~ ^[Yy]$ ]]
    else
        read -p "$message [y/N]: " -r response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

check_requirements() {
  for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null; then
      echo -e "${RED}Missing required tool: $cmd${NC}"
      exit 1
    fi
  done
}

discover_drives() {
  lsblk -ndo NAME,TYPE | awk '$2 == "disk" { print "/dev/" $1 }'
}

filter_safe_drives() {
  local all_drives=("$@")
  local safe_drives=()

  for dev in "${all_drives[@]}"; do
    if [[ $FORCE -eq 0 ]] && lsblk "$dev" | grep -q part; then
      log "Skipping $dev (has partitions)"
    else
      safe_drives+=("$dev")
    fi
  done

  echo "${safe_drives[@]}"
}

#
# Export functions for use in other scripts
#
export -f check_required_apps check_root_privileges check_log_space
export -f get_all_block_devices is_drive_unformatted get_unformatted_drives
export -f get_drive_info validate_drive_for_testing
export -f get_system_info check_system_resources
export -f seconds_to_human get_device_short_name supports_smart confirm_action
