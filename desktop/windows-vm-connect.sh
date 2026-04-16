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
MAX_RETRIES=30
while [ "$RETRIES" -lt "$MAX_RETRIES" ]; do
    xfreerdp /v:${RDP_HOST}:${RDP_PORT} /u:${USERNAME} /p:${PASSWORD} /cert:ignore +workarea -decorations -grab-keyboard
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
