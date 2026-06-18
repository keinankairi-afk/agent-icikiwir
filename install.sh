#!/bin/bash
# ============================================================
#  Agent Icikiwir - Hermes Agent One-Liner Installer v1.2
#  Ramah pemula, auto-setup di VPS baru
#
#  Usage:
#    sudo bash <(curl -sL https://raw.githubusercontent.com/keinankairi-afk/agent-icikiwir/main/install.sh)
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Config
REPO_OWNER="keinankairi-afk"
REPO_NAME="agent-icikiwir"
RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

# Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# Detect piped mode (curl | bash)
is_piped() { [ ! -t 0 ]; }

# Download file from GitHub
download() {
    local dest="$1"
    local path="$2"
    curl -sL "${RAW_URL}/${path}" -o "$dest" 2>/dev/null || warn "Failed to download: $path"
}

# ============================================================
# STEP 0: Pre-flight checks
# ============================================================
header "🚀 Agent Icikiwir Installer v1.2"

if [ "$(uname -s)" != "Linux" ]; then
    error "This installer only supports Linux (Ubuntu/Debian)"
fi

ARCH=$(uname -m)
OS=$(uname -s)
info "System: $OS $ARCH"

if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash install.sh"
fi

# ============================================================
# STEP 1: System dependencies
# ============================================================
header "📦 Installing System Dependencies"

apt-get update -qq || error "apt-get update failed"
apt-get install -y -qq \
    python3 python3-pip python3-venv \
    git curl wget unzip sqlite3 jq \
    build-essential libssl-dev libffi-dev \
    > /dev/null 2>&1 || error "Failed to install system packages"

log "System packages installed"

# Check Python (portable, no grep -oP)
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "unknown")
info "Python: $PYTHON_VERSION"

# ============================================================
# STEP 2: Install Node.js
# ============================================================
header "📦 Installing Node.js"

if command -v node &> /dev/null; then
    log "Node.js already installed: $(node --version)"
else
    curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
    bash /tmp/nodesource_setup.sh > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
    rm -f /tmp/nodesource_setup.sh
    log "Node.js installed: $(node --version)"
fi

# ============================================================
# STEP 3: Clone Hermes Agent
# ============================================================
header "📥 Installing Hermes Agent"

HERMES_HOME="$HOME/.hermes"
HERMES_AGENT="$HOME/hermes-agent"

if [ -d "$HERMES_AGENT" ]; then
    warn "Hermes Agent already exists at $HERMES_AGENT"
    if is_piped; then
        warn "Piped mode: overwriting in 3s (Ctrl+C to abort)"
        sleep 3
        rm -rf "$HERMES_AGENT"
    else
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$HERMES_AGENT"
        else
            info "Skipping clone"
        fi
    fi
fi

if [ ! -d "$HERMES_AGENT" ]; then
    git clone --depth 1 https://github.com/NousResearch/hermes-agent.git "$HERMES_AGENT" || error "Failed to clone Hermes Agent"
    log "Hermes Agent cloned"
fi

# ============================================================
# STEP 4: Setup Python venv
# ============================================================
header "🐍 Setting up Python Environment"

cd "$HERMES_AGENT"

if [ ! -d ".venv" ]; then
    python3 -m venv .venv || error "Failed to create venv"
    log "Virtual environment created"
fi

# Activate venv (with error handling)
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
else
    error "venv activate script not found"
fi

pip install --upgrade pip -q 2>/dev/null || true
pip install -r requirements.txt -q 2>/dev/null || pip install -e . -q 2>/dev/null || warn "Some Python deps may be missing"
log "Python dependencies installed"

# ============================================================
# STEP 5: Setup Hermes Home
# ============================================================
header "📁 Setting up Hermes Home"

mkdir -p "$HERMES_HOME"/{skills,plugins,memories,logs,cron,cache}

# ============================================================
# STEP 5.5: Choose LLM Provider
# ============================================================
header "🤖 Choose Your LLM Provider"

PROVIDER_NAME=""
PROVIDER_MODEL=""
PROVIDER_URL=""
PROVIDER_ENV_KEY=""

if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    echo -e "  ${CYAN}Pilih provider LLM:${NC}"
    echo ""
    echo -e "  ${BLUE}1.${NC} Xiaomi (MiMo)        — ${YELLOW}Gratis${NC}, API key dari mi.com"
    echo -e "  ${BLUE}2.${NC} Groq                 — ${YELLOW}Gratis${NC}, Llama 3.3 70B, cepat"
    echo -e "  ${BLUE}3.${NC} OpenRouter           — ${YELLOW}Bayar${NC}, semua model (Claude, GPT, dll)"
    echo -e "  ${BLUE}4.${NC} OpenAI               — ${YELLOW}Bayar${NC}, GPT-4o / o3"
    echo -e "  ${BLUE}5.${NC} Anthropic            — ${YELLOW}Bayar${NC}, Claude Sonnet/Opus"
    echo -e "  ${BLUE}6.${NC} DeepSeek             — ${YELLOW}Murah${NC}, DeepSeek V3/R1"
    echo -e "  ${BLUE}7.${NC} Ollama (local)       — ${YELLOW}Gratis${NC}, butuh RAM 8GB+"
    echo -e "  ${BLUE}8.${NC} Custom (manual edit) — Isi config.yaml sendiri"
    echo ""

    PROVIDER_CHOICE=""
    if is_piped; then
        PROVIDER_CHOICE="8"
        warn "Piped mode: defaulting to Custom (edit config.yaml manually)"
    else
        while true; do
            read -p "  Pilih [1-8]: " PROVIDER_CHOICE
            [[ "$PROVIDER_CHOICE" =~ ^[1-8]$ ]] && break
            echo -e "  ${RED}Masukkan angka 1-8${NC}"
        done
    fi

    case "$PROVIDER_CHOICE" in
        1)
            PROVIDER_NAME="xiaomi"
            PROVIDER_MODEL="xiaomi/mimo-v2.5-pro"
            PROVIDER_URL="https://token-plan-sgp.xiaomimimo.com/v1"
            PROVIDER_ENV_KEY="XIAOMI_API_KEY"
            log "Xiaomi MiMo selected"
            ;;
        2)
            PROVIDER_NAME="groq"
            PROVIDER_MODEL="groq/llama-3.3-70b-versatile"
            PROVIDER_URL="https://api.groq.com/openai/v1"
            PROVIDER_ENV_KEY="GROQ_API_KEY"
            log "Groq selected"
            ;;
        3)
            PROVIDER_NAME="openrouter"
            PROVIDER_MODEL="anthropic/claude-sonnet-4"
            PROVIDER_URL="https://openrouter.ai/api/v1"
            PROVIDER_ENV_KEY="OPENROUTER_API_KEY"
            log "OpenRouter selected"
            ;;
        4)
            PROVIDER_NAME="openai"
            PROVIDER_MODEL="gpt-4o"
            PROVIDER_URL="https://api.openai.com/v1"
            PROVIDER_ENV_KEY="OPENAI_API_KEY"
            log "OpenAI selected"
            ;;
        5)
            PROVIDER_NAME="anthropic"
            PROVIDER_MODEL="claude-sonnet-4"
            PROVIDER_URL="https://api.anthropic.com/v1"
            PROVIDER_ENV_KEY="ANTHROPIC_API_KEY"
            log "Anthropic selected"
            ;;
        6)
            PROVIDER_NAME="deepseek"
            PROVIDER_MODEL="deepseek-chat"
            PROVIDER_URL="https://api.deepseek.com/v1"
            PROVIDER_ENV_KEY="DEEPSEEK_API_KEY"
            log "DeepSeek selected"
            ;;
        7)
            PROVIDER_NAME="ollama"
            PROVIDER_MODEL="llama3.3:70b"
            PROVIDER_URL="http://localhost:11434/v1"
            PROVIDER_ENV_KEY=""
            log "Ollama (local) selected"
            if ! command -v ollama &> /dev/null; then
                warn "Ollama not installed. Installing..."
                curl -fsSL https://ollama.com/install.sh -o /tmp/ollama_install.sh
                bash /tmp/ollama_install.sh 2>/dev/null || warn "Ollama install failed — install manually: curl -fsSL https://ollama.com/install.sh | sh"
                rm -f /tmp/ollama_install.sh
            fi
            ;;
        8)
            if is_piped; then
                warn "Piped mode: edit config.yaml manually after install"
            else
                echo ""
                echo -e "  ${CYAN}Custom Provider Setup${NC}"
                echo -e "  Masukkan data provider kamu:"
                echo ""
                read -p "  Provider name (e.g. openrouter): " PROVIDER_NAME
                read -p "  Model name (e.g. anthropic/claude-sonnet-4): " PROVIDER_MODEL
                read -p "  Base URL (e.g. https://openrouter.ai/api/v1): " PROVIDER_URL
                read -p "  API key env var name (e.g. OPENROUTER_API_KEY): " PROVIDER_ENV_KEY
                log "Custom provider: $PROVIDER_NAME"
            fi
            ;;
    esac

    # Generate config.yaml
    cat > "$HERMES_HOME/config.yaml" << HEREDOC
model:
  default: ${PROVIDER_MODEL:-}
  provider: ${PROVIDER_NAME:-}
  base_url: ${PROVIDER_URL:-}
providers: {}
toolsets:
- hermes-cli
agent:
  max_turns: 150
  gateway_timeout: 1800
  system_prompt: ''
terminal:
  backend: local
  timeout: 180
  persistent_shell: true
HEREDOC
    log "Config created"
else
    log "Config already exists"
fi

# ============================================================
# STEP 6: Create .env
# ============================================================
if [ ! -f "$HERMES_HOME/.env" ]; then
    cat > "$HERMES_HOME/.env" << 'HEREDOC'
# Agent Icikiwir - Environment Variables
# Fill in ONLY the key for your chosen provider

# === Telegram Bot ===
TELEGRAM_BOT_TOKEN=TELEGRAM_ALLOWED_USERS=TELEGRAM_HOME_CHANNEL=

# === LLM Providers (fill ONE) ===
XIAOMI_API_KEY=*** Groq
GROQ_API_KEY=*** OpenRouter
OPENROUTER_API_KEY=*** OpenAI
OPENAI_API_KEY=*** Anthropic
ANTHROPIC_API_KEY=*** DeepSeek
DEEPSEEK_API_KEY=*** === Other ===
TERMINAL_ENV=local
HEREDOC
    chmod 600 "$HERMES_HOME/.env"
    log ".env template created"
else
    log ".env already exists"
fi

# ============================================================
# STEP 7: Download & Restore Skills
# ============================================================
header "📚 Installing Skills"

if [ ! -f "$HERMES_HOME/skills.tar.gz" ]; then
    info "Downloading skills from GitHub..."
    download "$HERMES_HOME/skills.tar.gz" "skills.tar.gz"
fi

if [ -f "$HERMES_HOME/skills.tar.gz" ]; then
    cd "$HERMES_HOME/skills"
    tar xzf "$HERMES_HOME/skills.tar.gz" --strip-components=0 2>/dev/null || warn "Failed to extract skills"
    rm -f "$HERMES_HOME/skills.tar.gz"
    SKILL_COUNT=$(find "$HERMES_HOME/skills" -name "SKILL.md" 2>/dev/null | wc -l)
    log "Skills restored: $SKILL_COUNT skills"
else
    warn "No skills found. Add later: hermes skills install <name>"
fi

# ============================================================
# STEP 8: Download & Restore Plugins
# ============================================================
header "🔌 Installing Plugins"

if [ ! -f "$HERMES_HOME/plugins.tar.gz" ]; then
    info "Downloading plugins from GitHub..."
    download "$HERMES_HOME/plugins.tar.gz" "plugins.tar.gz"
fi

if [ -f "$HERMES_HOME/plugins.tar.gz" ]; then
    cd "$HERMES_HOME/plugins"
    tar xzf "$HERMES_HOME/plugins.tar.gz" --strip-components=0 2>/dev/null || warn "Failed to extract plugins"
    rm -f "$HERMES_HOME/plugins.tar.gz"
    log "Plugins restored"
else
    warn "No plugins found."
fi

# ============================================================
# STEP 9: Restore Memories, Channel, SOUL
# ============================================================
header "🧠 Restoring Config Files"

# Download template files from GitHub
for f in MEMORY.md USER.md channel_directory.json SOUL.md; do
    if [ ! -f "$HERMES_HOME/$f" ] && [ ! -f "$HERMES_HOME/memories/$f" ]; then
        download "/tmp/$f" "$f" 2>/dev/null || true
    fi
done

# MEMORY.md
if [ -f "/tmp/MEMORY.md" ] && [ ! -f "$HERMES_HOME/memories/MEMORY.md" ]; then
    cp /tmp/MEMORY.md "$HERMES_HOME/memories/MEMORY.md"
    log "MEMORY.md restored"
elif [ -f "$HERMES_HOME/memories/MEMORY.md" ]; then
    log "MEMORY.md already exists"
fi

# USER.md
if [ -f "/tmp/USER.md" ] && [ ! -f "$HERMES_HOME/memories/USER.md" ]; then
    cp /tmp/USER.md "$HERMES_HOME/memories/USER.md"
    log "USER.md restored"
elif [ -f "$HERMES_HOME/memories/USER.md" ]; then
    log "USER.md already exists"
fi

# channel_directory.json
if [ -f "/tmp/channel_directory.json" ] && [ ! -f "$HERMES_HOME/channel_directory.json" ]; then
    cp /tmp/channel_directory.json "$HERMES_HOME/channel_directory.json"
    log "channel_directory.json restored"
elif [ -f "$HERMES_HOME/channel_directory.json" ]; then
    log "channel_directory.json already exists"
fi

# SOUL.md
if [ -f "/tmp/SOUL.md" ] && [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp /tmp/SOUL.md "$HERMES_HOME/SOUL.md"
    log "SOUL.md restored"
elif [ -f "$HERMES_HOME/SOUL.md" ]; then
    log "SOUL.md already exists"
else
    warn "No SOUL.md found. Agent will use default personality."
fi

# Cleanup tmp files
rm -f /tmp/MEMORY.md /tmp/USER.md /tmp/channel_directory.json /tmp/SOUL.md

# ============================================================
# STEP 10: Setup Gateway Service
# ============================================================
header "🌐 Setting up Gateway"

HERMES_BIN="$HERMES_AGENT/.venv/bin/hermes"

if [ -f "$HERMES_BIN" ]; then
    cat > /etc/systemd/system/hermes-gateway.service << HEREDOC
[Unit]
Description=Hermes Agent Gateway
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HERMES_AGENT
ExecStart=$HERMES_BIN gateway start
Restart=always
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=multi-user.target
HEREDOC
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable hermes-gateway 2>/dev/null || true
    log "Gateway service created"
else
    warn "Hermes binary not found. Gateway not configured."
fi

# ============================================================
# STEP 11: PATH & Aliases
# ============================================================
header "🔧 Final Setup"

if ! grep -q "hermes-agent/.venv/bin" ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/hermes-agent/.venv/bin:$PATH"' >> ~/.bashrc
    log "Added hermes to PATH"
fi

export PATH="$HERMES_AGENT/.venv/bin:$PATH"

if ! grep -q "alias hm=" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'HEREDOC'

# Agent Icikiwir aliases
alias hm='hermes'
alias hms='hermes gateway start'
alias hmr='hermes gateway restart'
alias hml='hermes logs --follow'
alias hmp='hermes plugins list'
alias hmsk='hermes skills list'
HEREDOC
    log "Aliases added (hm, hms, hmr, hml, hmp, hmsk)"
fi

# ============================================================
# STEP 12: Verification
# ============================================================
header "✅ Installation Complete!"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Agent Icikiwir installed successfully! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Location:${NC}     $HERMES_AGENT"
echo -e "  ${CYAN}Config:${NC}       $HERMES_HOME/config.yaml"
echo -e "  ${CYAN}Env:${NC}          $HERMES_HOME/.env"
echo -e "  ${CYAN}Provider:${NC}     ${PROVIDER_NAME:-not set}"
echo -e "  ${CYAN}Model:${NC}        ${PROVIDER_MODEL:-not set}"
echo -e "  ${CYAN}Skills:${NC}       $(find "$HERMES_HOME/skills" -name 'SKILL.md' 2>/dev/null | wc -l) installed"
echo -e "  ${CYAN}Memories:${NC}     $HERMES_HOME/memories/"
echo ""
echo -e "  ${YELLOW}⚠️  NEXT STEPS:${NC}"
echo ""

if [ -n "${PROVIDER_ENV_KEY:-}" ]; then
    echo -e "  ${BLUE}1.${NC} Add your ${GREEN}${PROVIDER_ENV_KEY}${NC} in:"
    echo -e "     ${CYAN}nano $HERMES_HOME/.env${NC}"
else
    echo -e "  ${BLUE}1.${NC} Edit your config & API keys:"
    echo -e "     ${CYAN}nano $HERMES_HOME/.env${NC}"
    echo -e "     ${CYAN}nano $HERMES_HOME/config.yaml${NC}"
fi

echo ""
echo -e "  ${BLUE}2.${NC} Start the gateway:"
echo -e "     ${CYAN}sudo systemctl start hermes-gateway${NC}"
echo ""
echo -e "  ${BLUE}3.${NC} Check status:"
echo -e "     ${CYAN}sudo systemctl status hermes-gateway${NC}"
echo ""
echo -e "  ${BLUE}4.${NC} View logs:"
echo -e "     ${CYAN}hermes logs --follow${NC}"
echo ""
echo -e "  ${BLUE}5.${NC} Quick commands:"
echo -e "     ${CYAN}hm${NC}           - hermes CLI"
echo -e "     ${CYAN}hms${NC}          - start gateway"
echo -e "     ${CYAN}hmr${NC}          - restart gateway"
echo -e "     ${CYAN}hml${NC}          - follow logs"
echo -e "     ${CYAN}hmp${NC}          - list plugins"
echo -e "     ${CYAN}hmsk${NC}         - list skills"
echo ""
echo -e "  ${GREEN}Docs: https://hermes-agent.nousresearch.com/docs${NC}"
echo ""

# Final warning if API key not set
if [ -n "${PROVIDER_ENV_KEY:-}" ]; then
    if grep -q "^${PROVIDER_ENV_KEY}=$" "$HERMES_HOME/.env" 2>/dev/null; then
        warn "⚠️  Don't forget to add your ${PROVIDER_ENV_KEY} in $HERMES_HOME/.env"
    fi
fi

echo ""
