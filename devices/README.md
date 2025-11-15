# Network Devices

This directory contains documentation and troubleshooting notes for devices on the network that are not part of the Kubernetes cluster.

## Device Inventory

| Device | Hostname/IP | Purpose | Credentials | Notes |
|--------|-------------|---------|-------------|-------|
| RetroPie | retropie.local | Game emulation | pi:raspberry | See [retropie.md](./retropie.md) |
| Home Assistant | homeassistant.local | Home automation | Default config | See [homeassistant.md](./homeassistant.md) |

## Organization

Each device should have its own markdown file with:
- Connection details
- Setup/configuration notes
- Common commands
- Troubleshooting history

Devices with complex configurations may have subdirectories containing:
- Backup scripts
- Configuration files
- Management tools

## Management Scripts

Some devices include helper scripts for common tasks:
- **RetroPie**: See [retropie/scripts/](./retropie/scripts/) for config backup/restore and ROM management
