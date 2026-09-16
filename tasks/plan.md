# Implementation Plan: Omarchy Design System Restyle (ytdlp-extension)

## Overview

Restyle the popup and options pages to the Omarchy design language with
**dynamic theme-following**: the native host reads the live Omarchy theme
(the shell's own source of truth) so the extension recolors when the user
runs `omarchy theme set ...`. No behavior change to the probe / download /
subtitle / playlist logic.

Decisions confirmed with the user:

- Dynamic theme-following via the host (not a static palette).
- Popup + options only; toolbar icons (`extension/icons/*.png`) stay untouched.
- Full-width Download button = "accent take" (selected state + accent label).
- Custom Omarchy dropdowns for Format / Language / Subtitle format.

## Architecture Decisions

- **Theme source of truth** mirrors what the Quickshell shell reads:
  - `~/.local/state/omarchy/current/theme/colors.toml`
  - `~/.local/state/omarchy/current/theme/shell.toml`
  - plus the machine-level user override `~/.config/omarchy/shell.toml`
    (user wins, same layering as `Color.mergeShell`), and `theme.name`.
- **Host stays dumb**: a new read-only `theme` action returns raw parsed
  token dicts (`colors` + `shell` + `name` + resolved `radius`/`fontFamily`).
  All resolution policy lives client-side in a new shared `extension/theme.js`,
  mirroring the shell's `Color`/`Style` semantics (surface roles, control
  state tokens, and resolving `hyprland.active-border` gradients into a CSS
  `linear-gradient`).
- **Native controls stay the source of truth**: `<select>` and
  `<input type="checkbox">` elements keep their ids and wiring; a new
  `extension/controls.js` decorates them visually (custom dropdown + pill
  toggle switch) using MutationObservers, so `popup.js` render/save logic is
  untouched.
- **Fail-soft theming**: `theme.js` ships a bundled Solitude token set used
  whenever the host/theme is unavailable, so the UI never paints broken.
- **Type**: `fc-match`-resolved family (JetBrainsMono Nerd Font today) with a
  `ui-monospace`/`monospace` fallback stack.
- **Radius**: `hyprctl -j getoption decoration:rounding` (= 6), fail-soft to 6.
- **No per-slice commits** (user override of the incremental-implementation
  skill's commit step): one commit at the very end.

## Task List

### Phase 0: Skill tooling

- Task 0: Vendor `planning-and-task-breakdown` + `incremental-implementation`
  into `.agents/skills/` and pin both in `skills-lock.json`.
- Task 1: Write this file + `tasks/todo.md`.

### Checkpoint 0: Skills resolvable; plan files in place.

### Phase 1: Host contract (risk-first)

- Task 2: `theme` action in the host — TOML-lite reader (semantics mirroring
  the shell's `parseShell`), whitelist-regexed output, `hyprctl` + `fc-match`
  extras (array argv, fail-soft), response
  `{req, ok, theme:{name, radius, fontFamily, colors, shell}}`.
  Verify: `python3 -m py_compile` + hand-fed frames over stdio.

### Checkpoint A: `theme` frame returns valid JSON; ping/probe/cancel untouched.

### Phase 2: Extension theming core

- Task 3: `background.js` `getTheme` message (reuse the `pendings` /
  `connectNative` pattern, ~5s cache, timeout fallback).
- Task 4: `theme.js` — host payload -> CSS-variable resolver (palette, popups
  surface, control states, gradients, typography, radius) + Solitude fallback.
  Verify: clean console on popup open; vars present on `:root`.

### Checkpoint B: `getTheme` round-trip; `theme.js` applies vars without errors.

### Phase 3: Controls + UI (the visual core)

- Task 5: `controls.js` — `decorateSwitch` (pill toggle over hidden native
  checkbox) + `decorateSelect` (floating card list, 28px rows, optgroups as
  caption headers, caret, keyboard/Escape/outside close) applied to
  `subsOn`/`autoSubs`/`convertSrt`/`embed`/`playlist` and
  `formatSelect`/`langs`/`subFormat`, working against the current markup.
- Task 6: `theme.css` design system + `popup.html` restructure + `popup.css`
  rewrite: floating card on a darker canvas, bar-style header (download glyph +
  brand in `bar.text`, host status pill, theme-name caption), section headers +
  rules, switches, custom dropdowns, accent-take Download + Cancel, OSD-style
  progress (pill bar + bold right-aligned readout), themed warn/err blocks,
  hover-fill footer link. **All element ids preserved.**
- Task 7: options restyle (`theme.css` + switches + mono status line).
  Verify: save/reset + host status work.

### Checkpoint C-D: popup + options fully redesigned; probe/download/cancel/
subs/playlist logic byte-identical and working.

### Phase 4: Dynamics, hardening, docs

- Task 8: theme-switch recolors on reopen; host-offline fallback; error/warn
  states; font/radius correctness.
- Task 9: README "How it talks to yt-dlp" (add `theme` action); AGENTS.md host
  section (new read-only `theme` action, security invariants preserved).

### Checkpoint E: End-to-end manual pass on a real page.

### Phase 5: Finish

- Task 10: `code-review-and-quality` + `code-simplification` pass on all
  touched files.
- Task 11: ONE commit (single descriptive message) including `tasks/`,
  the two vendored skills, and all code.

### Checkpoint F: Definition of Done — no regressions, UI verified at runtime,
docs updated, working tree clean.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Host parser drifts from shell parser semantics | Med | Mirror `parseShell` line regexes exactly; verify payload against known Solitude values + this machine's `~/.config/omarchy/shell.toml` override |
| Decoration breaks popup.js render/save logic | High | Native inputs/selects stay the source of truth; observers only mirror visuals; manual probe→download→cancel + subs/playlist test each slice |
| Host down / headless -> extension unstyled | Med | Bundled Solitude fallback token set in `theme.js` |
| Nerd Font missing in Chromium | Low | `font-family` fallback stack (`ui-monospace`, `monospace`) |
| `hyprctl`/`fc-match` latency on popup open | Low | ~30ms; cached in background with short TTL |
| Skills lock format mismatch | Low | Reuse `npx skills add` (the same CLI that wrote the existing lock) |
| `current/theme` path gone (no Hyprland/session) | Low | Host returns `ok:false`, extension uses fallback |

## Open Questions

- Include `tasks/` and the two skill dirs in the final commit? (Default: yes.)
- Plan/todo live in `tasks/` per the planning skill default; the repo had no
  such dir, so this creates it.