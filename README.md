# sysmon

A lightweight, dependency-light **system monitor daemon** in a single POSIX shell script. Polls SSH auth, OpenRC services, Docker containers, local HTTP endpoints, and resource usage, and fires notifications on state changes.

Borrowed from the [LAPTOO homelab](https://laptoo.xyz) (Alpine Linux / OpenRC / Cloudflare Tunnel).

> **yep this is vibecoded aswell**

## Requirements

- POSIX `sh` (dash, busybox ash, bash — anything)
- `curl`, `date`, `stat`
- Optional per-feature: `docker` (docker plugin), OpenRC `rc-service` (services plugin)
- Optional for desktop notifications: `notify-send` + `paplay` and a `hostenv`-style wrapper (see below)

## Install

```sh
sudo install -m 755 bin/sysmon /usr/local/bin/sysmon
sudo mkdir -p /usr/local/lib/sysmon/{plugins,state,dedup} /etc/sysmon
sudo install -m 755 plugins/*.sh /usr/local/lib/sysmon/plugins/
sudo install -m 644 /etc/sysmon/config.sh /etc/sysmon/config.sh  # start from config.sh.example
# (optional) symlink freedesktop sounds into /usr/local/lib/sysmon/sounds/
sudo install -m 755 openrc/sysmon /etc/init.d/sysmon
sudo rc-update add sysmon default
sudo rc-service sysmon start
```

The daemon reads `CONFIG` from `/etc/sysmon/config.sh` (override with `sysmon /path/to/config`).

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

### `hostenv`

Desktop/sound delivery goes through a `hostenv` helper that locates the login session's `DBUS_SESSION_BUS_ADDRESS`, `PULSE_SERVER`, and `WAYLAND_DISPLAY`, so the daemon (running as root a headless init context) can reach the user's GUI. If you don't need desktop notifications, just `export PATH` such that `hostenv` is a no-op passthrough (or point `notify-send` at your own session).

## Plugins

| Plugin | Watches | Notifies on |
|---|---|---|
| `ssh.sh` | `/var/log/messages` sshd lines | accepted logins (known vs unknown IP), failed passwords, logouts, disconnects |
| `services.sh` | `rc-service <svc> status` for `WATCH_SERVICES` | started / stopped / crashed / inactive |
| `docker.sh` | `docker ps -a` container states | up / exited / restarting / paused / dead |
| `tunnel.sh` | HTTP HEAD/GET of `WATCH_ENDPOINTS` | down / back online |
| `resources.sh` | disk, memory, load | warn / critical / recovery (hysteresis) |
| `system.sh` | — | heartbeat to events log every 30 min |

`commands.sh` (not enabled by default on this repo template) tails a command log — it's a homelab-specific extra; drop it from the plugin dir if you don't have that log.

## Layout

```
bin/sysmon            # the daemon
plugins/*.sh          # optional plugins (self-registering)
openrc/sysmon         # OpenRC init wrapper (supervise-daemon)
config.sh.example     # documented config template
sounds/               # freedesktop sound symlink references
```

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
