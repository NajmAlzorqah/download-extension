# Video Downloader Ultra credits

This project is original code under the MIT License — see [LICENSE](LICENSE) for
the terms and the copyright line. The work below is the exception: one of them
is incorporated into the source, and the rest are external programs the host
runs as separate processes. Each is credited with the licence it carries.

## Summary

| Work | Licence | How it is used here |
| --- | --- | --- |
| Omarchy `omarchy.osd` | MIT | Base of the `Osd.qml` panel kind |
| yt-dlp | Unlicense | Invoked by the host, not bundled |
| ffmpeg | LGPL / GPL | Invoked by the host, not bundled |
| Quickshell | LGPL-3.0 | Imported module interfaces only |
| Nerd Font glyphs | per typeface | Rendered from system fonts, not bundled |

## Omarchy — base of the `Osd.qml` panel kind

`Osd.qml` and `OsdModel.js` are derived from the stock `omarchy.osd` plugin that
Omarchy ships. The additions on top of that base are the stacked
title-over-bar download layout with its readout column, and the click-to-dismiss
card; the IPC target stays `najmalzorqah.video-downloader-ultra.osd` so the host's OSD calls are unchanged. The
base work is reproduced under the following license:

```
Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Both files carry this provenance in a header comment — keep it intact when
editing them.

## Runtime software the host invokes

These run as separate processes under the user's own account. No code from any
of them is copied, linked or embedded into this project, so they are listed for
transparency rather than for compliance.

- **yt-dlp** — [Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE)
  (public domain). Runs from `/usr/bin/yt-dlp` and does the actual downloading.
- **ffmpeg** — LGPL or GPL depending on how it was built. Merges separate video
  and audio streams.
- **Quickshell** — [LGPL-3.0](https://github.com/quickshell-io/quickshell). The
  QML panels import its public module interfaces and those of QtQuick; they
  incorporate no LGPL code.
- **Nerd Font glyphs** — the bar and OSD icons are glyphs rendered from whatever
  Nerd Font is installed on the system. No font files are bundled here.

## Original work

Everything else is original to this project and under the MIT License: the
native host and its agent daemon, the browser extension, the bar widget and
its JavaScript, the icons in `extension/icons/`, and the documentation.

## Disclaimer

The project license covers this project's own code. The software downloads
third-party media at your request, so respect the legal terms and copyright of
the platforms and the content you download — those rights belong to their owners
and are not conveyed by this license.
