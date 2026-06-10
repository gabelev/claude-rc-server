#!/usr/bin/env bash
#
# auth.sh -- guided login for a headless box.
#
# Remote Control needs a FULL-SCOPE claude.ai login token. An API key will not
# work, and neither will a 'claude setup-token' / CLAUDE_CODE_OAUTH_TOKEN, which
# are inference-only. This helper walks you through the browser flow.
#
set -uo pipefail

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ANTHROPIC_API_KEY is set in this shell. Unsetting it for login."
  echo "Make sure it is not exported in ~/.bashrc, or Remote Control will refuse to start."
  unset ANTHROPIC_API_KEY
fi

cat <<'EOF'

About to run: claude auth login  (choose the claude.ai option)

Claude will print a URL. One of two things happens:

  A) It gives you a code to paste back.
     -> Just open the URL on your laptop, approve, paste the code here. Done.

  B) It starts a local callback server on some port (e.g. localhost:PORT).
     -> In a SECOND terminal on your laptop, forward that exact port:
            ssh -L PORT:localhost:PORT <user>@<droplet>
     -> Then open the printed URL in your laptop browser. The callback
        tunnels back to the droplet and login completes.

EOF

read -r -p "Press Enter to start login (Ctrl-C to cancel)... " _

claude auth login || {
  echo "Login command exited non-zero. If it actually succeeded, ignore this." >&2
}

echo
echo "Verify inside a session with /status, or check that no API key is set."
echo "You want the login method to read as a claude.ai session (not API key, not inference-only)."
