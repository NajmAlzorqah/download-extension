#!/usr/bin/env bash
# Fully remove Najm Downloader: browser side (marker-driven uninstall.sh) then
# the Omarchy plugin itself. Prefer the self-contained state-dir copy of
# uninstall.sh (works even if this checkout is gone); fall back to this repo's
# own. Downloads are untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_UNINSTALL="$HOME/.local/state/najm-downloads/uninstall.sh"

if [[ -x "$STATE_UNINSTALL" ]]; then
  "$STATE_UNINSTALL"
else
  "$ROOT/uninstall.sh"
fi

omarchy plugin remove najm.downloads --yes