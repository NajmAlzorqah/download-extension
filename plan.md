# Najm Downloader — Omarchy marketplace packaging plan

Goal: turn this repo into a single Omarchy plugin so the **whole stack** installs
with one line —

```bash
omarchy plugin add https://github.com/<you>/<repo>.git --enable
```

— and appears on the Omarchy plugin marketplace (plugins.omarchy.org).

`omarchy plugin add` deliberately runs **no plugin code** (clones, validates
manifest, flips the enabled bit). So the one-liner installs the plugin surface;
the **first click** runs the bundled installer that sets up the browser
extension + native host + deps (the omabib/omalibre/podshl lazy-setup pattern).

## Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| Plugin identity | **one merged plugin** `najm.downloads`, kinds `bar-widget` + `panel` | single `add`/`remove`, OSD travels with the widget |
| OSD IPC target | keep `najm.osd` | zero host changes; targets are arbitrary strings; target ≠ plugin id |
| Extension id | **committed SPKI** baked into `extension/manifest.json` (no keygen, no pem) | deterministic per-user id → `allowed_origins` always matches; no private key in repo |
| Browser coverage | **all 9 Omarchy-parity Chromium roots + Brave-Origin** | `omarchy-install-chromium-ytdlp` parity |
| Install trigger | first-click in the widget, streams `install.sh` output | validator forbids install hooks |
| Deps | check `/usr/bin/yt-dlp`, `/usr/bin/ffmpeg` (host hardcodes them); best-effort `omarchy-pkg-add` | host paths are fixed |

## Target layout (repo root == plugin)

```
manifest.json            <- Omarchy plugin manifest (id najm.downloads)
Panel.qml  Client.js     <- bar-widget: shared-queue monitor + setup pane
Formats.js Defaults.js
Osd.qml    OsdModel.js   <- panel kind: the merged download OSD (IpcHandler najm.osd)
bin/install.sh  (== top-level install.sh)   <- browser+host+deps installer
extension/   host/  tools/   (unchanged)     <- MV3 extension + native host
```

`install.sh` resolves its own root, so it works from a checkout **and** from the
installed plugin dir (`~/.config/omarchy/plugins/najm.downloads/install.sh`).
The flags line points `--load-extension=` at `<plugin>/extension`.

## What the first click does (install.sh)

1. compute extension id from the committed manifest `key` (sha256(SPKI DER) → a-p).
2. write `com.najm.ytdlp.json` native-host manifest into `NATIVE_DIRS` (10 roots).
3. merge `--load-extension=<plugin>/extension` into existing `*-flags.conf` files
   (always create for chromium + brave-origin).
4. check `/usr/bin/yt-dlp` + `/usr/bin/ffmpeg`, try `omarchy-pkg-add` on Omarchy.
5. write marker `~/.local/state/najm-downloads/installed.json` (widget reads it
   to flip out of "setup needed" mode; Profiles list drives the success hint).
6. print summary + "restart Chromium/Brave/Edge to load the extension".

uninstall.sh reverses 1–5 (never touches other tools' flags).

## Implementation phases

- [x] **P0 research** — Omarchy plugin contract, marketplace publish flow,
      plugin-add/validate internals, Quickshell Process/StdioCollector API.
- [x] **P1 repo restructure** — copy widget + OSD files to root, merged
      `manifest.json`, commit extension manifest with baked key, drop pem/keygen.
- [x] **P2 installers** — rewrite `install.sh`/`uninstall.sh` for 10 profiles,
      marker, deps; runnable from checkout and plugin dir. The flags merge
      keeps other tools' entries and drops a previous Najm checkout path; a
      bug that dropped the `--load-extension=` literal on re-merge was caught
      by testing uninstall→reinstall on the live machine and fixed.
- [x] **P3 widget setup UI** — `setupNeeded` state, install button, live log,
      marker watcher; bar stays visible until installed.
- [x] **P4 validation** — `omarchy plugin validate .`, `qmllint`, `py_compile`,
      `bash -n` all pass; install/uninstall cycle verified end-to-end.
- [x] **P5 machine swap** — old `najm.downloads` + `najm.osd` dirs replaced by
      `omarchy plugin add` of this repo (files had to be committed first —
      clone-based install ignores untracked files), the plugin's install.sh
      transitioned the flags repo→plugin path, browsers restarted, host
      round-trip verified.
- [/] **P6 docs + marketplace** — README/AGENTS/CONTRIBUTING/NOTICE updated;
      remaining: push to GitHub, then optionally submit via the
      `omacom/omarchy-plugin-marketplace` issue template (no screenshot needed —
      the template only wants the repo URL, category, ≤3 tags, install/remove
      docs).

## Marketplace submission checklist

- public GitHub repo, `manifest.json` at root, README, LICENSE (MIT, already).
- `omarchy plugin validate .` passes on the commit that gets listed.
- `preview.png` (widget popup + OSD screenshot) — marketplace optimizes it.
- `id` `najm.downloads`, `name`, `version`, `author`, `description`, `kinds`,
  `entryPoints`, `barWidget` block; `author`/category/tags in the issue: System,
  downloads, yt-dlp, browser.
- one-liner in README; note the first-click install + browser restart.
- "The marketplace validates listings, not plugin security" — keep the host
  security invariants (nothing from plugin input reaches a shell/yt-dlp).

## Open considerations

- Chrome Web Store is out of scope (native hosts can't ship through it); the
  unpacked-load model + our installer is the Omarchy pattern.
- `omarchy plugin update` fast-forwards the plugin checkout — the installer
  never writes into the plugin dir (marker lives in `~/.local/state`), so
  updates stay clean.
- If a new browser appears later, re-run install (widget: Re-run button).