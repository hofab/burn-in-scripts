i#!/bin/bash
#
# logging.sh - Comprehensive logging functions for disk burn-in testing
#
# This script provides logging, temperature monitoring, and status tracking
# functions for the disk burn-in system.
#
# Usage: source this script in your main burn-in script
#

# Global variables for logging configuration
LOG_DIR="/var/log/disk-burnin"
LOG_FILE="${LOG_DIR}/burnin-$(date +%Y%m%d-%H%M%S).log"
TEMP_LOG_FILE="${LOG_DIR}/temperature-$(date +%Y%m%d-%H%M%S).csv"
ENABLE_TIMESTAMPS=true
TEMP_MONITOR_INTERVAL=60  # seconds
MAX_TEMP_THRESHOLD=55     # Celsius

# Array to track monitored drives for temperature logging
declare -a MONITORED_DRIVES=()

#
# Core logging functions
#

# Initialize logging system
init_logging() {
    local drives=("$@")

    # Store drives for temperature monitoring
    MONITORED_DRIVES=("${drives[@]}")

    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"

    # Set up main log file with header
    {
        echo "=== Disk Burn-in Test Started: $(date) ==="
        echo "Log Directory: $LOG_DIR"
        echo "Monitored Drives: ${MONITORED_DRIVES[*]}"
        echo "Temperature Threshold: ${MAX_TEMP_THRESHOLD}°C"
        echo "Temperature Monitor Interval: ${TEMP_MONITOR_INTERVAL}s"
        echo "================================================"
        echo ""
    } > "$LOG_FILE"

    # Initialize temperature CSV with header
    if [[ ${#MONITORED_DRIVES[@]} -gt 0 ]]; then
        {
            printf "timestamp"
            for drive in "${MONITORED_DRIVES[@]}"; do
                printf ",%s" "$drive"
            done
            printf "\n"
        } > "$TEMP_LOG_FILE"
    fi

    log_message "Logging system initialized for drives: ${MONITORED_DRIVES[*]}"
}

# Clean up logging resources
cleanup_logging() {
    log_message "Cleaning up logging system..."

    # Stop background processes
    cleanup_bg_processes

    # Log final summary
    {
        echo ""
        echo "=== Disk Burn-in Test Completed: $(date) ==="
        echo "Final temperature readings saved to: $TEMP_LOG_FILE"
        echo "================================================"
    } >> "$LOG_FILE"
}

# Simple logging function
log_message() {
    local message="$1"
    local device="$2"  # Optional device identifier

    local timestamp
    timestamp=$(get_timestamp)

    if [[ -n "$device" ]]; then
        echo "[$timestamp] [$device] $message" | tee -a "$LOG_FILE"
    else
        echo "[$timestamp] $message" | tee -a "$LOG_FILE"
    fi
}

# Log command start
log_command_start() {
    local command="$1"
    local device="$2"

    log_message "STARTED: $command" "$device"
}

# Log command completion
log_command_finish() {
    local command="$1"
    local device="$2"
    local exit_code="$3"
    local duration="$4"  # Optional

    local status_msg="FINISHED: $command (exit code: $exit_code)"
    if [[ -n "$duration" ]]; then
        status_msg="$status_msg [duration: ${duration}s]"
    fi

    log_message "$status_msg" "$device"
}

#
# Temperature monitoring functions
#

# Set up temperature monitoring for drives
setup_temp_monitoring() {
    local drives=("$@")

    # This function is now redundant since init_logging handles this
    # But kept for compatibility
    if [[ ${#drives[@]} -gt 0 ]]; then
        MONITORED_DRIVES=("${drives[@]}")
        log_message "Temperature monitoring setup for: ${MONITORED_DRIVES[*]}"
    fi
}

# Start temperature monitoring for all drives
start_temp_monitoring() {
    if [[ ${#MONITORED_DRIVES[@]} -eq 0 ]]; then
        log_message "No drives configured for temperature monitoring"
        return 1
    fi

    log_message "Starting temperature monitoring (interval: ${TEMP_MONITOR_INTERVAL}s)"

    # Start background temperature monitoring
    (
        while true; do
            log_all_temperatures
            sleep "$TEMP_MONITOR_INTERVAL"
        done
    ) &

    local temp_monitor_pid=$!
    track_bg_process "$temp_monitor_pid"

    log_message "Temperature monitoring started (PID: $temp_monitor_pid)"
}

# Stop temperature monitoring
stop_temp_monitoring() {
    log_message "Stopping temperature monitoring..."

    # The cleanup_bg_processes function will handle stopping the background process
    # Log final temperature reading
    log_all_temperatures

    log_message "Temperature monitoring stopped"
}

# Get current temperature for a specific drive
get_drive_temperature() {
    local device="$1"

    # Use smartctl to get current temperature
    local temp_output
    temp_output=$(smartctl -A "$device" 2>/dev/null | grep -i temperature | head -1)

    if [[ -n "$temp_output" ]]; then
        # Extract temperature value (usually in column 10 for most drives)
        local temp
        temp=$(echo "$temp_output" | awk '{print $10}')

        # Validate it's a number
        if [[ "$temp" =~ ^[0-9]+$ ]]; then
            echo "$temp"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Log temperature readings for all monitored drives
log_all_temperatures() {
    if [[ ${#MONITORED_DRIVES[@]} -eq 0 ]]; then
        return 1
    fi

    local timestamp
    timestamp=$(get_timestamp)

    # Build CSV line
    local csv_line="$timestamp"
    local temps=()
    local overheating_drives=()

    for drive in "${MONITORED_DRIVES[@]}"; do
        local temp
        temp=$(get_drive_temperature "$drive")
        temps+=("$temp")
        csv_line="$csv_line,$temp"

        # Check temperature threshold
        if [[ "$temp" != "N/A" && "$temp" -gt "$MAX_TEMP_THRESHOLD" ]]; then
            overheating_drives+=("$drive:${temp}°C")
        fi
    done

    # Write to temperature log
    echo "$csv_line" >> "$TEMP_LOG_FILE"

    # Log warnings for overheating drives
    if [[ ${#overheating_drives[@]} -gt 0 ]]; then
        log_message "WARNING: High temperature detected - ${overheating_drives[*]}"
    fi
}

# Check if any drive temperature exceeds threshold
check_temperature_thresholds() {
    local overheating_drives=()

    for drive in "${MONITORED_DRIVES[@]}"; do
        local temp
        temp=$(get_drive_temperature "$drive")

        if [[ "$temp" != "N/A" && "$temp" -gt "$MAX_TEMP_THRESHOLD" ]]; then
            overheating_drives+=("$drive")
            log_message "Temperature threshold exceeded: $drive = ${temp}°C (threshold: ${MAX_TEMP_THRESHOLD}°C)" "$drive"
        fi
    done

    # Return overheating drives as space-separated string
    echo "${overheating_drives[*]}"
}

#
# SMART status monitoring functions
#

# Log initial SMART status for a device
log_smart_baseline() {
    local device="$1"

    # Get and log comprehensive baseline SMART data
    # Save for later comparison
    :
}

# Log final SMART status for a device
log_smart_final() {
    local device="$1"

    # Get final SMART data
    # Compare with baseline if available
    # Log any changes or issues
    :
}

# Quick SMART health check
check_smart_health() {
    local device="$1"

    # Check SMART overall health status
    # Return PASSED/FAILED
    # Log any immediate concerns
    :
}

#
# Summary and reporting functions
#

# Generate summary report for a device
generate_device_summary() {
    local device="$1"

    # Create comprehensive test summary for single device
    # Include test results, temperature stats, SMART comparison
    # Format for easy reading
    :
}

# Generate overall burn-in summary
generate_burnin_summary() {
    local devices=("$@")

    # Create summary of all devices tested
    # Overall statistics and results
    # Temperature summary (min/max/avg for each drive)
    # List any failures or issues
    # Overall pass/fail status
    :
}

# Generate temperature statistics
generate_temp_summary() {
    # Parse temperature CSV file
    # Calculate min/max/average for each drive
    # Identify any temperature threshold violations
    # Create temperature summary report
    :
}

#
# Utility functions
#

# Check if logging system is properly initialized
is_logging_initialized() {
    # Check if log directory exists and is writable
    [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] &&
    # Check if main log file exists and is writable
    [[ -f "$LOG_FILE" && -w "$LOG_FILE" ]] &&
    # Check if we have drives configured
    [[ ${#MONITORED_DRIVES[@]} -gt 0 ]]
}

# Get timestamp in consistent format
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Print current logging configuration
show_logging_config() {
    echo "=== Logging Configuration ==="
    echo "Log Directory: $LOG_DIR"
    echo "Main Log File: $LOG_FILE"
    echo "Temperature Log File: $TEMP_LOG_FILE"
    echo "Temperature Monitor Interval: ${TEMP_MONITOR_INTERVAL}s"
    echo "Temperature Threshold: ${MAX_TEMP_THRESHOLD}°C"
    echo "Monitored Drives: ${MONITORED_DRIVES[*]}"
    echo "Timestamps Enabled: $ENABLE_TIMESTAMPS"
    echo "============================="
}

#
# Background process management
#

# List of background process PIDs for cleanup
declare -a BG_PIDS=()

# Add a background process PID to tracking
track_bg_process() {
    local pid="$1"
    BG_PIDS+=("$pid")
}

# Clean up all background processes
cleanup_bg_processes() {
    for pid in "${BG_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_message "Stopping background process: $pid"
            kill "$pid" 2>/dev/null

            # Wait a bit for graceful shutdown
            sleep 2

            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                log_message "Force killing background process: $pid"
                kill -9 "$pid" 2>/dev/null
            fi
        fi
    done

    # Clear the array
    BG_PIDS=()
}

# Signal handler for cleanup
cleanup_handler() {
    log_info "Cleaning up logging processes..."
    cleanup_bg_processes
    cleanup_logging
}

# Set up signal handlers
trap cleanup_handler EXIT INT TERM

# Export functions for use in other scripts
export -f init_logging cleanup_logging
export -f log_message log_command_start log_command_finish
export -f setup_temp_monitoring start_temp_monitoring stop_temp_monitoring
export -f get_drive_temperature log_all_temperatures check_temperature_thresholds
export -f log_smart_baseline log_smart_final check_smart_health
export -f generate_device_summary generate_burnin_summary generate_temp_summary
export -f is_logging_initialized get_timestamp show_logging_config
export -f track_bg_process cleanup_bg_processes cleanup_handler


## Usage:

## Discover drives (in main script)
# drives=("/dev/sda" "/dev/sdb" "/dev/sdc")

# Initialize logging with discovered drives
# source logging.sh
# init_logging "${drives[@]}"

# Start temperature monitoring
# start_temp_monitoring

# Log commands
# log_command_start "badblocks -wsv /dev/sda" "/dev/sda"
# ... run command ...
# log_command_finish "badblocks -wsv /dev/sda" "/dev/sda" "$?" "3600"

