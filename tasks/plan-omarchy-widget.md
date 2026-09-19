# Plan: Omarchy bar-widget backed by a shared host daemon

Status: in progress · Drives `tasks/todo-omarchy-widget.md`.

## Goal

An Omarchy bar-widget plugin (`najm.downloads`) that mirrors the yt-dlp
extension popup — same options, same actions, same queue — and is genuinely
*connected* to the browser extension via one shared host daemon. Both UIs see
and drive the same download queue.

## Architecture (decisions locked with the user)

Today the yt-dlp queue lives **inside the host process** that the browser
spawns per native-messaging connection. A widget spawning its own host would
get a private queue and silently disagree with the extension. So the host is
split:

```
popup/options (extension)              browser
        │  chrome.runtime.connectNative
        ▼
com.najm.ytdlp native shim ──(4-byte LE frames on stdin/stdout)──┐
  (spawned per connection, forwards, exits on EOF)               │
                                                                 ▼
                najm-ytdlp-host --agent    (unix socket, JSON-lines)
                owns: queue · yt-dlp jobs · probe cache · theme · OSD
                                                                 ▲
najm.downloads widget (Omarchy shell) ── Quickshell.Io.Socket ───┘
```

- Browser shim: same binary, default mode. Reads 4-byte LE frames on stdin,
  forwards them to the agent socket (JSON-lines), re-frames agent → stdout.
  `lifecycle: single-shot` still holds.
- Agent: `--agent` mode. Unix-socket server on
  `$XDG_RUNTIME_DIR/najm-ytdlp/agent.sock` (0700 dir / 0600 socket; fallback
  `~/.local/state/najm-ytdlp/`). Reuses every core function unchanged
  (`sanitize_selection`, `build_command`, probe cache, subtitle lock,
  `read_theme`, OSD/notifications). Survives client disconnects; idle-exits
  (queue empty + no clients for N min). Lazy-started by shim/widget when the
  socket is missing.
- Widget: `Quickshell.Io.Socket` client, JSON-lines framing (avoids
  binary-frame/UTF-8 murk in QML `Socket.write(QString)`).

### Message routing on the agent (the risky part — keep in one place)

- Requests are handled by the same serialized loop as today.
- Per-job streams (`start`/`progress`/`file`/`done`/`error`/`cancelled`/`info`)
  go to the **originating** client, keyed by its own `req` — popup semantics
  unchanged.
- `queue` events and a coarse `progress {queueId, pct, speed, eta}` are
  **broadcast** to every client, so either UI can render a job the other
  started.
- `probe` replies are originator-only (large payloads); the daemon's shared
  probe cache means popup and widget reuse each other's probes.

## Slices (drive with incremental-implementation)

1. Host: agent mode skeleton + socket server + JSON-lines framing + ping →
   hand-fed via netcat-style client.
2. Host: request loop over clients; per-originator job streams; broadcast
   `queue` + coarse `progress`; idle-exit; single-instance.
3. Host: native shim mode (4-byte stdin/stdout ⇄ socket, lazy-spawn agent).
   Extension popup works unchanged against the shim.
4. Extension: foreign-progress handling in the SW + SW filename bump to
   `background-4.js` (`manifest.json.in`, re-run `install.sh`).
5. Widget scaffold: `~/.config/omarchy/plugins/najm.downloads/` —
   `manifest.json`, themed `Panel.qml` with `BarIconButton`, `Client.js`
   (connect/ping/status), IPC target. Validate + enable.
6. Widget probe + options UI (format presets, subs, chapters, playlist,
   output dir) — port `Formats.js` helpers from `popup.js`.
7. Widget download + progress + queue management (cancel/reorder/remove),
   popup mirror of the extension progress view.
8. Docs: AGENTS.md (daemon/socket/shim contract, `background-4.js`, plugin
   dir, defaults-drift warning), README if it lists the protocol.
9. Review pass (code-review-and-quality / code-simplification), Definition of
   Done, then ONE commit only on explicit user approval.

## Security invariants (must not weaken)

Same rules as today, extended to the socket: array argv / `--` end-of-options,
output confinement via `realpath`, ANSI/control stripping, whitelist-validated
inputs (`RE_FMTID`, `RE_LANG`, `RE_INT`, `RE_SUB_ERROR`, `RE_LABEL`, …).
The socket is local, user-owned, 0600; the agent re-validates every request
exactly as the stdio host does today — the socket is not a trust boundary, only
a transport.

## Testing

- Host: `python3 -m py_compile host/najm-ytdlp-host`.
- Agent hand-fed: a tiny stdlib netcat-style socket client for
  ping/probe/download/cancel/reorder/getQueue/theme + hostile selection.
- Shim: AGENTS.md's `printf` trick against the shim on a pty.
- Widget: `omarchy plugin validate`, enable, hot-reload loop; `omarchy restart
  shell` after keepLoaded changes.
- End-to-end: popup download while widget shows queue; widget download while
  popup shows it.

## Open notes / deferred

- **Slices 6–7 (widget probe + download UI) were removed by user adjustment
  (2026-09-19):** the widget no longer probes or starts downloads — the
  extension popup owns URL probing and download initiation. The widget is now a
  pure shared-queue monitor (progress, cancel/pause/resume the active job,
  reorder/remove waiters) and the plan's Slice 6/7 *roles* are historical, not
  current. `Formats.js` survives as a popup.js mirror used by the node unit
  harness and queue-row labels; the dead `download()`/job-stream helpers were
  deleted from `Client.js`/`Panel.qml`.
- No yt-dlp resume wiring (unchanged).
- No systemd units — lazy-spawn + idle-exit.
- Widget defaults mirror `extension/defaults.js`; a plugin cannot read
  `chrome.storage` — that single surface is the known drift risk (comment in
  the file).
- The popup's session-scoped "last probe" cache stays extension-local; the
  widget has no probe of its own (it renders whatever the popup queued).