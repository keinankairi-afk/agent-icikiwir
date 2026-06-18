#!/bin/bash
# ============================================================
#  Agent Icikiwir - Hermes Agent One-Liner Installer
#  Ramah pemula, auto-setup di VPS baru
#
#  Usage:
#    curl -sL https://raw.githubusercontent.com/keinankairi-afk/agent-icikiwir/main/install.sh | bash
#
#  Atau:
#    wget -qO- https://raw.githubusercontent.com/keinankairi-afk/agent-icikiwir/main/install.sh | bash
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Config - change these if you fork the repo
REPO_OWNER="keinankairi-afk"
REPO_NAME="agent-icikiwir"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

# Functions
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# Detect if running piped (curl | bash) or from local file
is_piped() { [ ! -t 0 ]; }

# ============================================================
# STEP 0: Pre-flight checks
# ============================================================
header "🚀 Agent Icikiwir Installer v1.1"

if [ "$(uname -s)" != "Linux" ]; then
    error "This installer only supports Linux (Ubuntu/Debian)"
fi

ARCH=$(uname -m)
OS=$(uname -s)
info "System: $OS $ARCH"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash install.sh"
fi

# ============================================================
# STEP 1: System dependencies
# ============================================================
header "📦 Installing System Dependencies"

apt-get update -qq || error "apt-get update failed"
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
    > /dev/null 2>&1 || error "Failed to install system packages"

log "System packages installed"

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' || echo "unknown")
info "Python: $PYTHON_VERSION"

# ============================================================
# STEP 2: Install Node.js (for Hermes plugins)
# ============================================================
header "📦 Installing Node.js"

if command -v node &> /dev/null; then
    log "Node.js already installed: $(node --version)"
else
    # Use NodeSource setup script (safer than raw curl | bash)
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
        # In piped mode, auto-overwrite (user can Ctrl+C to abort)
        warn "Piped mode detected. Overwriting in 3 seconds... (Ctrl+C to abort)"
        sleep 3
        rm -rf "$HERMES_AGENT"
    else
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Skipping clone, using existing installation"
        else
            rm -rf "$HERMES_AGENT"
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

if [ -d ".venv" ]; then
    log "Virtual environment already exists"
else
    python3 -m venv .venv || error "Failed to create venv"
    log "Virtual environment created"
fi

source .venv/bin/activate
pip install --upgrade pip -q 2>/dev/null || true
pip install -r requirements.txt -q 2>/dev/null || pip install -e . -q 2>/dev/null || warn "Some Python deps may be missing"
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

SKILLS_URL="${RAW_URL}/skills.tar.gz"

# Try to download from GitHub if not found locally
if [ ! -f "$HERMES_HOME/skills.tar.gz" ] && [ ! -f "/tmp/agent-icikiwir/skills.tar.gz" ]; then
    info "Downloading skills from GitHub..."
    curl -sL "$SKILLS_URL" -o "$HERMES_HOME/skills.tar.gz" 2>/dev/null || warn "Failed to download skills"
fi

# Copy from local if available
if [ -f "/tmp/agent-icikiwir/skills.tar.gz" ]; then
    cp /tmp/agent-icikiwir/skills.tar.gz "$HERMES_HOME/skills.tar.gz"
fi

if [ -f "$HERMES_HOME/skills.tar.gz" ]; then
    cd "$HERMES_HOME/skills"
    tar xzf "$HERMES_HOME/skills.tar.gz" --strip-components=0 2>/dev/null || warn "Failed to extract skills"
    rm -f "$HERMES_HOME/skills.tar.gz"
    SKILL_COUNT=$(find "$HERMES_HOME/skills" -name "SKILL.md" 2>/dev/null | wc -l)
    log "Skills restored: $SKILL_COUNT skills"
else
    warn "No skills archive found. Skills will be empty."
    warn "To add skills later: hermes skills install <name>"
fi

# ============================================================
# STEP 7: Download & Restore Plugins
# ============================================================
header "🔌 Installing Plugins"

PLUGINS_URL="${RAW_URL}/plugins.tar.gz"

# Try to download from GitHub if not found locally
if [ ! -f "$HERMES_HOME/plugins.tar.gz" ] && [ ! -f "/tmp/agent-icikiwir/plugins.tar.gz" ]; then
    info "Downloading plugins from GitHub..."
    curl -sL "$PLUGINS_URL" -o "$HERMES_HOME/plugins.tar.gz" 2>/dev/null || warn "Failed to download plugins"
fi

# Copy from local if available
if [ -f "/tmp/agent-icikiwir/plugins.tar.gz" ]; then
    cp /tmp/agent-icikiwir/plugins.tar.gz "$HERMES_HOME/plugins.tar.gz"
fi

if [ -f "$HERMES_HOME/plugins.tar.gz" ]; then
    cd "$HERMES_HOME/plugins"
    tar xzf "$HERMES_HOME/plugins.tar.gz" --strip-components=0 2>/dev/null || warn "Failed to extract plugins"
    rm -f "$HERMES_HOME/plugins.tar.gz"
    log "Plugins restored"
else
    warn "No plugins archive found."
fi

# ============================================================
# STEP 8: Restore Memories
# ============================================================
header "🧠 Restoring Memories"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/MEMORY.md" ]; then
    cp "$SCRIPT_DIR/MEMORY.md" "$HERMES_HOME/memories/MEMORY.md"
    cp "$SCRIPT_DIR/USER.md" "$HERMES_HOME/memories/USER.md" 2>/dev/null || true
    log "Memories restored from local"
elif [ -f "$HERMES_HOME/memories/MEMORY.md" ]; then
    log "Memories already exist"
else
    warn "No memories found. Starting fresh."
fi

# ============================================================
# STEP 9: Restore Channel Directory
# ============================================================
header "📱 Restoring Channel Directory"

if [ -f "$SCRIPT_DIR/channel_directory.json" ]; then
    cp "$SCRIPT_DIR/channel_directory.json" "$HERMES_HOME/channel_directory.json"
    log "Channel directory restored"
elif [ -f "$HERMES_HOME/channel_directory.json" ]; then
    log "Channel directory already exists"
else
    warn "No channel directory found."
fi

# ============================================================
# STEP 9.5: Restore SOUL.md
# ============================================================
header "💀 Restoring SOUL.md"

if [ -f "$SCRIPT_DIR/SOUL.md" ]; then
    cp "$SCRIPT_DIR/SOUL.md" "$HERMES_HOME/SOUL.md"
    log "SOUL.md restored"
elif [ -f "$HERMES_HOME/SOUL.md" ]; then
    log "SOUL.md already exists"
else
    warn "No SOUL.md found. Agent will use default personality."
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

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable hermes-gateway 2>/dev/null || true
    log "Gateway service created"
else
    warn "Hermes binary not found. Gateway not configured."
fi

# ============================================================
# STEP 11: Add hermes to PATH
# ============================================================
header "🔧 Final Setup"

# Add to PATH
if ! grep -q "hermes-agent/.venv/bin" ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/hermes-agent/.venv/bin:$PATH"' >> ~/.bashrc
    log "Added hermes to PATH"
fi

export PATH="$HERMES_AGENT/.venv/bin:$PATH"

# Create quick aliases
if ! grep -q "alias hm=" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'ALIASES'

# Agent Icikiwir aliases
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
echo -e "${GREEN}  Agent Icikiwir installed successfully! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Location:${NC}     $HERMES_AGENT"
echo -e "  ${CYAN}Config:${NC}       $HERMES_HOME/config.yaml"
echo -e "  ${CYAN}Env:${NC}          $HERMES_HOME/.env"
echo -e "  ${CYAN}Skills:${NC}       $(find "$HERMES_HOME/skills" -name 'SKILL.md' 2>/dev/null | wc -l) installed"
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
