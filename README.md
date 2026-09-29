# claude-docker

Run [Claude Code](https://claude.ai) and [OpenAI Codex](https://developers.openai.com/codex) inside a Docker container with access to your host toolchain and working directory.

## Overview

- Isolates Claude Code and Codex from your host system (`--security-opt no-new-privileges`)
- Mounts host `/usr` ro so Claude can use your compilers, tools, and libraries
- Shares Claude config across host and container
- Optional extras: Node.js/ccstatusline, ccache (via `extra-build.sh` and `config`)

## What gets mounted

Always mounted by the script:

| Host path | Container path | Mode | Why |
|---|---|---|---|
| `$WORK_ROOT` | `$WORK_ROOT` | rw | Project files Claude Code reads and edits |
| `~/.claude` | `~/.claude` | rw | Claude Code config, memory, and project settings |
| `~/.claude.json` | `~/.claude.json` | rw | Claude Code authentication and session state |
| `~/.codex` | `~/.codex` | rw | Codex config (`config.toml`) and authentication (`auth.json`) |
| `/usr` | `/usr` | ro | Host compilers, libraries, and tools (gcc, make, etc.) |
| `/etc/alternatives` | `/etc/alternatives` | ro | Debian alternatives symlinks (auto-detected) |
| Per-run `xdg-dbus-proxy` socket | `/run/user/$UID/bus` | rw | Desktop notifications only (when `xdg-dbus-proxy` is installed) |

The default `config.in` also mounts ccstatusline and ccache. See [Configuration](#configuration) to customise.

## Extra build steps

To add packages or tools to the image, copy the template and uncomment what you need:

```bash
cp extra-build.sh.in extra-build.sh
vi extra-build.sh
./claude-docker-build
```

For example, uncomment the Node.js lines to install Node.js 20 and ccstatusline. 

## Configuration

Copy the template and edit to taste:

```bash
cp config.in config
vi config
```

`config` lets you set `WORK_ROOT` and `EXTRA_DOCKER_ARGS` (an array of extra `docker run` flags). The defaults in `config.in` include mounts for ccstatusline and ccache. If no `config` file exists, `config.in` is used as-is.

For a one-off run, set `CLAUDE_DOCKER_EXTRA_ARGS` to whitespace-separated Docker flags:

```bash
CLAUDE_DOCKER_EXTRA_ARGS='-p 8554-8556:8554-8556' claude-docker
```

These flags are added after `EXTRA_DOCKER_ARGS` and before the image name. The variable is split on whitespace; shell quotes and expansions inside its value are not interpreted. Use the `EXTRA_DOCKER_ARGS` array in `config` for arguments containing spaces. The `-p` example publishes ports on host interfaces, so only use it when that exposure is intended.

## Setup

```bash
# Build the image (uses your username automatically)
./claude-docker-build

# Full rebuild (no cache)
./claude-docker-build --full

# Setup ccstatusline (tmux/screen status bar integration)
./claude-docker-npx ccstatusline@latest
```

## Usage

Run from anywhere under `~/work`:

```bash
cd ~/work/my-project
claude-docker          # starts Claude Code
codex-docker           # starts OpenAI Codex
claude-docker-bash     # drops into a shell in the container
claude-docker-npx ...  # runs npx in the container
```

Claude and Codex share a single image. The launcher behaviour is selected by the name it's
invoked as — `codex-docker`, `claude-docker-bash`, and `claude-docker-npx` are symlinks to
`claude-docker`, and `codex-docker-build` is a symlink to `claude-docker-build` (either name
builds the shared image).

### Codex authentication

Both tools share the image but keep separate config/auth. Codex stores everything under
`~/.codex` (mounted rw), so authenticating once persists across runs.

Use the **device-code** flow to sign in with ChatGPT — the default browser flow binds a
callback on `localhost:1455` inside the container, which the host browser can't reach:

```bash
codex-docker login --device-auth   # prints a code + URL to open in your browser
```

To use an API key instead, uncomment the `-e OPENAI_API_KEY` line in `config` (see
[Configuration](#configuration)). Note a set `OPENAI_API_KEY` overrides the ChatGPT session.
