# Third-Party Notices

This project incorporates or references the following third-party works. Each
notice below is reproduced exactly as required by the corresponding license.

## Omarchy (MIT License) — base of the `Osd.qml` panel kind

The `Osd.qml` panel kind of this plugin (`najm.downloads`) is a derivative of
the stock `omarchy.osd` plugin shipped by Omarchy. `Osd.qml` and `OsdModel.js`
are derived
from the Omarchy originals; the stacked title-over-bar download rendering, the
readout column, and the click-to-dismiss behavior are additions on top of that
base. The base work is reproduced under the following license:

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

The `Osd.qml` panel also imports the Quickshell and QtQuick module interfaces
(see "Quickshell" below); the `osd` integration that drives it lives in
`host/najm-ytdlp-host`.

## addyosmani/agent-skills (MIT License) — vendored skills

The agent skills under `.agents/skills/` are vendored, pinned, and distributed
verbatim from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)
(see `skills-lock.json`). They are reproduced under the following license:

```
MIT License

Copyright (c) 2025 Addy Osmani

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

## Runtime software invoked by the host (no code is bundled)

These are external executables the native host runs as separate processes; no
code from them is copied, linked, or embedded into this project. They are
listed for transparency only.

- **yt-dlp** — [Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE)
  (public domain). Invoked via `host/najm-ytdlp-host` (`/usr/bin/yt-dlp`).
- **ffmpeg** — LGPL/GPL depending on build; invoked separately, not bundled.
- **Quickshell** — [LGPL-3.0](https://github.com/quickshell-io/quickshell).
  The QML panels (`Osd.qml`, `Panel.qml`) only *import* the public
  QtQuick/Quickshell module interfaces; they do not incorporate LGPL code.
- **Nerd Fonts** — glyphs used in the OSD/bar UI render from fonts installed on
  the system (MIT-licensed typeface); no font files are bundled.

## Disclaimer

The project license covers this project's own code. The software downloads
third-party media at the user's request; respect the legal terms and copyright
of the platforms and content you download. Copyright in downloaded content
belongs to its owners, and the license does not convey any rights in it.