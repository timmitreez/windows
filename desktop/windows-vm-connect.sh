#!/bin/bash

# Configuration
VM_COMPOSE_DIR="/Path/To/This/Repo"
RDP_HOST="127.0.0.1"
RDP_PORT="3389"
WIN_USER="tt"
WIN_PASS="1234"

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
xfreerdp /v:${RDP_HOST}:${RDP_PORT} /u:${WIN_USER} /p:${WIN_PASS} /cert:ignore +workarea -decorations -grab-keyboard
echo "Connection closed. Stopping Windows VM..."
cd "$VM_COMPOSE_DIR" || exit 1
docker compose down

echo "Windows VM stopped"
