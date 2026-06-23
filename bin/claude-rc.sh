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
#
# The restart delay uses jitter + exponential backoff. When a network blip drops
# several per-repo servers at once, a fixed 5s delay makes them all re-register
# on the same beat. That synchronized stampede trips the Remote Control relay's
# per-account concurrency guard, which answers with
#   Registration/Poll: Access denied (403). Check your organization permissions.
# and the denied servers retry on the same beat, sustaining the burst. Jitter
# de-synchronizes them; backoff stops hammering during a sustained outage.
delay=5
while true; do
  claude remote-control \
    --spawn "$SPAWN" \
    --capacity "$CAPACITY" \
    --remote-control-session-name-prefix "$REPO"
  code=$?

  # Clean exit resets the backoff; an error backs off up to 60s.
  if [ "$code" -eq 0 ]; then
    delay=5
  else
    delay=$(( delay * 2 ))
    [ "$delay" -gt 60 ] && delay=60
  fi

  # Add 0..delay seconds of jitter so concurrent supervisors spread out.
  jitter=$(( RANDOM % (delay + 1) ))
  wait=$(( delay + jitter ))
  echo "[claude-rc] '$REPO' server exited (code $code); restarting in ${wait}s" >&2
  sleep "$wait"
done
