# Security audit — Najm Downloader (ytdlp-extension + Omarchy plugins)

Date: 2026-09-21 · Scope: `extension/`, `host/najm-ytdlp-host`, `install.sh`/`uninstall.sh`, host manifest templates, `tools/`, Omarchy widget `najm.downloads` + OSD `najm.osd`.
Baseline: AGENTS.md security invariants. Guided by the `netresearch/security-audit-skill` (installed ad hoc at `~/.agents/skills/security-audit/`; its scanners are directory-convention sensitive and had to be pointed at copies under `/tmp/opencode/audit/`).

## Verdict

No exploitable vulnerabilities found. The host is the attack surface that matters, and it is defense-in-depth heavy: no code evaluation, array-argv-only subprocess with no shell, `--` terminators, whitelist-validated inputs at every boundary (stdio frames, agent socket, theme files), realpath-confined output, and sanitized echo snapshots that circle back through the same whitelists on replay. The extension and Qt plugins add no injection primitives. Findings below are hardening/robustness only, all same-user or Lan-to-Utterly-Ground severity.

## Verified hardening (holding)

- Host: no `eval`/`exec`/`pickle`/`yaml`/`marshal`; every `subprocess.run/Popen` uses array argv, never `shell=True`.
- `--` ends yt-dlp options before every user-supplied URL (probe + download); URL gated by `http_url()` (http/https, netloc required, ≤32 KB).
- Format/language/selection fields validated by `RE_FMTID`/`RE_LANG`/`RE_INT`/`RE_LABEL`/`RE_TOML_SAFE`; `sanitize_selection()` mirrors `build_command()`'s whitelists, so persisted/replayed snapshots can't smuggle anything.
- Output confinement: `--paths` dir is `expanduser`'d, `resolve_file()` requires `realpath(candidate)` to start with `realpath(out_dir)`. Path traversal out of the output dir is not possible regardless of what yt-dlp reports.
- Echoed strings pass `clean()` (ANSI + control chars stripped, length-capped); `--progress-template`/`--print` data is decomposed by `\t`/parse, not concatenated.
- Agent socket 0600 in a 0700 dir, flock single-instance with stale-socket cleanup; frames capped at `MAX_FRAME` (1 MiB); per-client `req` routing (`REQ_OWNERS`) so streams go only to their owner.
- Theme pipeline is read-only and regex-gated end to end; nothing from theme files ever reaches yt-dlp or a shell; `hyprctl`/`fc-match` run with array argv + 3 s timeouts.
- Extension: MV3 with minimal permissions (`nativeMessaging`, `activeTab`, `storage`, `tabs`), no `web_accessible_resources`, no `externally_connectable`, no content scripts, no host permissions. Default CSP (`script-src 'self'`), all scripts external. All `innerHTML` sites safe: three are `sel.innerHTML = ""` clears, `controls.js:21` is a static string, `popup.js:482` interpolates only `escapeHtml()`-wrapped title/tags.
- Install: `umask 077` + `genpkey` RSA-2048 → key 0600; extension id derived from the pubkey; `allowed_origins` pinned; `uninstall.sh` strips `--load-extension=` flags. Key gitignored, untracked, absent from all 15 commits; no API keys/credentials in the tree.
- Widget + OSD: single exec is `Quickshell.execDetached([hostBinary, "--agent"])` (array argv, no shell); all text renders as `Text.PlainText`; `Client.js` frame builders and classifiers match the host contract; OSD payloads are `String()`-coerced and clamped.
- Exception resilience: `download_worker` try/finally wrapper, idempotent `finish_job()` (active slot never stays wedged from a dead client or worker exception), probe threads isolated from the dispatch loop.

## Findings (by severity)

### Low — defense in depth / hardening

**[L1] `background-6.js` `onMessage` does not check `sender.id`** (`extension/background-6.js`). MV3 `runtime.onMessage` only fires for the same extension unless `externally_connectable` is set (it isn't), so this is unreachable today — pure defensive hygiene: add `if (sender.id !== chrome.runtime.id) return;` so the invariant survives future wiring changes.

**[L2] Widget trusts the NativeMessagingHosts manifest `path` field verbatim** (`Panel.qml` `hostManifest.onLoaded` → `hostBinary` → `execDetached`). The file is user-writable only (same-user namespace: whoever can write it can already exec as the user), so it's not a boundary crossing; but the widget turns a stale/third-party `com.najm.ytdlp.json` (e.g. left over from an uninstalled copy, a distro package, or a different checkout with a different `$HOST`) into an always-spawned binary on every shell start. Recommend resolving `hostBinary` to a realpath and warning when it isn't `host/najm-ytdlp-host` under the expected repo, or reading the path from the same source `install.sh` writes.

**[L3] `omarchy_tool()` prefers `PATH` over the repo's fixed binary dir.** A `PATH` entry shadowing `omarchy-shell`/`notify-send`/`mpv`/`xdg-open`/`hyprctl` is honored. Same-user namespace again (the browser passes the user's own env to the shim), but this is a place where an accidental PATH corruption turns into silently running the wrong tool. `yt-dlp`/`ffmpeg` are correctly hardcoded absolute; consider hardcoding the Omarchy tools the same way or at least preferring the absolute candidate.

### Informational — robustness notes

- **`client_reader` accumulates `buf` between newlines without a cap** (`host/najm-ytdlp-host`). A peer streaming one giant line (no `\n`) grows memory without bound; oversized *lines* are dropped only after the newline arrives. Cap the inter-newline buffer (e.g. 2×`MAX_FRAME`) and drop/reset on overflow. Same-user peer only.
- **Download requests can grow `wait_queue` without bound.** A same-user client can enqueue unlimited `download` frames; each already-reserved job id has no cap. Add a max (e.g. 100) with `ok:false, error:"queue full"`.
- **`job["_tmpdir"] = tempfile.mkdtemp()` runs before the try/finally** in `download_worker`. If `TMPDIR` is unwritable/full, `mkdtemp` raises out of the worker thread: no `finish_job()`, so `active_job` stays set and the queue (and agent idle-exit) wedges silently. Move the mkdtemp inside the guarded body or wrap it.
- **`split_sections` glob breaks if the media stem contains `[`** — the glob pattern concatenates `stem` raw; a `[` in the stem makes the pattern a character class and matches nothing (silent: originals are kept as a safe fallback, so it's a functional gap, not a path-injection; the regex side uses `re.escape` correctly — fix by globbing with `re.escape` too or by listing the dir and regex-matching).
- **`pause` SIGSTOPs only the direct child PID**, not the process group — yt-dlp's own helper children (if any) keep running under a "paused" headline; resume is fine. Consider a process group + `start_new_session=True` if full-lull pause ever matters.
- **Theme files read with no size cap** (`_read_utf8`). Multigraph TOMLs are already discarded by the value-length regex; a cap is cheap belt-and-suspenders.
- **`escapeHtml` omits `'`.** Used only in text-node contexts today (safe); it would be unsafe if ever reused for attribute values. Comment that or extend with `"'" -> "&#39;"`.
- **No explicit CSP meta** on `popup.html`/`options.html`. MV3's default policy covers `script-src 'self'`; an explicit `<meta http-equiv="Content-Security-Policy">` is redundant but future-proofs against a manifest change that widens defaults.
- **Agent socket symlink pre-placement** causes `bind()` to fail (transient DoS until removed); flock prevents two agents, and a crashed agent's stale socket file is cleaned. Defensive `lstat` + refuse-symlink before bind would close it.

## Non-issues (checked, rejected)

- XSS: host data reaches the popup only through `textContent`/`innerHTML`+`escapeHtml`; QML/widget surfaces are `PlainText`; theme CSS variables are `setProperty`-driven and value-whitelisted `#hex`/safe chars.
- Command injection: no shell anywhere; URLs after `--`; whitelisted option values; `outputDir` is an argv value, not an option.
- Path traversal: realpath prefix checks both in `resolve_file` and queue snapshots; out-of-dir writes are not possible from data yt-dlp reports.
- SSRF/credential exfiltration: downloads are user-initiated by design (a local tool); `http_url` permits private networks — matching this tool's purpose, not a boundary.
- `theme` action: raw palette data never reaches yt-dlp or a shell; only echoed as CSS vars through whitelists.

## Tooling notes

- The `security-audit-skill` wasn't vendored; installed globally via `npx -y skills add netresearch/security-audit-skill@security-audit -g -y`. It is not in the `skill()` registry this session (read directly from `~/.agents/skills/security-audit/`). Its `python.sh` scanner only walks `src/lib/app` / root `*.py`, so it missed the extension-less `host/najm-ytdlp-host`; copies were staged at `/tmp/opencode/audit/`. Its `secrets.sh`/`javascript.sh` equivalents scan false-positively on skill docs; the manual `git grep` + git-history check above is authoritative (clean).