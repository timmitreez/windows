#!/bin/bash

# Load configuration from .env in the repo root
VM_COMPOSE_DIR="$HOME/Documents/Personal/windows"
set -a
# shellcheck source=../.env
source "$VM_COMPOSE_DIR/.env"
set +a

notify() {
    notify-send -i computer "Windows VM" "$1" 2>/dev/null
}

# Determine xfreerdp display arguments based on connected monitors.
#
# Configurable via RDP_MONITOR env var (set in .env):
#   auto     — (default) laptop monitor when multi-monitor, workarea when single
#   workarea — always use borderless workarea mode (original behavior)
#   <number> — fullscreen on that xfreerdp monitor ID (see: xfreerdp /list:monitor)
get_display_args() {
    local rdp_monitor="${RDP_MONITOR:-auto}"

    # Explicit workarea override — skip detection entirely
    if [ "$rdp_monitor" = "workarea" ]; then
        echo "+workarea -decorations"
        return
    fi

    # Explicit monitor ID — fullscreen on that monitor
    if [[ "$rdp_monitor" =~ ^[0-9]+$ ]]; then
        echo "/f /monitors:${rdp_monitor}"
        return
    fi

    # Auto mode: detect monitors
    local monitor_list
    monitor_list=$(xfreerdp /list:monitor 2>/dev/null)
    local monitor_count
    monitor_count=$(echo "$monitor_list" | grep -cP '^\s*[\*\s]*\[\d+\]')

    if [ "$monitor_count" -le 1 ]; then
        echo "+workarea -decorations"
        return
    fi

    # Multiple monitors — find the laptop (eDP) screen
    local laptop_res
    laptop_res=$(xrandr --listmonitors 2>/dev/null \
        | grep -i 'eDP' \
        | grep -oP '\d+(?=/\d+x)' | head -1)
    local laptop_height
    laptop_height=$(xrandr --listmonitors 2>/dev/null \
        | grep -i 'eDP' \
        | grep -oP '(?<=x)\d+(?=/)')

    local target_id=""
    if [ -n "$laptop_res" ] && [ -n "$laptop_height" ]; then
        local match_res="${laptop_res}x${laptop_height}"
        target_id=$(echo "$monitor_list" \
            | grep -P "\[\d+\]\s+${match_res}\b" \
            | grep -oP '\[\K\d+' | head -1)
    fi

    # Fallback: primary monitor (marked with *)
    if [ -z "$target_id" ]; then
        target_id=$(echo "$monitor_list" \
            | grep '^\s*\*' \
            | grep -oP '\[\K\d+' | head -1)
    fi

    # Final fallback: monitor 0
    target_id="${target_id:-0}"

    echo "/f /monitors:${target_id}"
}

DISPLAY_ARGS=$(get_display_args)

# Start the VM
cd "$VM_COMPOSE_DIR" || exit 1
notify "Starting Windows VM..."
docker compose up -d

# Wait for RDP to become available (up to 5 minutes)
MAX_WAIT=300
WAITED=0
notify "Waiting for RDP service to be ready..."
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
    if nc -z "$RDP_HOST" "$RDP_PORT" 2>/dev/null; then
        notify "RDP is ready — connecting..."
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    notify "RDP did not become available after ${MAX_WAIT}s. Stopping VM."
    docker compose down
    exit 1
fi

# Connect via FreeRDP, retrying on failure.
# The RDP port can be open before Windows is ready to accept logins —
# xfreerdp exits non-zero when the connection fails, and 0 when the
# user closes a successful session.
RETRIES=0
MAX_RETRIES=6
while [ "$RETRIES" -lt "$MAX_RETRIES" ]; do
    # shellcheck disable=SC2086
    xfreerdp /v:${RDP_HOST}:${RDP_PORT} /u:${USERNAME} /p:${PASSWORD} /cert:ignore ${DISPLAY_ARGS} -grab-keyboard
    RC=$?

    if [ "$RC" -eq 0 ]; then
        break
    fi

    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -lt "$MAX_RETRIES" ]; then
        notify "RDP not ready yet, retrying... (${RETRIES}/${MAX_RETRIES})"
        sleep 5
    fi
done

if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    notify "Could not establish RDP session after ${MAX_RETRIES} attempts. Stopping VM."
    cd "$VM_COMPOSE_DIR" || exit 1
    docker compose down
    exit 1
fi

notify "Connection closed. Stopping Windows VM..."
cd "$VM_COMPOSE_DIR" || exit 1
docker compose down
notify "Windows VM stopped."
