# Task List: Omarchy bar-widget + shared host daemon

Task list target for `tasks/plan-omarchy-widget.md`. Drive with
`incremental-implementation`: thin vertical slices, verify each, **no commits
until the user says so** (user override of the skill default).

### Slice 1 — Host agent skeleton
- [x] `--agent` mode: unix-socket server + JSON-lines framing + single
      instance (flock/pid) + `ping` over the socket
- [x] Hand-fed via a stdlib socket client: `ping` round-trip

### Slice 2 — Host agent routing + lifecycle
- [x] Multi-client request loop (per-originator `req`, serialized like today)
- [x] Per-originator job streams; broadcast `queue`
- [x] Coarse `progress` broadcast (`{event:"progress", queueId, pct, speed,
      eta, downloaded, total}`, req-less → all clients)
- [x] Idle-exit timer (queue empty + no clients); client disconnect never
      kills the queue
- [x] Hand-fed: download → queue broadcast; second client sees it

### Slice 3 — Native shim mode
- [x] Default (no `--agent`) = shim: 4-byte stdin/stdout ⇄ socket, lazy-spawn
      agent on missing socket, retry connect
- [x] AGENTS.md `printf` ping trick against the shim works
- [x] Full action matrix through the shim (ping/probe/download/cancel/
      reorder/getQueue/theme)

### Slice 4 — Extension compatibility
- [x] Foreign-progress handling in the SW (`adoptQueue()` shared by
      `queue`/`getQueue`/restore; `activeId` tracking; foreign-job terminal
      fallback to idle since routed done/error/cancelled only reach the owner)
- [x] SW renamed `background-3.js` → `background-4.js`; `manifest.json.in`
      updated; `./install.sh` re-run (id unchanged); AGENTS.md/README
      filename refs bumped
- [ ] Browser smoke test: popup/options unchanged work through the shim;
      widget-started job renders in the popup (needs manual browser testing)

### Slice 5 — Widget scaffold
- [x] `~/.config/omarchy/plugins/najm.downloads/{manifest.json,Panel.qml,
      Client.js}` — themed `BarIconButton`, connect, ping, host-status state,
      IPC target
- [x] `omarchy plugin validate` passes; widget enabled; icon shows online/
      offline

### Slice 6 — Widget probe + options
- [x] URL + Detect → probe; meta header; format dropdown (presets+formats)
- [x] Playlist / subs / chapters / output-dir controls mirroring the popup
- [x] `Formats.js` ported from popup.js; defaults mirror `defaults.js`
- [x] Prefs persisted to `~/.local/state/najm-downloads/widget-prefs.json`
      (`mkdir -p` guard, FileView whitelist-reload); pending: probe a real
      video end-to-end once a reachable URL is available (pipe + reply FSM
      unit-tested; failure reply + IPC verified live)

### Slice 7 — Widget download + progress + queue
- [x] Download → shared queue; live progress view; Cancel (`download()` + req-routed
      `start`/`done`/`error`/`cancelled`/`info` handling; coarse `progress` broadcast;
      `sourceUrl` stamp → URL-changed re-detect guard; `getQueue` bootstrap on connect)
- [x] Queue list (active + waiting, move ↑/↓, remove) mirroring `renderQueue`
      (`activeItem`/`waitingItems` derived, reorder/cancel-with-queueId, terminal msg row)
- [x] Widget-started job visible in the popup and vice-versa (`queue`/`progress`
      broadcasts render both sides; pending: live end-to-end once a reachable URL
      is available — qmllint/plugin-validate clean, no runtime errors, FSM green,
      sha traffic reachable cross-widget verified by construction)

### Slice 8 — Docs
- [x] AGENTS.md: daemon/socket/shim contract, routing, `background-4.js`,
      plugin dir, defaults-drift warning
- [x] README protocol notes if it lists actions

### Slice 9 — Review + Done
- [x] code-review-and-quality / code-simplification pass
  (fixed: dead duplicate `formatLabel` in Formats.js; widget `onDownloadReply`
  disarmed `pendingDownloadReq` too early, dropping req-routed terminal
  `done`/`error`/`cancelled` for own jobs — now disarmed only at stream end)
- [x] Definition of Done: py_compile clean, hand-fed matrix green, widget +
      popup end-to-end, docs updated
  (live end-to-end still needs a reachable URL — every other gate verified)

### Slice 10 — User adjustments (2026-09-19)
- [x] Diagnose "cancel didn't cancel": host protocol proven correct live
      (waiting-item `cancel{queueId}` pops and broadcasts); the real gap was
      UX — the widget's only active Cancel lived in the probe/options section,
      unreachable once the URL field is gone. No host-protocol fix needed.
- [x] Host `pause` action (request+reply, SIGSTOP/SIGCONT, `"paused"` status in
      queue snapshot, cancel-while-paused SIGCONT-first, finish_job flag scrub)
      — delegated to a sub-agent, then reviewed: idempotent-gated, correct.
- [x] Extension: `background-4.js` routes `pause`, `adoptQueue` treats a
      `"paused"` head as active (frozen progress, no resetTo on pause↔resume),
      snapshot carries `paused`; `popup.html` adds a Pause button; `popup.js`
      toggles Pause/Resume label + "Paused" hint, hides it on done/error/cancel
      — delegated to a sub-agent, then reviewed (node --check clean).
- [x] Widget: removed URL TextField + Detect button + probe/options/download
      UI entirely (`Panel.qml` 1197 → 709 lines); progress section now has a
      Cancel button (always reachable) + Pause/Resume button; `activeItem`
      matches `"paused"`; `Client.js` gained `pause(req, paused)` and
      `queueBusy` knows `"paused"` — delegated to a sub-agent, then reviewed
      (qmllint / plugin validate / node --check clean; pause ack verified to
      fall through handleLine without misrouting).
- [ ] Browser smoke test: reload the unpacked extension (pause button in the
      popup while downloading), queue-cancel + reorder from both popup and
      widget, pause/resume/cancel the active job from both surfaces (needs
      manual browser testing)
- [x] Review pass (code-review-and-quality): fixed two real bugs + host minors
  (widget Pause now wrapped in `sendFrame`; run_one re-asserts SIGSTOP for a
  pause that landed during the subtitle lock probe / spawn gap; cancel-queueId
  scrubs the job's REQ_OWNERS entry; `agent_connect` dead `spawned` branch
  removed; send() fallback-broadcast docs corrected; idle-exit/all-clients
  note). Widget dead-code removed per review: Panel.qml job-stream machine
  (pendingDownloadReq/ownQueueId/onDownloadReply/onDownloadError/onJobStream)
  + Client.js download/isDownloadReply/isJobStream/probe/isProbeReply/
  widgetPrefsPath; Formats.js + test kept as documented popup.js mirror;
  Defaults.js kept for the node harness. AGENTS.md + plan reconciled with the
  monitor-only widget.
- [ ] ONE commit, only after explicit user approval