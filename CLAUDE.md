# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@~/.claude/CLAUDE.md

## Project Overview

This is a local fork/customization of [dockur/windows](https://github.com/dockur/windows) — a project that runs Windows inside a Docker container using QEMU/KVM. The local additions add a one-click desktop launcher for Fedora/GNOME that starts the VM and connects via RDP (FreeRDP).

## Running the VM

### Prerequisites
- Docker with compose plugin
- KVM support (`/dev/kvm` device)
- FreeRDP (`xfreerdp`) installed for RDP connections
- A `.env` file in the repo root (see `.env.example` for required variables)

### Start / Stop
```bash
docker compose up -d       # Start
docker compose down        # Stop (graceful ACPI shutdown, 2m grace period)
```

### Desktop Launcher (Fedora/GNOME)
The `desktop/` directory contains a `.desktop` file and shell script that starts the container, waits for RDP, launches `xfreerdp`, and stops the container when the session closes. Install steps are in the README under "Local additions".

### Build the Docker Image Locally
```bash
docker build -t windows .
```

## Environment Variables

All VM configuration is driven by environment variables (set in `.env` or `compose.yml`):

| Variable | Purpose | Default |
|---|---|---|
| `VERSION` | Windows version to install | `"11"` |
| `RAM_SIZE` / `CPU_CORES` / `DISK_SIZE` | VM resources | `"4G"` / `"2"` / `"64G"` |
| `USERNAME` / `PASSWORD` | Windows login credentials | `Docker` / `admin` |
| `LANGUAGE` | Windows language | English |
| `MANUAL` | Skip automatic install (`"Y"`) | unset |

Compose references `$SELECTED_RAM`, `$SELECTED_CORES`, `$SELECTED_DISK` from `.env`.

## Architecture

### Container Entrypoint Pipeline (`src/entry.sh`)
The entrypoint sources scripts sequentially — each stage has a single responsibility:

1. **`define.sh`** — Parses `VERSION` env var into internal version IDs, defines all supported Windows versions/editions, language/locale mappings, and mirror URLs
2. **`mido.sh`** — Downloads Windows ISOs from Microsoft servers (handles retail + evaluation editions, ESD format, catalog parsing, retries, and mirror fallback)
3. **`install.sh`** — Extracts ISOs, detects Windows version/edition from WIM metadata, injects VirtIO drivers and unattended answer files (XML), rebuilds the ISO with `genisoimage`
4. **`samba.sh`** — Configures Samba shares for host-guest file sharing (`/shared` mount)
5. **`power.sh`** — Sets up QEMU process management: PID tracking, graceful ACPI shutdown via QEMU monitor, signal traps

Scripts sourced from the base image (`qemux/qemu`): `start.sh`, `utils.sh`, `reset.sh`, `server.sh`, `disk.sh`, `display.sh`, `network.sh`, `boot.sh`, `proc.sh`, `memory.sh`, `config.sh`, `finish.sh`.

### Answer Files (`assets/`)
XML unattended answer files for each Windows version/edition. Named by internal version ID (e.g., `win11x64.xml`). Injected into the boot WIM during installation to automate Windows setup.

### Ports
- **8006** — Web-based VNC viewer (noVNC) for installation and fallback access
- **3389** — RDP (TCP + UDP) for primary desktop access after installation

### Storage
- `/storage` — Persistent VM disk, ISO cache, and installation state files
- `/shared` — Samba-shared folder accessible from Windows desktop as "Shared"
