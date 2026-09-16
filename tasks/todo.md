# Task List: Omarchy Design System Restyle

Task list target for `tasks/plan.md`. Drive the work with
`incremental-implementation`: thin vertical slices, verify each, commit once
at the very end (user override).

- [x] Task 0: Vendor planning-and-task-breakdown + incremental-implementation skills
- [x] Task 1: Write tasks/plan.md + tasks/todo.md

### Checkpoint 0
- [x] `planning-and-task-breakdown` / `incremental-implementation` resolvable as skills
- [x] tasks/plan.md and tasks/todo.md in place

- [x] Task 2: Host `theme` action (TOML-lite reader, hyprctl/fc-match extras, whitelisted output)

### Checkpoint A
- [x] Hand-fed `theme` frame returns valid JSON with expected Solitude tokens
- [x] ping/probe/cancel responses unchanged

- [x] Task 3: background.js `getTheme` message + short cache
- [x] Task 4: extension/theme.js resolver + Solitude fallback

### Checkpoint B
- [x] getTheme round-trip via background
- [x] theme.js applies CSS vars without console errors (Node harness: 39/39 tokens, live + fallback)

- [x] Task 5: extension/controls.js switches + custom dropdowns (current markup)
- [x] Task 6: theme.css design system + popup restructure (ids preserved)

### Checkpoint C
- [x] Popup fully redesigned to Omarchy card idiom
- [x] probe → download → cancel → subs → playlist logic unchanged
      (popup.js / options.js untouched; host ping/probe/unknown frames re-verified)

- [x] Task 7: options restyle

### Checkpoint D
- [x] Options matches design; save/reset + host status keep their ids/flow

- [x] Task 8: Dynamics/hardening: theme switch recolors (4s cache), host-offline fallback, font/radius
- [x] Task 9: Docs: README + AGENTS.md host section

### Checkpoint E
- [ ] End-to-end manual pass on a real page — reload `chrome://extensions`,
      restart browser so the native host respawns, probe/download/cancel live

- [x] Task 10: code-review-and-quality + code-simplification pass
      (dead vars/classes removed; host whitelist review; unknown-action fallthrough kept)

- [ ] Task 11: Final single commit

### Checkpoint F (Definition of Done)
- [ ] No regressions; runtime-verified; docs updated; working tree clean