# Contributing

Thanks for your interest in Najm Downloader. This project is open source under
the MIT License; the notes below keep contributions legally clean and easy to
review.

## Licensing your contributions (inbound = outbound)

By submitting a contribution (a pull request, commit, or patch), you agree
that your contribution is licensed under the project's MIT License, the same
terms as the code you are building on — including any third-party notices that
already apply to the files you touch (see `NOTICE.md`).

To make this explicit, sign your commits with a Developer Certificate of
Origin trailer, and add **`Signed-off-by: Your Name <you@example.com>`** to the
commit message:

```
Signed-off-by: Your Name <you@example.com>
```

`git commit -s` adds this automatically. Adding the line means you certify that
you wrote the contribution yourself, or that you have the right to submit it
under the MIT License (Developer Certificate of Origin, version 1.1).

Please do not submit material you do not have the right to license, including
code copied from other projects without compatible permissive terms.

## How to contribute

1. Fork the repository on GitHub and clone your fork.
2. Create a feature branch: `git checkout -b feature/your-change`.
3. Make your change, following the conventions in `AGENTS.md` and the style of
   the code around it.
4. Verify your change:
   - `python3 -m py_compile host/najm-ytdlp-host` for host changes.
   - The Omarchy widget has its own validation; see `AGENTS.md` -> Commands.
   - There is no lint/typecheck infrastructure — don't invent one.
5. Commit with a descriptive message and the `Signed-off-by` trailer.
6. Push and open a pull request describing what changed and why.

## Gotchas to keep in mind

- Never edit `extension/manifest.json` — it is generated from
  `manifest.json.in` by `./install.sh`.
- Never regenerate or commit `host/najm-ytdlp-key.pem`. The extension id is
  derived from it; a new key breaks the native-host `allowed_origins` and the
  key must stay private.
- Keep `extension/background-*.js` filename bumps and the `manifest.json.in`
  `background` field in sync (Chromium caches service workers).
- The `najm.osd` panel is a *derivative* of Omarchy's MIT-licensed `omarchy.osd`;
  preserve its provenance headers and keep the Omarchy copyright notice intact.
- Keep `extension/defaults.js`, `extension/theme.js`'s fallback reading, and the
  widget's `Formats.js`/`Defaults.js` in sync — duplicated logic drifts.
- The host parser (`run_one`) and `build_command()` tagged lines
  (`NJDP:PCT`, `NJDP:FILE`, `NJDP:TITLE`) are coupled: editing one side without
  the other silently breaks progress/file tracking.