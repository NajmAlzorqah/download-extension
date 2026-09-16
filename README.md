# Najm Downloader

A Chromium / Brave-Origin extension that downloads videos, subtitles, and
playlists through a local [yt-dlp](https://yt-dlp.github.io/) native host,
without cookies or accounts. Companion to the Omarchy "Download Video"
extension, but with a full popup UI that mirrors **exactly** what the video
offers:

- **quality**: one option per resolution actually offered by the video, from
  highest to lowest (nothing more — no codec names). The best codec for each
  resolution is chosen automatically (H.264 stays default for compatibility;
  VP9/AV1 only when no H.264 exists), the highest resolution is preselected,
  and a single `Audio only` entry (best track) covers audio extraction
- **sample size**: probed streams include their byte size, so each quality
  option shows an approximate size (e.g. `1080p · ~7 MB`) and the meta line shows
  the estimate for the whole download — for a playlist, one video's size times
  the entry count. Estimates, not exact: sizes come from yt-dlp's
  `filesize/filesize_approx`.
- **subtitles**: the actual language tracks offered by the video — manual
  subtitles and auto-generated captions separately (an `Auto-generated`
  group) — so you can never pick a language the video doesn't have (e.g. an
  Arabic track that doesn't exist simply isn't listed)
- **playlists**: paste or open a playlist and the checkbox turns on automatically.
  Resolutions/subtitle languages are sampled from the first video and offered as
  usual; if the first video can't be reached, a preset resolution list
  (Best…144p, Audio only) is shown instead. Every video downloads with the same
  resolution + subtitle choices, files are numbered in exact playlist order
  (`001_Title … `) inside a folder named after the playlist, and one failed
  video doesn't abort the rest
- live progress via the **Omarchy OSD** while downloading (same overlay as
  the default "Download Video"), a popup progress bar with %/speed/ETA,
  and Cancel
- completion notification styled like the defaults (`omarchy-notification-send`
  with a thumbnail preview and an "open in mpv" action); errors notify too

## Layout

```
extension/          MV3 extension (manifest rendered by install.sh)
  manifest.json.in  template — @@KEY@@ is replaced with your RSA public key
  background.js     owns a single native-messaging port, routes probe/download/cancel
  popup.{html,css,js}  toolbar popup
  options.{html,js}    defaults (output dir, resolutions, subtitle defaults)
host/
  najm-ytdlp-host   Python native-messaging host (stdio, 4-byte LE framing)
  com.najm.ytdlp.json.tpl  host manifest template
  najm-ytdlp-key.pem  generated RSA key (stable extension id) — keep private
tools/make-icons.py icon generator (regenerate: `uv run --directory tools python make-icons.py`)
install.sh / uninstall.sh
```

## Install

Requires `yt-dlp` (in `PATH` or at `/usr/bin/yt-dlp`), `ffmpeg`, `openssl`, `python3`.

```bash
./install.sh
```

What it does:

1. Generates `host/najm-ytdlp-key.pem` once and renders `extension/manifest.json`
   with the matching SPKI public key. The extension id
   (`sha256(spki)` → first 16 bytes hex-mapped `0-f → a-p`) is derived from the
   same key, so the id is stable and the host's `allowed_origins` is always correct.
2. Registers `com.najm.ytdlp.json` in:
   - `~/.config/chromium/NativeMessagingHosts/`
   - `~/.config/BraveSoftware/Brave-Origin/NativeMessagingHosts/`
3. Appends the extension dir to the existing `--load-extension=` line in
   `~/.config/chromium-flags.conf` and `~/.config/brave-origin-flags.conf`
   (timestamped `.najm-bak` backup; idempotent).

Then **restart the browser**. The extension loads with the other Omarchy
extensions; click the icon in the toolbar.

## Use

1. Open a video or playlist page (or paste a URL) — the popup probes it automatically.
2. Pick the **actual quality this video offers** — one entry per resolution
   (highest first, best codec chosen for you) plus `Audio only`; subtitle
   language tracks the video actually offers; playlist on/off.
   For a playlist, the resolutions come from the first video (or presets) and
   subtitles default to **all available**.
3. Download; progress shows in the Omarchy OSD overlay and the popup.
   Files go to your output dir (default `~/Videos`, change in Options);
   playlist videos are numbered by playlist order.

Subtitle notes:

- Enable **Download subtitles** → the language list contains the tracks the
  video offers. By default only **manual** subtitles are eligible: `All available`
  means every manual track. Auto-generated captions are downloaded only when you
  tick **Auto-generated**, and then for the chosen language only (or a single
  default, English, for `All available`) — never a per-language flood. For
  playlists the same choice is applied to every video, and a language you pick
  stays picked. If the video offers no subtitles at all, the option is disabled
  with a hint.
- When the site is rate-limiting subtitle requests (YouTube's HTTP 429), the
  host retries a few times, then downloads the video without subtitles and
  shows a clear warning in the popup instead of silently failing.
- **Convert to SRT** / **Embed** apply when the source offers VTT/other tracks.

Download completes with a notification (thumbnail preview + "open with mpv"),
errors with a critical one — identical to the Omarchy Download Video toasts.
Set `NDLP_NO_OMARCHY=1` when launching the host to disable OSD/notifications.

## How it talks to yt-dlp

The background service worker connects a native port
(`chrome.runtime.connectNative("com.najm.ytdlp")`). Requests are length-prefixed
JSON on stdio:

- `ping` → host/yt-dlp/ffmpeg availability
- `probe` → title, thumbnail, duration, **all real format streams** (id, size,
  fps, ext, codecs), manual + auto subtitle language maps; for a playlist it
  also samples the first video so the same options are real, plus entry count
- `download` → streams `start` / `progress` (pct %speed %eta) / `file` / `done`
  (a chosen `formatId` downloads that exact stream instead of re-deriving)
- `cancel` → terminates the running yt-dlp process

Progress also drives the Quickshell OSD (`omarchy-osd`, throttled ~4/sec,
same glyphs as the default Download Video) and completion/failure toasts use
`omarchy-notification-send` with thumbnail + mpv action; `notify-send` is the
fallback when Omarchy isn't present.

Security mirrors the Omarchy host: only `http(s)` URLs; `--` ends options
(array argv, no shell); output is confined to the configured dir via `realpath`;
all echoed strings are stripped of ANSI/control characters; inputs are
whitelist-validated.

## Troubleshooting

- Extension not in the toolbar after restart → `chrome://extensions` must show
  "Najm Downloader"; re-run `./install.sh` and restart again.
- Host status dot red in the popup → the native host wasn't found. Verify
  `com.najm.ytdlp.json` exists in the browser's `NativeMessagingHosts`, the
  `path` and `allowed_origins` are correct, and you restarted after install.
- `--load-extension` edit backfires → restore the `.najm-bak` backup.
- Headless / custom `--user-data-dir` runs look for host manifests inside the
  profile (`<user-data-dir>/NativeMessagingHosts`), not `~/.config/…`.

## Uninstall

```bash
./uninstall.sh            # removes host manifests + flags, keeps the RSA key
./uninstall.sh --purge-key  # also delete the key (new extension id on reinstall)
```