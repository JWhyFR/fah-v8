#!/bin/bash

# --- ROBUST AUTOMATIC DETECTION OF PRIMARY INTERFACE ---
get_default_interface() {
    local iface=""
    if command -v ip >/dev/null 2>&1; then
        iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1)
    fi
    if [ -z "$iface" ] && command -v route >/dev/null 2>&1; then
        iface=$(route -n 2>/dev/null | awk '/^0\.0\.0\.0/ {print $8}' | head -n 1)
    fi
    if [ -z "$iface" ] && [ -f /proc/net/dev ]; then
        iface=$(awk -F: '/:/ {print $1}' /proc/net/dev | tr -d ' ' | grep -v '^lo$' | head -n 1)
    fi
    echo "${iface:-eth0}"
}

INTERFACE=$(get_default_interface)
IFACE_PATH="/sys/class/net/$INTERFACE/statistics"

if [ ! -d "$IFACE_PATH" ]; then
    echo "Error: Unable to access statistics for interface '$INTERFACE'."
    exit 1
fi

# --- DEFAULT THRESHOLDS (IN MB) ---
MAX_MB_5M=200
MAX_MB_20M=300
MAX_MB_60M=400

# --- NAMED ARGUMENTS PARSING ---
for arg in "$@"; do
    case "$arg" in
        5M=*)  MAX_MB_5M="${arg#*=}" ;;
        20M=*) MAX_MB_20M="${arg#*=}" ;;
        60M=*) MAX_MB_60M="${arg#*=}" ;;
        *)     echo "[WARNING] Unknown option ignored: $arg" ;;
    esac
done

# Conversion to bytes
THRESH_5M=$((MAX_MB_5M * 1024 * 1024))
THRESH_20M=$((MAX_MB_20M * 1024 * 1024))
THRESH_60M=$((MAX_MB_60M * 1024 * 1024))

# --- COOLDOWN STATE VARIABLES ---
alert_active_dl_5m=0; alert_active_ul_5m=0
alert_active_dl_20m=0; alert_active_ul_20m=0
alert_active_dl_60m=0; alert_active_ul_60m=0

# Minute tick counter for hourly summary
tick_counter=0

# --- STARTUP BANNER (BUFFERED) ---
startup_msg=$(cat <<EOF
========================================
Script started at: $(date +'%Y-%m-%d %H:%M:%S')
Detected network interface: $INTERFACE
Configured MB alert thresholds:
 - 5 minutes  : ${MAX_MB_5M} MB
 - 20 minutes : ${MAX_MB_20M} MB
 - 60 minutes : ${MAX_MB_60M} MB
Monitoring network usage...
========================================
EOF
)
echo "$startup_msg"

declare -a hist_rx
declare -a hist_tx

hist_rx[0]=$(cat "$IFACE_PATH/rx_bytes")
hist_tx[0]=$(cat "$IFACE_PATH/tx_bytes")

check_alert() {
    local minutes=$1
    local threshold=$2
    local label=$3
    local var_dl_name="alert_active_dl_${minutes}m"
    local var_ul_name="alert_active_ul_${minutes}m"
    
    if [ ${#hist_rx[@]} -gt "$minutes" ]; then
        local current_rx=${hist_rx[0]}
        local current_tx=${hist_tx[0]}
        local past_rx=${hist_rx[$minutes]}
        local past_tx=${hist_tx[$minutes]}

        local dl_bytes=$((current_rx - past_rx))
        local ul_bytes=$((current_tx - past_tx))

        # --- DOWNLOAD ALERT ---
        if [ "$dl_bytes" -gt "$threshold" ]; then
            if [ "${!var_dl_name}" -eq 0 ]; then
                local dl_mo=$((dl_bytes / 1024 / 1024))
                echo "[$(date +'%H:%M:%S')] [ALERT] DOWNLOAD ($INTERFACE): $dl_mo MB downloaded in $minutes min! (Threshold: ${label}) | Cooldown active: alert muted for at least $minutes min."
                eval "$var_dl_name=1"
            fi
        else
            eval "$var_dl_name=0"
        fi

        # --- UPLOAD ALERT ---
        if [ "$ul_bytes" -gt "$threshold" ]; then
            if [ "${!var_ul_name}" -eq 0 ]; then
                local ul_mo=$((ul_bytes / 1024 / 1024))
                echo "[$(date +'%H:%M:%S')] [ALERT] UPLOAD ($INTERFACE): $ul_mo MB uploaded in $minutes min! (Threshold: ${label}) | Cooldown active: alert muted for at least $minutes min."
                eval "$var_ul_name=1"
            fi
        else
            eval "$var_ul_name=0"
        fi
    fi
}

print_periodic_summary() {
    local summary_buf
    if [ ${#hist_rx[@]} -gt 60 ]; then
        local dl_bytes=$((hist_rx[0] - hist_rx[60]))
        local ul_bytes=$((hist_tx[0] - hist_tx[60]))
        local dl_mo=$((dl_bytes / 1024 / 1024))
        local ul_mo=$((ul_bytes / 1024 / 1024))
        summary_buf=$(cat <<EOF
----------------------------------------
[$(date +'%H:%M:%S')] [HOURLY REPORT] Usage over the last hour on $INTERFACE:
 - DL = ${dl_mo} MB 
 - UL = ${ul_mo} MB
----------------------------------------
EOF
)
    else
        summary_buf=$(cat <<EOF
----------------------------------------
[$(date +'%H:%M:%S')] [HOURLY REPORT] Usage over the last hour on $INTERFACE:
 - Insufficient data (${#hist_rx[@]} min logged)
----------------------------------------
EOF
)
    fi
    echo "$summary_buf"
}

while true; do
    sleep 60
    
    current_rx=$(cat "$IFACE_PATH/rx_bytes")
    current_tx=$(cat "$IFACE_PATH/tx_bytes")
    
    hist_rx=("$current_rx" "${hist_rx[@]}")
    hist_rx=("${hist_rx[@]:0:61}")
    
    hist_tx=("$current_tx" "${hist_tx[@]}")
    hist_tx=("${hist_tx[@]:0:61}")

    check_alert 5 "$THRESH_5M" "${MAX_MB_5M}MB"
    check_alert 20 "$THRESH_20M" "${MAX_MB_20M}MB"
    check_alert 60 "$THRESH_60M" "${MAX_MB_60M}MB"

    ((tick_counter++))
    if [ "$tick_counter" -ge 60 ]; then
        print_periodic_summary
        tick_counter=0
    fi
done
