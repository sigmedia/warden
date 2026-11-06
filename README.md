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

Options go before the tool:

```bash
warden --runtime runsc claude             # run inside gVisor
warden --context native claude            # use Docker's system (root) daemon
warden --work-root ~/work claude          # only allow launches under ~/work
```

Run it from the project root. Only the current directory is mounted, so from a
subdirectory git won't find `.git`. The mount is your real files, not a copy: commit
before you hand over a task.

Don't run an agent from inside this checkout, since it could edit the launcher. To avoid
that entirely, install a root-owned copy:

```bash
sudo install -d /opt/warden
sudo install -m 755 warden warden-build /opt/warden/
sudo install -m 644 Dockerfile extra-build.sh /opt/warden/
sudo ln -s /opt/warden/warden /usr/local/bin/warden
```

## How it works

This shows a run with `--runtime runsc` (gVisor). By default warden uses plain runc,
which skips the gVisor box.

```
              you  (fish / bash, inside a project folder)
                               │
                               ▼
          ┌─────────────────────────────────────────┐
          │  warden                 launcher script │  reads options, checks the
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

With the default runc, the container talks to the host kernel directly. All
capabilities are dropped, except `DAC_OVERRIDE` under rootless Docker.

This protects your system, not your project: agents can still edit the project, read
their own logins and use the network. Keep permission prompts on and use git.

## Mounts

Every run gets the project (rw), `~/.agents` (rw), `/usr` and `/etc/alternatives` (ro),
and a D-Bus socket limited to desktop notifications.

If uv is installed, it is mounted too: the binaries (ro), `~/.local/share/uv` and
`~/.cache/uv` (rw), and `~/.config/uv` (ro). Paths match the host, so a project `.venv`
made on the host works inside. The rest of `~/.local` is not mounted.

Each agent only gets its own config and logins:

| Agent | Mounts |
|---|---|
| claude | `~/.claude`, `~/.claude.json`, `~/.config/ccstatusline` |
| codex | `~/.codex` |
| opencode | `~/.config/opencode`; data, cache and state in `~/.local/share/opencode-docker` etc. |
| bash, npx | all of the above |

OpenCode shares your host config but keeps its own sessions and logins, so connect
providers once inside the container.

## Options

Options go before the tool. `warden build` takes its own.

| Option | Default | |
|---|---|---|
| `--context` | `rootless` | Docker daemon: `rootless` (per-user) or `native` (system, root) |
| `--runtime` | `runc` | `runsc` for gVisor, `io.containerd.kata.v2` for Kata (native only) |
| `--work-root DIR` | any folder | only allow launches under this folder |
| `--docker-args 'FLAGS'` | | extra `docker run` flags, repeatable, split on spaces |
| `--gpu` | off | pass NVIDIA and `/dev/dri` devices; always runs with runc |
| `--uv`, `--no-uv` | on if installed | mount host uv, its Pythons and cache |
| `build --full` | | rebuild without cache |
| `build --base-image IMAGE` | your distro | must match host `/usr` |

To change a default, edit the `DEFAULT_*` lines at the top of `warden`.

```bash
warden --docker-args '-e OPENAI_API_KEY' codex
warden --docker-args '-v /home/me/.cache/ccache:/home/me/.cache/ccache' bash
```

Don't pass `--privileged`, the Docker socket or your whole home directory.
To add packages, `cp extra-build.sh.in extra-build.sh`, edit it, and run `warden build`.

## GPU

`warden --gpu claude` passes `/dev/nvidia*` and `/dev/dri`. The NVIDIA driver libraries
and `nvidia-smi` come from the host's `/usr`, so no NVIDIA container toolkit is needed.
gVisor can't use this GPU driver, so `--gpu` always runs with runc.

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

Then `systemctl --user restart docker` and use `warden --runtime runsc ...`, or set
`DEFAULT_RUNTIME=runsc` in `warden`. `warden --runtime runsc bash -c 'uname -r'` should
print `4.19.0-gvisor`.

Downsides: builds are several times slower (40 small `gcc` runs: 6.8 s vs 1.4 s),
notifications don't work, and `docker stats` shows nonsense. Use `ps` instead.
If gVisor is your default, skip it for a heavy build with `warden --runtime runc`.

If something fails:

- `unknown or invalid runtime name: runsc`: registered with the other daemon. Check
  `docker context show`.
- `Interactive authentication required`: add `--ignore-cgroups`.
- `pull access denied for claude-docker`: run `warden build` for this daemon.

## Logins

- **Codex**: use `warden codex login --device-auth`. The browser flow can't reach the
  container's localhost.
- **OpenCode**: `/connect`, then `/models`. Or pass API keys with `--docker-args '-e ANTHROPIC_API_KEY'`.
- The container's `localhost` is not your host's, so local Ollama or MCP servers need
  explicit networking.

## tmux

Run tmux on the host and `warden <tool>` inside each pane. The tmux socket is not shared
with the container on purpose. ccstatusline is Claude Code's own status line; customize
it with `warden bash -c ccstatusline`.

## Credits

Based on [claude-docker](https://github.com/tguillem/claude-docker) by Thomas Guillem.
