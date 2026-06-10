#!/usr/bin/env bash
#
# install.sh -- one-time setup on the droplet.
# Installs dependencies, lays down config, and registers the systemd user unit.
# Safe to re-run.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_UNIT_DIR="$HOME/.config/systemd/user"

say() { printf '\n>> %s\n' "$*"; }

# --- dependencies ------------------------------------------------------------
say "Checking dependencies"

if ! command -v node >/dev/null 2>&1; then
  echo "node not found. Install Node.js 18+ first (e.g. via nvm or your package manager), then re-run." >&2
  exit 1
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "Node.js 18+ required, found $(node -v)." >&2
  exit 1
fi
echo "node $(node -v) ok"

if ! command -v tmux >/dev/null 2>&1; then
  say "Installing tmux"
  sudo apt-get update -y && sudo apt-get install -y tmux
fi

if ! command -v git >/dev/null 2>&1; then
  say "Installing git"
  sudo apt-get update -y && sudo apt-get install -y git
fi

if ! command -v claude >/dev/null 2>&1; then
  say "Installing Claude Code"
  sudo npm install -g @anthropic-ai/claude-code
fi
echo "claude $(claude --version 2>/dev/null || echo '(version check failed)')"

# --- config ------------------------------------------------------------------
say "Setting up config"
if [ ! -f "$REPO_ROOT/config/claude-rc.env" ]; then
  cp "$REPO_ROOT/config/claude-rc.env.example" "$REPO_ROOT/config/claude-rc.env"
  echo "created config/claude-rc.env (edit it to taste)"
else
  echo "config/claude-rc.env already exists, leaving it alone"
fi

# Read PROJECTS_DIR the same way the wrapper does.
# shellcheck disable=SC1090
set -a; . "$REPO_ROOT/config/claude-rc.env"; set +a
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
mkdir -p "$PROJECTS_DIR"
echo "projects dir: $PROJECTS_DIR"

chmod +x "$REPO_ROOT"/bin/*.sh "$REPO_ROOT"/scripts/*.sh

# --- systemd user unit -------------------------------------------------------
say "Installing systemd user unit"
mkdir -p "$USER_UNIT_DIR"
sed "s|__CLAUDE_RC_ROOT__|$REPO_ROOT|g" \
  "$REPO_ROOT/systemd/claude-rc@.service" > "$USER_UNIT_DIR/claude-rc@.service"
systemctl --user daemon-reload
echo "installed $USER_UNIT_DIR/claude-rc@.service"

# Linger lets user services start at boot and keep running after logout.
if ! loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
  say "Enabling linger (may prompt for sudo)"
  sudo loginctl enable-linger "$USER" || \
    echo "Could not enable linger automatically. Run: sudo loginctl enable-linger $USER"
fi

cat <<EOF

Done. Next steps:
  1. Authenticate:   scripts/auth.sh
  2. Wire up MCP:    scripts/setup-mcp.sh
  3. Add a repo:     scripts/add-repo.sh <git-url> [name]

EOF
