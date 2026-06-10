#!/usr/bin/env bash
#
# setup-mcp.sh -- register the Chaos Dimension MCP server at USER scope so it is
# available in every session across every repo and worktree, configured once.
#
# If CHAOS_DIMENSION_TOKEN is set in config/claude-rc.env, the token is stored as
# a runtime-expanded ${CHAOS_DIMENSION_TOKEN} reference (single-quoted), so the
# real secret never lands in ~/.claude.json. The token must then be present in
# the service environment at runtime, which the EnvironmentFile already handles.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="chaos-dimension"
URL="https://www.chaosdimension.fyi/api/mcp"

# shellcheck disable=SC1090
set -a; . "$REPO_ROOT/config/claude-rc.env"; set +a

# Remove any stale entry so this is idempotent.
claude mcp remove --scope user "$NAME" >/dev/null 2>&1 || true

if [ -n "${CHAOS_DIMENSION_TOKEN:-}" ]; then
  echo ">> Adding $NAME (user scope, with auth header)"
  # Single quotes keep ${CHAOS_DIMENSION_TOKEN} literal so claude expands it at load time.
  claude mcp add --scope user --transport http \
    --header 'Authorization: Bearer ${CHAOS_DIMENSION_TOKEN}' \
    "$NAME" "$URL"
else
  echo ">> Adding $NAME (user scope, no auth)"
  claude mcp add --scope user --transport http "$NAME" "$URL"
fi

echo ">> Verifying"
if claude mcp list 2>/dev/null | grep -qi "$NAME"; then
  echo "ok: $NAME is registered"
else
  cat <<EOF
WARNING: claude mcp list did not show $NAME.

There is a known issue where 'claude mcp add --scope user' writes to
~/.claude.json but the CLI does not read it back. If a session does not see the
tools, add the block below to ~/.claude.json under the top-level "mcpServers" key:

  "chaos-dimension": {
    "type": "http",
    "url": "$URL"$( [ -n "${CHAOS_DIMENSION_TOKEN:-}" ] && printf ',\n    "headers": { "Authorization": "Bearer \${CHAOS_DIMENSION_TOKEN}" }' )
  }

Then restart the servers:  systemctl --user restart 'claude-rc@*'
EOF
fi
