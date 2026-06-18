#!/bin/bash
# ============================================================
#  Hermes Agent One-Liner Installer
#  Ramah pemula, auto-setup di VPS baru
#
#  Usage:
#    curl -sL https://raw.githubusercontent.com/keinankairi-afk/hermes-installer/main/install.sh | bash
#
#  Atau:
#    wget -qO- https://raw.githubusercontent.com/keinankairi-afk/hermes-installer/main/install.sh | bash
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# ============================================================
# STEP 0: Pre-flight checks
# ============================================================
header "🚀 Hermes Agent Installer v1.0"

if [ "$EUID" -eq 0 ]; then
    warn "Running as root. This is OK for VPS setup."
fi

ARCH=$(uname -m)
OS=$(uname -s)
info "System: $OS $ARCH"

if [ "$OS" != "Linux" ]; then
    error "This installer only supports Linux (Ubuntu/Debian)"
fi

# ============================================================
# STEP 1: System dependencies
# ============================================================
header "📦 Installing System Dependencies"

apt-get update -qq
apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget \
    unzip \
    sqlite3 \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    > /dev/null 2>&1

log "System packages installed"

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+')
info "Python: $PYTHON_VERSION"

# ============================================================
# STEP 2: Install Node.js (for Hermes plugins)
# ============================================================
header "📦 Installing Node.js"

if command -v node &> /dev/null; then
    log "Node.js already installed: $(node --version)"
else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
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
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Skipping clone, using existing installation"
    else
        rm -rf "$HERMES_AGENT"
        git clone --depth 1 https://github.com/NousResearch/hermes-agent.git "$HERMES_AGENT"
        log "Hermes Agent cloned"
    fi
else
    git clone --depth 1 https://github.com/NousResearch/hermes-agent.git "$HERMES_AGENT"
    log "Hermes Agent cloned"
fi

# ============================================================
# STEP 4: Setup Python venv
# ============================================================
header "🐍 Setting up Python Environment"

cd "$HERMES_AGENT"

if [ -d ".venv" ]; then
    log "Virtual environment already exists"
else
    python3 -m venv .venv
    log "Virtual environment created"
fi

source .venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q 2>/dev/null || pip install -e . -q 2>/dev/null || true
log "Python dependencies installed"

# ============================================================
# STEP 5: Setup Hermes Home
# ============================================================
header "📁 Setting up Hermes Home"

mkdir -p "$HERMES_HOME"/{skills,plugins,memories,logs,cron,cache}

# Create config if not exists
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cat > "$HERMES_HOME/config.yaml" << 'CONFIG'
model:
  default: xiaomi/mimo-v2.5-pro
  provider: xiaomi
  base_url: https://token-plan-sgp.xiaomimimo.com/v1
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
CONFIG
    log "Config created (default)"
else
    log "Config already exists"
fi

# Create .env if not exists
if [ ! -f "$HERMES_HOME/.env" ]; then
    cat > "$HERMES_HOME/.env" << 'ENV'
# Fill in your values below
TELEGRAM_BOT_TOKEN=
XIAOMI_API_KEY=
XIAOMI_BASE_URL=https://token-plan-sgp.xiaomimimo.com/v1
TERMINAL_ENV=local
ENV
    chmod 600 "$HERMES_HOME/.env"
    log ".env template created"
else
    log ".env already exists"
fi

# ============================================================
# STEP 6: Download & Restore Skills
# ============================================================
header "📚 Installing Skills"

SKILLS_URL="https://github.com/keinankairi-afk/hermes-installer/raw/main/skills.tar.gz"

if [ -f "$HERMES_HOME/skills.tar.gz" ] || [ -f "/home/ubuntu/hermes-export/skills.tar.gz" ]; then
    # Local restore
    if [ -f "/home/ubuntu/hermes-export/skills.tar.gz" ]; then
        cp /home/ubuntu/hermes-export/skills.tar.gz "$HERMES_HOME/skills.tar.gz"
    fi
    cd "$HERMES_HOME/skills"
    tar xzf "$HERMES_HOME/skills.tar.gz" --strip-components=0
    rm -f "$HERMES_HOME/skills.tar.gz"
    SKILL_COUNT=$(find "$HERMES_HOME/skills" -name "SKILL.md" | wc -l)
    log "Skills restored: $SKILL_COUNT skills"
else
    warn "No skills archive found. Skills will be empty."
    warn "To add skills later: hermes skills install <name>"
fi

# ============================================================
# STEP 7: Download & Restore Plugins
# ============================================================
header "🔌 Installing Plugins"

PLUGINS_URL="https://github.com/keinankairi-afk/hermes-installer/raw/main/plugins.tar.gz"

if [ -f "$HERMES_HOME/plugins.tar.gz" ] || [ -f "/home/ubuntu/hermes-export/plugins.tar.gz" ]; then
    if [ -f "/home/ubuntu/hermes-export/plugins.tar.gz" ]; then
        cp /home/ubuntu/hermes-export/plugins.tar.gz "$HERMES_HOME/plugins.tar.gz"
    fi
    cd "$HERMES_HOME/plugins"
    tar xzf "$HERMES_HOME/plugins.tar.gz" --strip-components=0
    rm -f "$HERMES_HOME/plugins.tar.gz"
    log "Plugins restored"
else
    warn "No plugins archive found."
fi

# ============================================================
# STEP 8: Restore Memories
# ============================================================
header "🧠 Restoring Memories"

if [ -f "/home/ubuntu/hermes-export/MEMORY.md" ]; then
    cp /home/ubuntu/hermes-export/MEMORY.md "$HERMES_HOME/memories/MEMORY.md"
    cp /home/ubuntu/hermes-export/USER.md "$HERMES_HOME/memories/USER.md"
    log "Memories restored"
elif [ -f "$HERMES_HOME/memories/MEMORY.md" ]; then
    log "Memories already exist"
else
    warn "No memories found. Starting fresh."
fi

# ============================================================
# STEP 9: Restore Channel Directory
# ============================================================
header "📱 Restoring Channel Directory"

if [ -f "/home/ubuntu/hermes-export/channel_directory.json" ]; then
    cp /home/ubuntu/hermes-export/channel_directory.json "$HERMES_HOME/channel_directory.json"
    log "Channel directory restored"
fi

# ============================================================
# STEP 10: Setup Gateway Service
# ============================================================
header "🌐 Setting up Gateway"

HERMES_BIN="$HERMES_AGENT/.venv/bin/hermes"

if [ -f "$HERMES_BIN" ]; then
    # Create systemd service
    cat > /etc/systemd/system/hermes-gateway.service << SVC
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
SVC

    systemctl daemon-reload
    systemctl enable hermes-gateway
    log "Gateway service created"
else
    warn "Hermes binary not found. Gateway not configured."
fi

# ============================================================
# STEP 11: Add hermes to PATH
# ============================================================
header "🔧 Final Setup"

# Add to PATH
if ! grep -q "hermes-agent/.venv/bin" ~/.bashrc; then
    echo 'export PATH="$HOME/hermes-agent/.venv/bin:$PATH"' >> ~/.bashrc
    log "Added hermes to PATH"
fi

export PATH="$HERMES_AGENT/.venv/bin:$PATH"

# Create quick aliases
if ! grep -q "alias hm=" ~/.bashrc; then
    cat >> ~/.bashrc << 'ALIASES'

# Hermes aliases
alias hm='hermes'
alias hms='hermes gateway start'
alias hmr='hermes gateway restart'
alias hml='hermes logs --follow'
alias hmp='hermes plugins list'
alias hmsk='hermes skills list'
ALIASES
    log "Aliases added (hm, hms, hmr, hml, hmp, hmsk)"
fi

# ============================================================
# STEP 12: Verification
# ============================================================
header "✅ Installation Complete!"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Hermes Agent installed successfully! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Location:${NC}     $HERMES_AGENT"
echo -e "  ${CYAN}Config:${NC}       $HERMES_HOME/config.yaml"
echo -e "  ${CYAN}Env:${NC}          $HERMES_HOME/.env"
echo -e "  ${CYAN}Skills:${NC}       $(find $HERMES_HOME/skills -name 'SKILL.md' 2>/dev/null | wc -l) installed"
echo -e "  ${CYAN}Memories:${NC}     $HERMES_HOME/memories/"
echo ""
echo -e "  ${YELLOW}⚠️  NEXT STEPS:${NC}"
echo ""
echo -e "  ${BLUE}1.${NC} Edit your API keys:"
echo -e "     ${CYAN}nano $HERMES_HOME/.env${NC}"
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

# Check if .env needs editing
if grep -q "^XIAOMI_API_KEY=$" "$HERMES_HOME/.env" 2>/dev/null; then
    warn "⚠️  Don't forget to add your API keys in $HERMES_HOME/.env"
fi

echo ""
