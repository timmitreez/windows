#!/bin/bash

# Load configuration from .env in the repo root
VM_COMPOSE_DIR="$HOME/Documents/Personal/windows"
set -a
# shellcheck source=../.env
source "$VM_COMPOSE_DIR/.env"
set +a

# Start the VM
cd "$VM_COMPOSE_DIR" || exit 1
docker compose up -d
sleep 4
# Wait for RDP to be available
echo "Waiting for RDP service..."
for i in {1..30}; do
    if nc -z "$RDP_HOST" "$RDP_PORT" 2>/dev/null; then
        echo "RDP service is ready"
        break
    fi
    sleep 1
done

# Launch GNOME Connections with RDP URL
# Format: rdp://username:password@host:port
xfreerdp /v:${RDP_HOST}:${RDP_PORT} /u:${USERNAME} /p:${PASSWORD} /cert:ignore +workarea -decorations -grab-keyboard
echo "Connection closed. Stopping Windows VM..."
cd "$VM_COMPOSE_DIR" || exit 1
docker compose down

echo "Windows VM stopped"
