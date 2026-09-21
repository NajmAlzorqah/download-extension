# Najm Downloader

A Chromium / Brave-Origin extension that downloads videos, subtitles, and
playlists through a local [yt-dlp](https://yt-dlp.github.io/) native host,
without cookies or accounts. Companion to the Omarchy "Download Video"
extension, but with a full popup UI that mirrors **exactly** what the video
offers — plus an Omarchy bar-widget (`najm.downloads`) that shares the same
download queue, so jobs survive popup/browser restarts and are manageable from
either surface. The whole thing is an **Omarchy plugin**: `omarchy plugin add
<url> --enable` installs it, and the widget's first click installs the browser
extension + native host into every Chromium-family browser on the machine.

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
- **video sections (chapters)**: when the video has YouTube chapters, a
  `Video sections` selector appears in the popup — embed them as navigable
  chapter markers into the file (MKV/MP4/WebM) or split the video into one file
  per section. Split downloads remove the duplicated whole-video copy
  (`Title.webm` → `Title - 01_Intro.webm`, `Title - 02_…`). Only offered for
  videos that actually have chapters and formats that can hold them (audio-only
  never shows it)
- live progress via the **Omarchy OSD** while downloading (same overlay as
  the default "Download Video"), a popup progress bar with %/speed/ETA,
  and Cancel
- completion notification styled like the defaults (`omarchy-notification-send`
  with a thumbnail preview and an "open in mpv" action); errors notify too
- **download queue**: add any number of videos — they download one after
  another, and a failed or cancelled item auto-advances to the next. The popup
  lists what's waiting (title + chosen options) with per-item remove and move
  up/down, and an in-flight queue survives a browser restart (the service
  worker mirrors it to `chrome.storage.local` and re-submits the jobs to the
  fresh host on wake; the active item restarts from scratch)

## Layout

The repository root is an Omarchy plugin; a git clone of it is a working plugin
(`omarchy plugin add <git-url> --enable`) and a checkout of it works the same
way:

```
manifest.json      Omarchy plugin manifest — bar-widget (najm.downloads) + the
                   panel kind that renders the download OSD (IPC target
                   najm.osd, so the native host is unchanged)
Panel.qml          bar-widget: shared queue monitor + first-click setup pane
                   (until install.sh writes its marker it installs the browser
                   side and streams the output)
Client.js Formats.js Defaults.js   widget JS (agent socket + popup ported logic)
Osd.qml OsdModel.js  panel kind: the stacked title-over-bar progress OSD
extension/         MV3 extension (static manifest.json; the committed SPKI key
                   pins the extension id — no private key exists in the repo)
  background-6.js   owns the native port, routes probe/download/cancel/reorder/getQueue
   popup/options/theme/controls  popup UI, defaults, live theme → CSS vars
host/
  najm-ytdlp-host            Python native-messaging host — shim ↔ JSON-lines
                             unix-socket agent (owns the shared queue)
  com.najm.ytdlp.json.tpl    host manifest template (@@HOST_PATH@@/@@EXT_ORIGIN@@)
install.sh / uninstall.sh  browser-side installer/uninstaller (10 Chromium-family
                             profiles; run by the widget's first click or by hand).
                             install.sh also arms the removal watcher; uninstall.sh
                             is marker-driven (see Uninstall)
tools/make-icons.py       icon generator (`uv run --directory tools python make-icons.py`)
tools/omarchy-remove.sh   full teardown from the console (uninstall + plugin remove)
tools/perf-check.sh       samples agent/shim RSS+CPU, or counts OSD spawns
```

The bar-widget is a **second client of the same agent socket** the host shim
talks to, so a download started in the popup renders in the widget live and
vice-versa (the queue is owned by the agent daemon, which outlives every
browser session).

## Install

`omarchy plugin add` runs no plugin scripts, so installation is two steps:

```bash
omarchy plugin add https://github.com/NajmAlzorqah/download-extension.git --enable
# then: click the Najm Downloader widget in the bar (it installs the browser side)
```

The widget's first click runs `install.sh` (streaming its output) and flips to
the queue monitor when done. You can also run it by hand from a checkout:

```bash
./install.sh
```

Requires `yt-dlp` and `ffmpeg` at `/usr/bin` (the host hardcodes those paths;
best-effort `omarchy-pkg-add` is attempted otherwise), plus `python3`,
`sha256sum`, `base64`. What `install.sh` does:

1. Derives the extension id from the **committed SPKI key** in
   `extension/manifest.json` (`sha256(spki)` → first 16 bytes hex-mapped
   `0-f → a-p`). No private key exists — a new key would change the id and
   break `allowed_origins`, so the key is checked in and never regenerated.
2. Registers the `com.najm.ytdlp.json` native host in **all ten**
   Chromium-family profile roots:
   `chromium`, `google-chrome[-beta|-unstable]`,
   `BraveSoftware/Brave-Browser[-Beta|-Nightly|/Brave-Origin]`,
   `microsoft-edge[-dev]`.
3. Adds the extension dir to `--load-extension=` in every `*-flags.conf`
   (omitting browsers without a conf except the core `chromium` + `brave-origin`, for which
   the conf is created). Idempotent, keeps other tools' entries on the line,
   and drops a previously-configured Najm checkout path so the line never
   carries two. A `.najm-bak` backup is taken on first edit.
4. Writes the marker `~/.local/state/najm-downloads/installed.json`
   (the widget's "setup needed" flip), with the active extension dir/id, host
   binary, the configured profiles and yt-dlp/ffmpeg availability.

Then **restart the browser** (fully quit). The extension loads with the other
Omarchy extensions; click the icon in the toolbar.

## Use

1. Open a video or playlist page (or paste a URL) — the popup probes it automatically.
2. Pick the **actual quality this video offers** — one entry per resolution
   (highest first, best codec chosen for you) plus `Audio only`; subtitle
   language tracks the video actually offers; playlist on/off; and, when the
   video has chapters, a `Video sections` selector (embed as chapter markers /
   split into one file per section).
   For a playlist, the resolutions come from the first video (or presets) and
   subtitles default to **all available**.
3. Download; progress shows in the Omarchy OSD overlay and the popup.
   Files go to your output dir (default `~/Videos`, change in Options);
   playlist videos are numbered by playlist order. Reopen the popup at any
   time to add more downloads, or reorder/remove rows in the queue section.

Subtitle notes:

- Enable **Download subtitles** → the language list contains the tracks the
  video offers. By default only **manual** subtitles are eligible: `All available`
  means every manual track. Auto-generated captions are downloaded only when you
  tick **Auto-generated**, and then for the chosen language only (or a single
  default track for `All available`: English when offered, otherwise the first
  available) — never a per-language flood. For playlists the same choice is
  applied to every video, and a language you pick stays picked. If the video
  offers no subtitles at all, the option is disabled with a hint.
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

Under the hood there are **two host processes, not one**: the process the
browser's native-messaging port talks to is a thin **shim** that just forwards
each 4-byte-framed request to a long-lived **agent** daemon over a local unix
socket (`$XDG_RUNTIME_DIR/najm-ytdlp/agent.sock`, JSON-lines) and relays the
agent's replies back. The agent owns the download queue, so it outlives every
shim/browser session — which is what makes the queue shared and persistent. The
Omarchy **`najm.downloads` bar-widget** is a second client of that same socket
(no 4-byte framing — it speaks JSON-lines directly), so a download started in
the popup shows up in the widget live, and vice-versa. The agent is
lazy-spawned by a shim on demand and idle-exits (120s with nothing to do), so
it never accumulates as a background process; job-specific streams
(`start`/`progress`/`file`/`done`/`error`/`cancelled`/`info`) are routed only
to the client that started the job, while `queue` snapshots and coarse
`progress` go to every client.

- `ping` → host/yt-dlp/ffmpeg availability
- `probe` → title, thumbnail, duration, chapter count, **all real format
  streams** (id, size, fps, ext, codecs), manual + auto subtitle language maps;
  for a playlist it also samples the first video so the same options are real,
  plus entry count
- `download` → always accepted: if nothing is running it starts immediately,
  otherwise it joins the queue and the host replies `{ok:true, queueId}`. Each
  job streams `start` / `progress` (pct %speed %eta) / `file` / `done`
  (a chosen `formatId` downloads that exact stream instead of re-deriving;
  `chapters: "embed" | "split"` drives the section features). Every queue
  change broadcasts a `queue` event with the full snapshot — active item first
  (`status: "downloading"`), then waiting items (`status: "queued"`), each
  `{id, url, status, position, selection}` — and done/error/cancel
  auto-advance to the next item
- `cancel` → with a `queueId` removes that waiting item (a `queueId` that is
  no longer waiting is a no-op `not found`); without one it terminates the
  running yt-dlp process and the queue advances
- `reorder` `{queueId, newIndex}` → moves a waiting item (0-based index in the
  waiting subgroup)
- `getQueue` → the same snapshot the `queue` event carries (the service worker
  uses it after a restart to decide whether the host already owns a queue)
- `theme` → read-only snapshot of the live Omarchy theme (theme name, resolved
  font family + radius, raw `colors` and `shell` token dicts), read from the
  same files the Quickshell shell uses
  (`~/.local/state/omarchy/current/theme/` + the machine-level
  `~/.config/omarchy/shell.toml` overlay). The popup/options pages resolve
  these tokens client-side in `extension/theme.js`, so the extension recolors
  when you run `omarchy theme set ...`. `colors.toml`'s `mode` (dark/light)
  drives `--color-scheme`.

  The static Solitude palette lives in **one** place — `theme.css` `:root` —
  as the first-paint/no-JS guard. `theme.js` holds no palette literals: it
  reads its fallback tokens from the computed `:root` styles at apply time
  (`readFallbacks()`), so a live theme only overrides tokens it provides and
  no second palette copy can drift. If the live theme can't be fetched the
  popup header shows `solitude · offline` (reason in
  `data-theme-error`). There is no Chromium API to read the browser's own theme
  (`browser.theme` is Firefox-only), so this host round-trip is the only way to
  get the real palette.

Progress drives the Quickshell OSD exclusively — no notification is sent while
a download runs (the old per-second "Downloading" toast spammed the
notification center via its history log). The OSD is rendered **stacked**
(video name over a progress bar, bottom-center) by the `panel` kind of this
same plugin (`Osd.qml`, IPC target `najm.osd`) — stock Omarchy only draws a bar
*or* a message. Completion/failure toasts use
`omarchy-notification-send` with thumbnail + mpv action; `notify-send` is the
fallback when Omarchy isn't present.

Security mirrors the Omarchy host: only `http(s)` URLs; `--` ends options
(array argv, no shell); output is confined to the configured dir via `realpath`;
all echoed strings are stripped of ANSI/control characters; inputs are
whitelist-validated.

## Troubleshooting

- Extension not in the toolbar after restart → `chrome://extensions` must show
  "Najm Downloader"; re-run `./install.sh` and restart again.
- Popup header reads **`solitude · offline`** → `getTheme` failed (or the SW is
  stale). Full error is in `documentElement.dataset.themeError` / the popup
  console (`[theme] getTheme failed: …`). If it follows `omarchy theme set …`
  for no one, suspect the cached service worker:
  `chrome://extensions` → reload "Najm Downloader", or fully quit the browser
  (a window close can leave background processes keeping the old SW alive).
  Chromium caches MV3 service workers for `--load-extension` extensions, so SW
  changes also need the filename bumped (currently `background-6.js`) before
  reload — same trick as the Omarchy `copy-url` extension.
- Probe shows **`Could not establish connection. Receiving end does not exist.`**
  → the service worker isn't answering (stale cached worker, see above). Reload
  the extension from `chrome://extensions` or fully quit the browser — no
  code change fixes it.
- Host status dot red in the popup → the native host wasn't found. Verify
  `com.najm.ytdlp.json` exists in the browser's `NativeMessagingHosts`, the
  `path` and `allowed_origins` are correct, and you restarted after install.
- `--load-extension` edit backfires → restore the `.najm-bak` backup.
- Headless / custom `--user-data-dir` runs look for host manifests inside the
  profile (`<user-data-dir>/NativeMessagingHosts`), not `~/.config/…`.

## Uninstall

```bash
./uninstall.sh          # browser side + runtime, then remove the plugin below
tools/omarchy-remove.sh # both at once, from the console
```

`uninstall.sh` is marker-driven: it removes exactly what `install.sh` recorded
— the host manifests from the ten Chromium-family profiles, the extension from
`--load-extension=` (preserving other tools' entries; `.najm-bak` stays as a
manual safety net), the yt-dlp agent (whole process group) and its runtime
dirs, the removal watcher, and the marker. The extension id is pinned by the
committed key, so there is nothing to purge — re-install with `./install.sh`.

To remove the Omarchy plugin itself, `omarchy plugin remove najm.downloads
--yes`: since `plugin remove` runs no scripts, the watcher install.sh arms then
catches it — it runs the state-dir `uninstall.sh --if-plugin-gone`, which
cleans the browser side whenever the recorded `installed_from` dir is gone, so
a re-`plugin add` starts fresh (the widget's setup pane reappears). An install
served from your own dev checkout is never touched automatically.

## Contributing

Open to contributions under the MIT License. Fork, branch, and open a pull
request; commit with a `Signed-off-by` trailer (Developer Certificate of
Origin) so contributions are cleanly licensed inbound = outbound. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

- The **Omarchy** desktop shell and its `omarchy.osd` panel (MIT,
  © David Heinemeier Hansson) — the `Osd.qml` panel kind in this repo is a
  derivative of the stock panel; see [NOTICE.md](NOTICE.md).
- **yt-dlp** (Unlicense) does the actual downloading; **ffmpeg** handles
  merging; **Quickshell** (LGPL-3.0) is the QML runtime the panels run on.
- Agent skills vendored under `.agents/skills/` from
  [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (MIT,
  © 2025 Addy Osmani).
- The Omarchy **Download Video** extension + native host, whose companion
  pattern, OSD glyphs and toast style this project matches.

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE).
Third-party notices and license texts for every incorporated or referenced
work are collected in [NOTICE.md](NOTICE.md).

The license covers this project's code only. It downloads third-party media at
the user's request — respect the legal terms and copyright of the platforms and
content you download; those are not conveyed by this license.