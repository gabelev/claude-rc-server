#!/usr/bin/env bash
#
# claude-rc.sh -- run one Claude Code Remote Control server (server mode) for a
# single repo, restarting it automatically if it exits.
#
# Run one instance of this script per repo. A server-mode process is anchored to
# one working directory, so each repo needs its own server. The systemd template
# unit (claude-rc@.service) launches one of these per repo.
#
# Usage:
#   claude-rc.sh <repo-name>
#
#   <repo-name> is a directory under PROJECTS_DIR that is a git repository.
#
set -u

REPO="${1:?usage: claude-rc.sh <repo-name>}"

# Find the repo root (parent of bin/) so we can locate the config file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CLAUDE_RC_ENV:-$SCRIPT_DIR/config/claude-rc.env}"

# Load config. "set -a" exports everything so child processes (claude) inherit
# it, which is how CHAOS_DIMENSION_TOKEN reaches the MCP header expansion.
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
CAPACITY="${CAPACITY:-6}"
SPAWN="${SPAWN:-worktree}"
REPO_DIR="$PROJECTS_DIR/$REPO"

# Remote Control refuses to start when an API key is present; it needs a
# full-scope claude.ai login token instead. Strip the key from the environment.
unset ANTHROPIC_API_KEY

if [ ! -d "$REPO_DIR" ]; then
  echo "[claude-rc] repo directory not found: $REPO_DIR" >&2
  echo "[claude-rc] clone it first:  scripts/add-repo.sh <git-url> $REPO" >&2
  exit 1
fi

if [ "$SPAWN" = "worktree" ] && [ ! -d "$REPO_DIR/.git" ]; then
  echo "[claude-rc] $REPO_DIR is not a git repository, but SPAWN=worktree needs one" >&2
  echo "[claude-rc] either clone a real repo or set SPAWN=same-dir in config/claude-rc.env" >&2
  exit 1
fi

cd "$REPO_DIR" || exit 1

echo "[claude-rc] starting server for '$REPO' in $REPO_DIR (spawn=$SPAWN, capacity=$CAPACITY)"

# The loop restarts claude if it crashes or times out after a long network
# outage. systemd handles reboot survival; this handles in-session recovery.
while true; do
  claude remote-control \
    --spawn "$SPAWN" \
    --capacity "$CAPACITY" \
    --remote-control-session-name-prefix "$REPO"
  code=$?
  echo "[claude-rc] '$REPO' server exited (code $code); restarting in 5s" >&2
  sleep 5
done
