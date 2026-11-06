# claude-docker — `warden`

`warden` runs [Claude Code](https://claude.ai), [Codex](https://developers.openai.com/codex)
and [OpenCode](https://opencode.ai/v2/docs/) in a Docker container. The agent sees the
current project and your host toolchain (`/usr`, read-only), and nothing else from your
home directory except its own config.

## Quick start

```bash
fish_add_path /path/to/claude-docker   # or add it to PATH in bash
warden build

cd ~/work/my-project
warden claude
```

## Usage

```bash
warden claude [args]      # Claude Code, e.g. warden claude --resume
warden codex [args]       # Codex
warden opencode [args]    # OpenCode
warden bash               # shell in the container, all agents available
warden npx [args]
warden build [--full]     # update agents; --full rebuilds without cache
warden --help
```

Run it from the project root. Only the current directory is mounted, so from a
subdirectory git won't find `.git`. The mount is your real files, not a copy: commit
before you hand over a task.

Don't run an agent from inside this checkout, since it could edit the launcher. To avoid
that entirely, install a root-owned copy:

```bash
sudo install -d /opt/warden
sudo install -m 755 warden warden-build /opt/warden/
sudo install -m 644 Dockerfile config config.in extra-build.sh /opt/warden/
sudo ln -s /opt/warden/warden /usr/local/bin/warden
```

## How it works

```
              you  (fish / bash, inside a project folder)
                               │
                               ▼
          ┌─────────────────────────────────────────┐
          │  warden                 launcher script │  reads config, checks the
          │                                         │  folder, picks the mounts
          └────────────────────┬────────────────────┘
                               │  docker run --runtime runsc
                               ▼
          ┌─────────────────────────────────────────┐
          │  rootless Docker daemon                 │  runs as your user:
          │                                         │  container root = your UID
          └────────────────────┬────────────────────┘
                               │  starts the container inside gVisor
                               ▼
          ┌─────────────────────────────────────────┐
          │  gVisor sandbox (runsc)                 │  a user-space kernel that
          │   ┌─────────────────────────────────┐   │  answers the agent's
          │   │    claude / codex / opencode    │   │  system calls itself
          │   └─────────────────────────────────┘   │
          └──────────┬────────────────────┬─────────┘
                     │                    │
                     │ file access        │ few, filtered syscalls
                     ▼                    ▼
          ┌────────────────────┐  ┌────────────────────┐
          │  mounted folders   │  │  host Linux kernel │
          │  project       rw  │  └────────────────────┘
          │  ~/.claude etc rw  │
          │  /usr          ro  │
          └────────────────────┘
```

gVisor is optional. Without it the container uses runc and talks to the host kernel
directly. All capabilities are dropped, except `DAC_OVERRIDE` under rootless Docker.

This protects your system, not your project: agents can still edit the project, read
their own logins and use the network. Keep permission prompts on and use git.

## Mounts

Every run gets the project (rw), `~/.agents` (rw), `/usr` and `/etc/alternatives` (ro),
and a D-Bus socket limited to desktop notifications.

Each agent only gets its own config and logins:

| Agent | Mounts |
|---|---|
| claude | `~/.claude`, `~/.claude.json`, `~/.config/ccstatusline` |
| codex | `~/.codex` |
| opencode | `~/.config/opencode`; data, cache and state in `~/.local/share/opencode-docker` etc. |
| bash, npx | all of the above |

OpenCode shares your host config but keeps its own sessions and logins, so connect
providers once inside the container.

## Configuration

```bash
cp config.in config    # optional; config.in is used if config is missing
```

| Setting | Default | |
|---|---|---|
| `DOCKER_CONTEXT` | `rootless` | `default` for rootful Docker |
| `DOCKER_RUNTIME` | runc | `runsc` for gVisor, `io.containerd.kata.v2` for Kata (rootful only) |
| `WORK_ROOT` | any folder | only allow launches under this folder |
| `BASE_IMAGE` | your distro | must match host `/usr` |
| `EXTRA_DOCKER_ARGS` | | extra `docker run` flags, e.g. a ccache mount |

For one run: `CLAUDE_DOCKER_EXTRA_ARGS='-p 8554:8554' warden claude`. Don't add
`--privileged`, the Docker socket or your whole home directory.

To add packages to the image, `cp extra-build.sh.in extra-build.sh`, edit it, and run
`warden build`.

## Rootless Docker

```bash
sudo apt install uidmap docker-ce-rootless-extras
dockerd-rootless-setuptool.sh install    # --force if rootful Docker is also running
sudo loginctl enable-linger "$USER"      # optional, start at boot
```

This also makes `rootless` your default `docker` context. The two daemons don't share
images, so run `warden build` again after switching.

## gVisor

```bash
URL=https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -m)
wget $URL/gvisor.tar.zstd $URL/gvisor.tar.zstd.sha512
sha512sum -c gvisor.tar.zstd.sha512
sudo tar --zstd -xf gvisor.tar.zstd -C /usr/local/bin
```

`sudo runsc install` only sets up rootful Docker. For rootless, put this in
`~/.config/docker/daemon.json`:

```json
{"runtimes": {"runsc": {"path": "/usr/local/bin/runsc", "runtimeArgs": ["--ignore-cgroups"]}}}
```

Then `systemctl --user restart docker` and set `DOCKER_RUNTIME="runsc"` in `config`.
`warden bash -c 'uname -r'` should print `4.19.0-gvisor`.

Downsides: builds are several times slower (40 small `gcc` runs: 6.8 s vs 1.4 s),
notifications don't work, and `docker stats` shows nonsense. Use `ps` instead.

If something fails:

- `unknown or invalid runtime name: runsc`: registered with the other daemon. Check
  `docker context show`.
- `Interactive authentication required`: add `--ignore-cgroups`.
- `pull access denied for claude-docker`: run `warden build` for this daemon.

## Logins

- **Codex**: use `warden codex login --device-auth`. The browser flow can't reach the
  container's localhost.
- **OpenCode**: `/connect`, then `/models`. Or set API keys via `config`.
- The container's `localhost` is not your host's, so local Ollama or MCP servers need
  explicit networking.

## tmux

Run tmux on the host and `warden <tool>` inside each pane. The tmux socket is not shared
with the container on purpose. ccstatusline is Claude Code's own status line; customize
it with `warden bash -c ccstatusline`.

## Credits

Based on [claude-docker](https://github.com/tguillem/claude-docker) by Thomas Guillem.
