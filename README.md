# 🚀 Agent Icikiwir

Hermes Agent one-liner installer. Satu command, langsung jalan.

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/keinankairi-afk/agent-icikiwir/main/install.sh)
```

## Apa aja yang di-install?

1. ✅ Python, Node.js, git
2. ✅ Hermes Agent dari GitHub
3. ✅ 247+ skills (hacking, crypto, web dev)
4. ✅ Plugins (ponytail)
5. ✅ Config & memory templates
6. ✅ Systemd service (auto-start)
7. ✅ PATH & aliases

## Setelah Install

```bash
# 1. Edit API keys
nano ~/.hermes/.env

# 2. Start gateway
sudo systemctl start hermes-gateway

# 3. Cek status
sudo systemctl status hermes-gateway
```

## Quick Commands

| Alias | Command | Desc |
|-------|---------|------|
| `hm` | `hermes` | CLI |
| `hms` | `hermes gateway start` | Start |
| `hmr` | `hermes gateway restart` | Restart |
| `hml` | `hermes logs --follow` | Logs |
| `hmp` | `hermes plugins list` | Plugins |
| `hmsk` | `hermes skills list` | Skills |

## Requirements

- Ubuntu 20.04+ / Debian 11+
- 1GB+ RAM, 5GB+ disk
- Root/sudo access

## Files

```
~/.hermes/
├── config.yaml          # Config
├── .env                 # API keys
├── memories/            # Agent memory
├── skills/              # 247+ skills
├── plugins/             # Plugins
├── logs/                # Logs
└── cron/                # Scheduled tasks
```
