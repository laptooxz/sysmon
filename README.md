# sysmon

A lightweight, dependency-light **system monitor daemon** in a single POSIX shell script. Polls SSH auth, OpenRC services, Docker containers, local HTTP endpoints, and resource usage, and fires notifications on state changes.

> **yep this is vibecoded aswell**

> **Built for one homelab.** This is written for and tested only on `laptoo`
> (Alpine Linux, OpenRC, `/var/log/messages`, my own paths). It can be adapted
> to other systems — see [Portability](#portability) — but it is not portable
> as-is, and it has no CI, no test suite and no security audit. Read the source
> before running it anywhere that matters.

## Requirements

- POSIX `sh` (dash, busybox ash, bash — anything)
- `curl`, `date`, `stat`
- Optional per-feature: `docker` (docker plugin), OpenRC `rc-service` (services plugin)
- Optional for desktop notifications: `notify-send` + `paplay`, plus a `hostenv` helper (**not shipped here** — see below)

## Install

```sh
sudo install -m 755 bin/sysmon /usr/local/bin/sysmon
sudo mkdir -p /usr/local/lib/sysmon/plugins /usr/local/lib/sysmon/sounds /etc/sysmon
sudo mkdir -p /var/lib/sysmon/state /var/lib/sysmon/dedup
sudo install -m 755 plugins/*.sh /usr/local/lib/sysmon/plugins/
sudo install -m 644 config.sh.example /etc/sysmon/config.sh
# (optional) symlink freedesktop sounds into /usr/local/lib/sysmon/sounds/
sudo install -m 755 openrc/sysmon /etc/init.d/sysmon
sudo rc-update add sysmon default
sudo rc-service sysmon start
```

The daemon reads `CONFIG` from `/etc/sysmon/config.sh` (override with
`sysmon /path/to/config`). Runtime state, dedup and the events log live under
`/var/lib/sysmon/`. The ntfy token, if used, is read from
`/etc/sysmon/tokens/ntfy.sh`.

## How it works

- Reads config, sources every `plugin_*.sh` from the plugins dir.
- Each plugin registers a name and implements `plugin_<name>_init()` (once at startup) and `plugin_<name>_check()` (each poll).
- State is diffed against files in the state dir — **alerts fire only on change**, not on every poll.
- Resource alerts use **hysteresis** (warn → crit → recover), so you're not spammed.
- Per-key dedup with timeouts prevents notification storms.
- Every event is appended to a JSONL events log.

### Notification triple

`notify()` fan-outs to, in parallel:

1. **Desktop** — `hostenv notify-send …` (GUI session)
2. **Sound** — `hostenv paplay <sound>` (freedesktop oga)
3. **ntfy** — publish to a local `ntfy` server (or any ntfy/webhook)

Plus an optional **off-box critical forward**: reliability-priority (≥5) infra alerts matching `Service:*` / `Tunnel*` / `Docker:*` are also POSTed to a public `ntfy.sh/<topic>` — so you still get paged when the local tunnel/whole host is down.

> **Privacy note on the public ntfy.sh forward.** `ntfy.sh` topics are
> public: **the topic name is the only secret.** Anyone who guesses or learns
> it can subscribe to every forwarded alert, and those alerts can contain host
> names, endpoint labels, container names and mailbox/domain details. Use a
> long, random topic name, treat it like a password, and don't reuse it across
> services. If that isn't acceptable, either leave
> `NTFY_CRITICAL_TOPIC=""` (local-only delivery) or self-host ntfy and point
> the forward at your own instance.

### `hostenv`

Desktop/sound delivery goes through a `hostenv` helper that locates the login session's `DBUS_SESSION_BUS_ADDRESS`, `PULSE_SERVER`, and `WAYLAND_DISPLAY`, so the daemon (running as root a headless init context) can reach the user's GUI.

**`hostenv` is not part of this repo** — it's a small external helper in my
dotfiles. Anything with the same job works: it must accept a command and run
it with the desktop user's session environment. If you don't need desktop
notifications, put a `hostenv` shim on `PATH` that just `exec "$@"`, or point
`notify-send`/`paplay` at your own session however you prefer.

## Plugins

| Plugin | Watches | Notifies on |
|---|---|---|
| `ssh.sh` | `/var/log/messages` sshd lines | accepted logins (known vs unknown IP), failed passwords, logouts, disconnects |
| `services.sh` | `rc-service <svc> status` for `WATCH_SERVICES` | started / stopped / crashed / inactive |
| `docker.sh` | `docker ps -a` container states | up / exited / restarting / paused / dead |
| `tunnel.sh` | HTTP HEAD/GET of `WATCH_ENDPOINTS` | down / back online |
| `resources.sh` | disk, memory, load | warn / critical / recovery (hysteresis) |
| `system.sh` | — | heartbeat to events log every 30 min |

`commands.sh` tails a homelab-specific command log
(`/var/log/sysmon_cmds.log`). It stays inert while that file doesn't exist, but
the install step above copies every `plugins/*.sh`, so remove it from the
plugin dir if you don't have that log.

## Layout

```
bin/sysmon            # the daemon
plugins/*.sh          # optional plugins (self-registering)
openrc/sysmon         # OpenRC init wrapper (supervise-daemon)
config.sh.example     # documented config template
sounds/               # freedesktop sound symlink references
```

Not in this repo, but referenced at runtime: a `hostenv` helper on `PATH`
(desktop/sound), an `ntfy-push`-style publisher if you use ntfy, and
`/etc/sysmon/tokens/ntfy.sh` for a token.

## Portability

This is tuned to Alpine/OpenRC. Things that will not work unchanged elsewhere:

- **`plugins/ssh.sh`** tails `/var/log/messages` and expects Alpine's `sshd[`/
  `sshd-session[` line shapes. Debian/Ubuntu log to `/var/log/auth.log`, most
  systemd distros use the journal, and the exact wording has changed across
  OpenSSH releases (see the notes in the script). Expect to rewrite the parse.
- **`plugins/services.sh`** uses `rc-service` — OpenRC only. `docker.sh` and
  `tunnel.sh` are portable as long as `docker` / `curl` exist.
- **`bin/sysmon`** hardcodes `HOME`, `PATH`, `DATA_DIR=/var/lib/sysmon`,
  `PLUGIN_DIR`/`SOUND_DIR` under `/usr/local/lib/sysmon`, and the ntfy token
  path. `openrc/sysmon` is an OpenRC wrapper. Change those (and write a unit
  for your init system) to run it elsewhere.
- **`DESKTOP_USER`** defaults to `main`, and desktop delivery expects `sudo`.

## Writing a plugin

```sh
register_plugin myplugin

plugin_myplugin_init() {
    write_state "myplugin.known" ""
}

plugin_myplugin_check() {
    cur=$(some_check)
    prev=$(read_state myplugin.known)
    [ "$cur" != "$prev" ] && notify "My: widget" "changed to $cur" 3 "dialog-information.oga"
    write_state myplugin.known "$cur"
}
```

Helper functions available: `notify`, `log_event`, `dedup_check <key> <secs>`, `read_state`, `write_state`, `ip_in_net`.
