# Implementation Plan: Removal & Update Lifecycle (ytdlp-extension)

## Problem

`omarchy plugin remove najm.downloads` only disables the plugin and `rm -rf`s
its clone under `~/.config/omarchy/plugins/` (verified against
`/usr/bin/omarchy-plugin-remove`). It runs no scripts and touches nothing else,
so the browser side lives on forever:

- `--load-extension=` in every `*-flags.conf`
- `NativeMessagingHosts/com.najm.ytdlp.json` in each Chromium profile
- the setup marker `~/.local/state/najm-downloads/installed.json`
- the agent process + `$XDG_RUNTIME_DIR/najm-ytdlp/` socket (and the
  `~/.local/state/najm-ytdlp/` fallback)

A re-`plugin add` is then *not* fresh: the stale marker suppresses the widget's
setup pane, install.sh never runs, and the browsers keep pointing at whatever
path the marker recorded (on this machine, the dev checkout).

## Goal

`omarchy plugin remove` → watcher fires → everything the plugin installed is
cleaned (browser side + runtime), downloads dir untouched → reinstall is
guaranteed fresh. Update keeps browsers at the released popup automatically.
Dev checkout stays untouched unless explicitly re-pointed.

## Key decisions

- **Served-git model**: the marker records `served_git` (clone HEAD at install)
  + `installed_from` (the dir the browser side is actually served from). The
  widget compares them against the installed clone's HEAD.
- **Marker-driven uninstall**: `uninstall.sh` no longer sources
  `host/browsers.sh`; it acts only on the marker. This is what lets the
  state-dir copy (`~/.local/state/najm-downloads/uninstall.sh`) run
  self-contained after the plugin clone is gone. Requires a new marker field
  `flags_confs` (the marker's `profiles` are `~/.config`-relative dirs, which
  do not map 1:1 to flags-conf names).
- **Systemd path watcher**: `najm-downloads-watch.path` fires on the plugins
  dir (top-level add/remove only — `PathChanged` does not fire on in-subdir
  git pulls, so updates land on the Panel self-heal, not the watcher). The
  service runs the state-dir copy with `--if-plugin-gone`, which exits 0
  unless the recorded `installed_from` dir is gone.
- **Process-group agent kill**: the agent runs `start_new_session=True` and
  has no SIGTERM handler; killing only it would orphan the child yt-dlp (which
  keeps downloading). Kill the whole process group (guard pgid != 1/$$).
- **Watcher units registered on every install, even from the dev checkout** —
  they are dormant there (guard keys off `installed_from`) but self-heal if
  the dev checkout is later removed.

## Task List

### 1. `install.sh`

- Compute `SERVED_GIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"`
  and `INSTALLED_FROM="$ROOT"`.
- Pass `served_git`, `installed_from`, and `flags_confs` (the conf names) into
  the marker writer alongside the existing fields.
- After the marker write:
  - `cp "$ROOT/uninstall.sh" "$STATE_DIR/uninstall.sh"` + `chmod +x`
    (refreshed on every install; it acts on marker data, not its own dir).
  - If `systemctl --user` is reachable, write
    `~/.config/systemd/user/najm-downloads-watch.path` +
    `najm-downloads-cleanup.service`, `daemon-reload`, `enable --now` the
    `.path`; on failure warn that uninstall must be manual.

### 2. `uninstall.sh` — marker-driven rewrite

- args: `--if-plugin-gone` optional.
- `--if-plugin-gone`: exit 0 unless marker exists and `installed_from` is not
  a directory; then fall through to full cleanup.
- Full cleanup (all `|| true` / `set -u`-safe):
  - strip marker `extension_dir` from each marker `flags_confs` conf
    (reuse the existing sed logic; `.najm-bak` stays as the safety net);
  - remove `$HOME/.config/<profile>/NativeMessagingHosts/com.najm.ytdlp.json`
    per marker `profiles`;
  - process-group kill the agent, then remove
    `$XDG_RUNTIME_DIR/najm-ytdlp/` and `~/.local/state/najm-ytdlp/` (guard
    empty vars — never `rm -rf /`);
  - `systemctl --user stop/disable` the `.path`, remove both unit files,
    `daemon-reload`;
  - remove `$STATE_DIR/uninstall.sh`, the marker, rmdir `$STATE_DIR` if empty.
- Plain `./uninstall.sh` = same full cleanup, no gone-condition.

### 3. `tools/omarchy-remove.sh`

`uninstall.sh` (state-dir copy, fallback repo-root) then
`omarchy plugin remove najm.downloads --yes`.

### 4. `Panel.qml`

- Marker load captures `served_git` / `installed_from`.
- `git -C pluginDir rev-parse HEAD` via a small `Process` (best-effort).
- Self-heal on load: when `installed_from == pluginDir` and git resolves and
  `served_git != HEAD` → `startSetup()` once (idempotent; marker becomes HEAD).
- Dev case (`installed_from` set, `!= pluginDir`, `pluginDir/install.sh`
  exists): "Update to this plugin's version" button → `startSetup()`.
- Uninstall action: armed-confirm → run `$STATE_DIR/uninstall.sh` (fallback
  `pluginDir/uninstall.sh`) → on exit 0 `Quickshell.execDetached(["omarchy",
  "plugin", "remove", "najm.downloads", "--yes"])`.
- Both live in a Manage footer in the popup body (visible whenever the popup
  is open; the popup is only reachable while `busy || setupNeeded`).

### 5. Docs

- AGENTS.md removal & update contract section.
- `docs/omarchy-compat.md` marker-schema row.

## Verification

- `python3 -m py_compile host/najm-ytdlp-host`
- `bash -n install.sh uninstall.sh tools/omarchy-remove.sh`
- `qmllint -I /usr/share/omarchy/shell Panel.qml`
- `omarchy plugin validate .`
- Live drill: fresh `install.sh` from a `/tmp` clone → delete the clone dir →
  watcher fires → browser entries stripped → reinstall is fresh (setup pane).