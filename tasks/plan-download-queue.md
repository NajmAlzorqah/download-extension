# Implementation Plan: Download Queue (ytdlp-extension)

## Overview

Replace the current "one active download, second request rejected
(`A download is already running`)" behavior with an unlimited serialized
download queue: every `Download` request is accepted and enqueued, one video
downloads at a time, and when the active item finishes (done **or error** or
cancel) the next waiting item starts automatically. The popup gains a queue
list — title + chosen options per item, with per-item cancel and reordering
of not-yet-started entries. The queue survives a browser restart by having the
service worker mirror it into `chrome.storage.local` and re-submit jobs to the
(restarted) native host on wake.

Confirmed with the user:

- Failures auto-advance the queue (one bad video never blocks the rest).
- Cancelling the active item also auto-starts the next.
- Queue persists across full browser restarts (`chrome.storage.local`).
- **No commits until the user says so** (override of the
  incremental-implementation commit step).

## Architecture Decisions

- **Queue lives in the host.** The native host is the authority for running
  downloads and already survives popup/SW death ("the host survives a dead
  tab/sw"). A SW-side queue would vanish if the MV3 worker suspends; a
  host-side queue lasts the whole browser session. Downloads remain strictly
  serialized (one `active_job`, a FIFO of waiting jobs).
- **New `queue` snapshot event.** Host emits the full queue on every mutation:
  active item first (status `downloading`), then waiting items (status
  `queued`), each `{id, url, status, pct, position, selection}`. The existing
  `start`/`progress`/`file`/`done`/`error`/`cancelled` event stream for the
  active item is unchanged, so the tested popup progress view keeps working.
- **Selection echoed back is host-sanitized.** The `selection` copy carried in
  the snapshot is whitelisted field-by-field with the exact same rules
  `build_command()` uses (`RE_FMTID`, `MERGE_CONTAINERS`, audioFmt enum,
  chapters enum, `RE_LANG`/`"all"` langs, bool conversions, `clean()` title),
  preserving the host's echo-paranoid invariants while still being sufficient
  to re-run the download after a restart (needed for persistence).
- **Cancel/reorder target queue items by `queueId`** (host-assigned int). A
  `cancel` on a waiting item just removes it (nothing to tear down); a `cancel`
  without/with an active `queueId` keeps today's terminate behavior and then
  advances the queue.
- **Persistence = SW mirror + re-submit.** Service worker throttles writes of
  the queue to `chrome.storage.local` (~1/s) on every snapshot. On wake
  (`chrome.runtime.onStartup` + `onInstalled`) it asks the host (`getQueue`):
  if the host already owns a queue (it outlived an extension reload) the host
  wins and storage is overwritten from its snapshot — otherwise, if storage has
  a saved queue, the saved jobs are re-submitted in order (former-active first)
  to the fresh host. `storage.local`, not `session` (cleared on restart).
- **SW filename bump to `background-3.js`** (AGENTS.md gotcha: any SW logic
  change must version the service-worker file; otherwise Chromium serves a
  stale worker and the popup shows `offline`).
- **UI:** kept additive. The existing big progress view stays the active
  item's display; the new queue list shows waiting items (position, title,
  options summary, ↑/↓, Remove). The popup's reopen-early-return is removed so
  the queue renders and the user can still probe/add from any page while a
  download runs (also fixes the latent hidden-progress bug: `#progress` sits
  inside the `#opts` section that stays hidden on the downloading reopen path).

## Task List

### Phase 1: Host queue core (risk-first)

- Task 1: Host enqueue + snapshot + auto-advance. Replace `busy` with
  `active_job` + `queue[]` under `STATE_LOCK`;
  `download` builds a job `{id, req, url, selection}` (id = incremented int),
  replies `{ok:true, queueId}`, starts it immediately if idle or appends to
  `queue`; emit a `queue` snapshot on every change. Worker terminal paths
  (done/error/cancelled) become `finish_job()` → `start_next()` (clears
  active, promotes `queue[0]`, spawns worker). Sanitized-selection echo helper
  shared by snapshot + `build_command`.
- Task 2: Host cancel/reorder/getQueue + cancel-before-spawn race fix.
  `cancel` accepts optional `queueId` (waiting → remove + snapshot);
  new `reorder` (`{queueId, newIndex}` ints validated+clamped on waiting
  subgroup); new `getQueue` action returning the same snapshot; add
  `_cancel_pending()` guards before every `run_one` and right after
  `cancel_flag = False` so a cancel landing mid-transition exits cleanly
  instead of starting a full download that only "notices" at the end.

### Checkpoint A: Host contract
- New `queue` frame returns the full list (active+watching) with sanitized selection.
- `ping`/`probe`/`theme`/active-item progress frames unchanged.
- Hand-fed `download`×2 → second is queued, first ends → second auto-starts; `cancel{queueId}` / `reorder` mutate the list as expected.

### Phase 2: Service worker

- Task 3: Rename `background-2.js` → `background-3.js` (bump in
  `manifest.json.in`, then `./install.sh`). `state.queue = []`;
  handle the `queue` event; forward `reorder` and `cancel` (optional
  `queueId`); `getState` returns `state.queue`.
- Task 4: Persistence. Throttled (`~1/s`) writes of `state.queue` to
  `chrome.storage.local` on every snapshot/terminal event (clear when empty).
  On `onStartup`/`onInstalled`: `getQueue` → if host has items, adopt them;
  else if storage has a saved queue, re-submit each as
  `{action:"download", url, selection}` in order (former active first), then
  clear storage. Guard against duplicate submission.

### Checkpoint B: SW round-trip
- `queue` events populate `state.queue` live.
- Simulated restart: host idle + stored queue → jobs re-submitted once, popup
  `getState` shows the restored queue.
- Extension reload mid-queue: host is authority, no duplicates.

### Phase 3: Popup queue UI

- Task 5: Queue section in popup. `popup.html` new top-level
  `<section id="queueSection">` (sibling of Video, visible during downloads)
  with `<ul id="queueList">`; `popup.js` `renderQueue()` on every hostEvent,
  `summarizeSelection()` (e.g. `1080p · mp4 · subs embed`, `Playlist ·
  split chapters`, `MP3 audio`), Move ↑/↓ (`reorder`) and Remove (`cancel`)
  handlers; remove the reopen early-return so probing/adding stays possible
  during a download and `#opts` is unhidden on the downloading reopen path;
  `popup.css` row/caret/button styles matching the design system. Active item
  continues to use the existing progress view.

### Checkpoint C: Popup end-to-end
- Probe + download 3 links → 1 downloading + 2 listed rows with title/options.
- Remove a queued row; reorder rows; cancel active → next auto-starts.
- Reopen popup mid-queue from another page → queue shown, can probe+add.

### Phase 4: Docs, review, finish

- Task 6: `AGENTS.md` — bump `background-3.js` filename, add Download-queue
  section (queue event, `cancel.queueId`, `reorder`, `getQueue`, sanitized
  echo, advance-on-failure, storage.local persistence/restore contract);
  README if it documents the message protocol.
- Task 7: `code-review-and-quality` + `code-simplification` pass on all
  touched files.
- Task 8: Manual end-to-end pass on a real page, then ONE commit (descriptive
  message) — **only after explicit user approval**.

### Checkpoint D: Definition of Done
- Host py_compile clean; host hand-fed frames for queue/cancel/reorder/
  getQueue verified; SW filename bumped; queue + persist/restore work at
  runtime; docs updated; review pass done; commit only on user's go.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cancel lands mid auto-advance; worker ignores flag and downloads whole job | High | `_cancel_pending()` guards before each `run_one` + after flag reset (Task 2) |
| Restore duplicates queue on extension reload | Med | `getQueue` authority check: host-owned queue wins, storage only re-submits when host is idle |
| `queue`/`start` event ordering races | Low | Cosmetic; `SEND_LOCK` serializes framing; popup renders from snapshot + active events |
| Unsanitized selection echoed back breaks host invariants | Med | Echo uses the exact `build_command()` whitelists; never raw `sel` values |
| Stale SW served after logic change | Med | Versioned filename bump to `background-3.js` + `./install.sh` |
| Queue lost mid-browser-quit (host dies) | Low | Persistence task mirrors to `chrome.storage.local`; active item restarts from scratch (no yt-dlp resume wiring — documented) |
| Probe blocks host main loop while queue downloads (pre-existing) | Low | Out of scope; unchanged single-threaded main loop |

## Open Questions

- Show the active item inside the queue list too, or keep it in the existing
  progress view only? (Default: keep the progress view; list = waiting only.)
- Should `options` page get a queue view? (Default: no, popup only.)
- Partial file from a killed active item: reuse for resume, or always restart?
  (Default: restart, matching today.)