# Omarchy compatibility pin

This file is the single source that pins what a full Omarchy update must keep
compatible for Najm Downloader. If an Omarchy update (or a bump on our side)
changes any row below, expect the corresponding symptom and fix the coupling —
the runtime health reporting in the host (`ping` → `osd`/`deps`) is what turns
silent breaks into visible warnings first.

## Detectors

Run after any Omarchy update whose origin you are unsure about (they only need
a checkout, no browser involved):

```bash
omarchy plugin validate .                    # plugin manifest/schema
qmllint -I /usr/share/omarchy/shell Panel.qml Osd.qml   # Quickshell/QML interfaces
python3 -m py_compile host/najm-ytdlp-host   # host (no test infra exists)
```

Then drive a real download once — the OSD warning row in the `najm.downloads`
widget popup reports `osd: missing|broken` (with reason) instead of failing
silently, and the widget's status line shows which yt-dlp/ffmpeg/shell deps are
present. `printf '\x12\x00\x00\x00{"action":"ping"}' | NDLP_NO_OMARCHY=1 ./host/najm-ytdlp-host`
checks the raw `ping` payload (`osd`, `osdIssue`, `deps`).

## Pinned contract

| Surface | Pinned shape | Symptom if an update breaks it |
|---|---|---|
| Plugin manifest | `"schemaVersion": 1`, `kinds: ["bar-widget","panel"]`, `entryPoints: {barWidget: Panel.qml, panel: Osd.qml}`, `keepLoaded: true` | `omarchy plugin validate` fails / widget missing from the bar |
| Quickshell imports | `QtQuick`, `QtQuick.Layouts`, `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `qs.Commons`, `qs.Ui` (`Panel.qml:1-6`, `Osd.qml:8-13`) | `qmllint` errors; widget/OSD refuse to load |
| Bar widget | `BarWidget` + `BarIconButton`/`Button` from `qs.Ui`; themed via `Color.*`/`Style.*` | widget renders wrong colors or fails to load |
| OSD IPC | `OSD_IPC_TAG = "nd-osd-1"`, `OSD_IPC_VERSION = 1` (host `najm-ytdlp-host` ~line 115; mirrored `OsdModel.js`). Payload fields: `icon`, `message`, `value`, `progressText`, `max`, `duration`, `ipc`, `iface_version`. Command shape: `omarchy-shell -q najm.osd show <json>` / `omarchy-shell -q najm.osd close`; layer-shell namespace `najm-osd`; `osd_progress()`/`osd_close()`/`_osd_show()` in the host. The panel is driven directly by this plugin — `omarchy.clonedFrom` must NOT be set (stock `omarchy.osd` keeps serving system OSDs) | Missing progress card during downloads; host `ping` reports `osd: broken` + reason; `OsdModel.js`/`Osd.qml open()` logs an ipc-mismatch `console.warn` |
| OSD panel model | `OsdModel.js` `stacked` title-over-bar layout + `readout`; stays in sync with the host `osd_progress()` payload | card renders single-row or wrong readout |
| Theme state dir | `~/.local/state/omarchy/current/theme/{colors.toml,shell.toml,theme.name}` + machine overlay `~/.config/omarchy/shell.toml` (host read-only, whitelist-regexed) | popup keeps the single Solitude fallback in `extension/theme.css`; header shows `reload needed` / `data-theme-error` |
| Window rounding | `hyprctl -j getoption decoration:rounding` (3s timeout, array argv) | popup/options buttons fall back to default radius |
| Font family | `fc-match -f "%{family[0]}" monospace` | popup mono text falls back to the CSS stack |
| Host tooling | `omarchy-shell`, `omarchy-notification-send` resolved via `omarchy_tool()` (PATH, then `OMARCHY_PATH/bin`/`/usr/share/omarchy/bin`) | `osd`/`deps.omarchyShell` flip to `missing`; notifications fall back to `notify-send` |

## Browser-side pins (Omarchy independent)

- Extension id pinned by the committed SPKI `key` in `extension/manifest.json`
  (16-byte hex→`a-p` mapping, shared with `install.sh`). Never regenerate.
- NativeMessagingHosts manifests: canonical roots + conservative discovery in
  `host/browsers.sh` (shared with `install.sh`/`uninstall.sh`). Discovery only
  registers a non-canonical Chromium-family root whose flags conf already
  exists — it never invents a config path.
- `ping` reply is additive-forward-compatible (`osd`, `osdIssue`, `deps` were
  added without breaking the `ytdlp`/`ffmpeg` booleans the browser classifiers
  key on).
- Setup marker (`~/.local/state/najm-downloads/installed.json`) schema: the
  journal fields `installed_from` (dir the browser side is served from),
  `served_git` (that checkout's HEAD at install, best-effort) and
  `flags_confs` (flags-conf names, because `profiles` dirs don't map 1:1 to
  conf names) drive the removal watcher and marker-driven `uninstall.sh`.
  install.sh writes them; uninstall.sh and `Panel.qml` read them — keep the
  field names in sync if any side evolves.