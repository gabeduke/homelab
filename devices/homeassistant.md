# Home Assistant Device

## Connection Details

- **Purpose**: Home automation
- **OS**: Home Assistant OS (on Raspberry Pi)
- **Credentials**: Default configuration
- **Network**: Connected to network
- **Hostname**: `homeassistant`

## Web Access

```bash
# Default web interface
http://homeassistant:8123
# or
http://homeassistant.local:8123
```

## SSH Access

Home Assistant OS SSH access typically requires:
1. Installing the SSH add-on from the Add-on Store
2. Or using the Console access from the web UI

```bash
# If SSH add-on is configured
ssh root@homeassistant
```

## Common Commands

### Check Home Assistant Status
```bash
ha core info
ha core logs
```

### Restart Home Assistant
```bash
ha core restart
```

### System Info
```bash
ha info
ha os info
```

### Backup
```bash
ha backups list
ha backups new --name "manual-backup"
```

## Configuration

- **Config directory**: `/config`
- **Main config**: `/config/configuration.yaml`
- **Automations**: `/config/automations.yaml`
- **Secrets**: `/config/secrets.yaml`

## Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [Home Assistant OS](https://github.com/home-assistant/operating-system)
