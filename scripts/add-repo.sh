#!/usr/bin/env bash
#
# add-repo.sh -- clone a repo onto the box and start a Remote Control server
# for it. One server per repo; the session list at claude.ai/code distinguishes
# them by the repo-name prefix.
#
# Usage:
#   add-repo.sh <git-url> [name]
#
#   <git-url>  the repo to clone (ssh or https)
#   [name]     optional directory + service-instance name; defaults to the repo
#              basename. Keep it short and free of spaces.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT_URL="${1:?usage: add-repo.sh <git-url> [name]}"
NAME="${2:-}"

# shellcheck disable=SC1090
set -a; . "$REPO_ROOT/config/claude-rc.env"; set +a
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"

if [ -z "$NAME" ]; then
  NAME="$(basename "$GIT_URL" .git)"
fi

DEST="$PROJECTS_DIR/$NAME"

if [ -d "$DEST/.git" ]; then
  echo ">> $DEST already cloned, skipping clone"
else
  echo ">> Cloning $GIT_URL into $DEST"
  git clone "$GIT_URL" "$DEST"
fi

echo ">> Enabling service: claude-rc@$NAME"
systemctl --user enable --now "claude-rc@$NAME.service"

cat <<EOF

Started. The server is registering with the Anthropic API now.
  Find it at https://claude.ai/code (sessions prefixed "$NAME-...")
  Watch it locally:  tmux -L claude-rc attach -t claude-$NAME   (Ctrl-b d to detach)
  Service status:    systemctl --user status claude-rc@$NAME

EOF
