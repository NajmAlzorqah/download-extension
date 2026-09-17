# Task List: Download Queue

Task list target for `tasks/plan-download-queue.md`. Drive with
`incremental-implementation`: thin vertical slices, verify each, commit once
at the very end (user override — **no commits until the user says so**).

- [x] Task 1: Host enqueue + queue snapshot + auto-advance (`active_job` +
      `queue[]`, sanitized selection echo, `finish_job()` → `start_next()`)
- [x] Task 2: Host `cancel{queueId}` / `reorder` / `getQueue` +
      cancel-before-spawn race fix
- [x] Task 2b: whitelisted display `label` in `sanitize_selection()`

### Checkpoint A (host contract)
- [x] `queue` frame = full list (active + waiting) with sanitized selection
- [x] `ping`/`probe`/`theme`/active-item progress frames unchanged
- [x] Hand-fed: download×3 → queued; cancel active → next auto-starts
- [x] Hand-fed: `cancel{queueId}` removes a waiting item; `reorder` moves it
- [x] Hand-fed: hostile selection stripped (ANSI/CTRL/junk/hostile label)

- [x] Task 3: `background-2.js` → `background-3.js` rename (+
      `manifest.json.in`, `./install.sh`), `state.queue`, `queue` event,
      forward `cancel{queueId}` + `reorder`
- [x] Task 4: Persistence — throttle-write `state.queue` to
      `chrome.storage.local`; restore on `onStartup`/`onInstalled` via
      `getQueue` authority check (no duplicates)

### Checkpoint B (SW round-trip)
- [ ] `queue` events populate `state.queue` live
- [ ] Simulated restart: idle host + stored queue → jobs re-submitted once
- [ ] Extension reload mid-queue → host wins, no duplicates

- [x] Task 5: Popup queue UI (`popup.html`/`popup.css`/`popup.js`) — section +
      rows (title, options summary, position, ↑/↓, Remove), `renderQueue()`,
      `summarizeSelection()`, reopen-early-return removal, `#opts` unhide fix,
      whitelisted `label` in `buildSelection()`

### Checkpoint C (popup end-to-end)
- [ ] 3 downloads → 1 downloading + 2 rows with title/options
- [ ] Remove row; reorder rows; cancel active → next auto-starts
- [ ] Reopen mid-queue from another page → queue shown, can probe + add

- [x] Task 6: Docs — AGENTS.md (filename bump + queue/persistence contract),
      README message protocol if it lists actions
- [x] Task 7: code-review-and-quality + code-simplification pass
  (review done; findings fixed: lock_probe cancel race, notify-before-promote
  ordering, dropdown label desync, probe/URL binding, probe-message leak,
  speed/eta formatting, RE_CTRL hardening, README backup wording)

### Checkpoint D (Definition of Done)
- [ ] `python3 -m py_compile host/najm-ytdlp-host` clean
- [ ] Host hand-fed queue/cancel/reorder/getQueue frames verified
- [ ] Queue + restart-persistence work at runtime; SW filename bumped
- [ ] Review pass done; docs updated
- [ ] Task 8: ONE commit, only after explicit user approval