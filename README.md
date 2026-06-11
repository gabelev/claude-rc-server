# claude-rc-server

Persistent, multi-repo Claude Code Remote Control on a headless server (DigitalOcean or any Ubuntu/Debian VPS). Clone it, run three scripts, and drive long-lived Claude Code sessions from claude.ai/code or the mobile app, one server per repo, surviving reboots.

## The model

A Remote Control server runs in **server mode** and is anchored to one working directory. A single server process can serve many concurrent sessions (default capacity 32 upstream, set lower here), and you create those sessions on demand from the web or phone. Because a server is tied to one directory, you run **one server per repo**. This repo wires each one up as a systemd user service via a template unit, so adding a repo is a single command.

Each session runs on the box against your local filesystem, MCP servers, and config. The web and mobile interfaces are just a window into it. Traffic is outbound HTTPS only; no inbound ports are opened.

## Pairing with Chaos Dimension

[Chaos Dimension](https://github.com/gabelev/chaos_dimension) ([live](https://chaosdimension.fyi)) is the other half of this setup: a themeable mission-control board for personal projects and AI agent orchestration. This repo is the *runtime* that hosts the agents; Chaos Dimension is the *board* that coordinates what they work on and shows what they did.

The two link through MCP. `setup-mcp.sh` registers the Chaos Dimension MCP endpoint at user scope (see [MCP across every repo](#mcp-across-every-repo)), so every session this server spawns, across every repo, can:

- **read** its work from the board (`list_tasks`, `claim_task`), and
- **report progress back** (`report_progress`, `update_task`).

So the Kanban columns and Agent Monitor on the board reflect what your droplet's agents are doing in near real time. Dispatch a task from the web or your phone, an agent here claims it, and you watch the logs stream back into Chaos Dimension while your laptop is closed.

You don't strictly need Chaos Dimension to use this repo (MCP registration is optional), but the two were built to run together. Chaos Dimension's README carries the mirror of this section under "Coordinate agents on a droplet or remote server."

## Requirements

- A Claude **Pro, Max, Team, or Enterprise** plan. Remote Control does not work with an API key. On Team/Enterprise an admin must enable the Remote Control toggle.
- A **full-scope claude.ai login token**. A `claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN` is inference-only and will be rejected.
- Node.js 18+, git, tmux. `install.sh` installs git and tmux if missing.
- Claude Code v2.1.51+ (server-mode flags assume a recent build).

## Quickstart

```bash
git clone <this-repo-url> ~/claude-rc-server
cd ~/claude-rc-server

./scripts/install.sh                 # deps, config, systemd user unit, linger
nano config/claude-rc.env            # set CAPACITY, SPAWN, optional token
./scripts/auth.sh                    # one-time full-scope login (see Auth below)
./scripts/setup-mcp.sh               # register Chaos Dimension MCP at user scope
./scripts/add-repo.sh git@github.com:you/putu.git putu
./scripts/add-repo.sh git@github.com:you/secondseat.git secondseat
```

Then open https://claude.ai/code. Sessions show up prefixed by repo name (`putu-...`, `secondseat-...`). Start a new session against any server from there or the app.

## Managing sessions

```bash
# add another repo (clone + enable + start)
./scripts/add-repo.sh <git-url> [name]

# stop / start / restart a repo's server
systemctl --user stop claude-rc@putu
systemctl --user start claude-rc@putu
systemctl --user restart 'claude-rc@*'        # all of them

# enable on boot vs run only when needed (saves RAM)
systemctl --user enable --now claude-rc@putu  # auto-start on boot
systemctl --user disable claude-rc@putu       # leave it off until you start it

# inspect the live process
systemctl --user status claude-rc@putu
tmux -L claude-rc attach -t claude-putu        # Ctrl-b d to detach
```

`--spawn worktree` (the default in `config/claude-rc.env`) gives each session its own git worktree, so parallel sessions on one repo do not stomp on each other's edits. Switch to `same-dir` if you want them sharing the tree, or `session` for single-session servers.

## MCP across every repo

The Chaos Dimension server is registered at **user scope**, stored in `~/.claude.json`, which applies across all projects and worktrees. Every server runs as the same user, so they all inherit it. Configure once, available everywhere. `setup-mcp.sh` handles this.

If you set `CHAOS_DIMENSION_TOKEN` in `config/claude-rc.env`, the token is stored as a runtime-expanded reference, not in plaintext, and is injected into the service environment via the unit's EnvironmentFile. systemd does not read `~/.bashrc`, so the token must live in the env file, not your shell profile.

Known gotcha: there is an open bug where `claude mcp add --scope user` writes the entry but `claude mcp list` does not read it back. `setup-mcp.sh` checks for this and prints the exact `~/.claude.json` block to paste if it happens.

## Auth, the part that bites people

On a headless box the OAuth flow has no local browser. `auth.sh` runs `claude auth login` and explains the two outcomes: either you paste a code back (easy), or it opens a localhost callback that you forward over SSH:

```bash
# in a second terminal on your laptop, forward the exact port it printed
ssh -L PORT:localhost:PORT <user>@<droplet>
# then open the printed URL in your laptop browser
```

Make sure `ANTHROPIC_API_KEY` is not exported anywhere, or Remote Control refuses to start.

## Resources

Each server plus its sessions plus any subagents consume RAM, and you are running several servers at once. Keep `CAPACITY` modest (default 6 here), watch `free -h`, and add swap on a small droplet:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Optional but nice: put Tailscale on the droplet so the one-time auth and any debugging happen over a private encrypted address instead of the public IP.

## Caveats

- The local process must keep running. The wrapper loop and systemd handle crashes and reboots, but if the box is offline for more than ~10 minutes the session times out and the loop starts a fresh one.
- Each reboot creates new Remote Control sessions. Old ones can linger as "connected" in the session list until they time out, so expect a few ghosts after several reboots.
- This is Ubuntu/Debian oriented (apt). Adjust `install.sh` for other distros.

## Layout

```
claude-rc-server/
├── README.md
├── bin/
│   └── claude-rc.sh           # per-repo server with restart loop
├── systemd/
│   └── claude-rc@.service     # template unit (%i = repo name)
├── config/
│   ├── claude-rc.env.example  # committed template
│   └── claude-rc.env          # your real config (gitignored)
└── scripts/
    ├── install.sh             # deps + systemd + linger
    ├── auth.sh                # guided headless login
    ├── setup-mcp.sh           # Chaos Dimension at user scope
    └── add-repo.sh            # clone + enable a repo server
```
