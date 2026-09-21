#!/usr/bin/env bash
# Install Najm Downloader's browser side.
#
# This is the repo-root Omarchy plugin installer: it registers the native
# yt-dlp host into every Chromium-family profile on the machine, merges
# --load-extension= into every browser flags conf, checks the yt-dlp/ffmpeg
# deps the host hardcodes, and writes the marker the bar widget reads to flip
# out of "setup needed" mode.
#
# `omarchy plugin add` runs no plugin scripts, so the widget launches this on
# its first click (install.sh resolves its own root, so it works identically
# from a checkout and from the installed plugin dir). Idempotent - safe to
# re-run whenever a new browser profile appears. The flags files always carry
# exactly one Najm extension path: any previously configured path to a
# different checkout (same extension name) is dropped in favour of this one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="$ROOT/host/najm-ytdlp-host"
EXT_DIR="$ROOT/extension"
MANIFEST="$EXT_DIR/manifest.json"
NATIVE_TPL="$ROOT/host/com.najm.ytdlp.json.tpl"
MANIFEST_NAME="com.najm.ytdlp.json"
STATE_DIR="$HOME/.local/state/najm-downloads"
MARKER="$STATE_DIR/installed.json"

# Chromium-family profile roots that use the NativeMessagingHosts layout.
# Omarchy-parity (omarchy-install-chromium-ytdlp) plus this project's own
# Brave-Origin profile.
NATIVE_DIRS=(
  "$HOME/.config/chromium"
  "$HOME/.config/google-chrome"
  "$HOME/.config/google-chrome-beta"
  "$HOME/.config/google-chrome-unstable"
  "$HOME/.config/BraveSoftware/Brave-Browser"
  "$HOME/.config/BraveSoftware/Brave-Browser-Beta"
  "$HOME/.config/BraveSoftware/Brave-Browser-Nightly"
  "$HOME/.config/BraveSoftware/Brave-Origin"
  "$HOME/.config/microsoft-edge"
  "$HOME/.config/microsoft-edge-dev"
)
# Flags conf names (matches the Omarchy yt-dlp migration list + Brave-Origin).
FLAGS_CONFS=(
  chromium
  chrome
  google-chrome
  brave
  brave-beta
  brave-nightly
  brave-origin
  brave-origin-beta
  microsoft-edge-stable
)
# Core browsers: create their flags conf even if it doesn't exist yet so the
# extension is guaranteed for the profiles this project targets.
CORE_CONFS=(chromium brave-origin)

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1" >&2; exit 1; }; }
need sha256sum
need base64
command -v python3 >/dev/null 2>&1 || { echo "error: missing python3" >&2; exit 1; }

chmod +x "$HOST"

# ------------------------------------------------------------------ extension id
# The id is pinned by the SPKI `key` baked into extension/manifest.json (no
# private key involved - a new key would change the id and break
# allowed_origins). Derived the same way Chromium does it:
#   sha256(SPKI DER) first 16 bytes, hex digits mapped 0-f -> a-p.
KEYB64="$(sed -n 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -1)"
[[ -n "$KEYB64" ]] || { echo "error: no key field in $MANIFEST" >&2; exit 1; }
DER="$(mktemp)"
printf '%s' "$KEYB64" | base64 -d > "$DER"
HEX="$(sha256sum "$DER" | cut -d' ' -f1)"
rm -f "$DER"
HEX="${HEX:0:32}"
MAP="abcdefghijklmnop"
ID=""
for ((i = 0; i < ${#HEX}; i++)); do
  v=$((16#"${HEX:$i:1}"))
  ID+="${MAP:$v:1}"
done
echo "extension id: $ID (pinned by committed key)"

# --------------------------------------------------- NativeMessaging hosts
written=()
write_native() {
  local dir="$1"
  mkdir -p "$dir/NativeMessagingHosts"
  sed -e "s|@@HOST_PATH@@|$HOST|" \
      -e "s|@@EXT_ORIGIN@@|chrome-extension://$ID/|" \
      "$NATIVE_TPL" > "$dir/NativeMessagingHosts/$MANIFEST_NAME"
  echo "host manifest -> $dir/NativeMessagingHosts/$MANIFEST_NAME"
  written+=("${dir#$HOME/.config/}")
}
for dir in "${NATIVE_DIRS[@]}"; do
  write_native "$dir"
done

# ------------------------------------------------------------- flags merge
# Adds EXT_DIR to --load-extension= in every flags conf. Idempotent: leaves
# the entry alone when EXT_DIR is already listed, and drops any OTHER Najm
# Downloader checkout path so a line never carries two. The work happens in
# python (already required for the marker) to avoid sed fragility with
# comma-separated values and other flags on the same line.
python3 - "$EXT_DIR" "${FLAGS_CONFS[@]}" <<'PY'
import json, os, re, sys

ext = sys.argv[1]
confs = sys.argv[2:]
home = os.environ.get("HOME", "")
core = {"chromium", "brave-origin"}

def is_other_najm(p):
    if p == ext:
        return False
    m = os.path.join(p, "manifest.json")
    if not os.path.isfile(m):
        return False
    try:
        with open(m, encoding="utf-8", errors="replace") as f:
            return '"Najm Downloader"' in f.read(4096)
    except OSError:
        return False

def update(filepath, create):
    if os.path.exists(filepath):
        with open(filepath, encoding="utf-8", errors="replace") as f:
            lines = f.read().split("\n")
    else:
        lines = []
    flag_re = re.compile(r"(--load-extension=)(\S*)")
    changed = False
    patched_line = None
    for i, ln in enumerate(lines):
        m = flag_re.search(ln)
        if not m:
            continue
        parts = [p for p in m.group(2).split(",") if p]
        keep = []
        for p in parts:
            if is_other_najm(p):
                print("  dropped previous najm path %s" % p)
                changed = True
            else:
                keep.append(p)
        if ext not in keep:
            keep.append(ext)
            changed = True
        lines[i] = ln[:m.start(2)] + ",".join(keep) + ln[m.end(2):]
        patched_line = lines[i]
        break
    if patched_line is None:
        if create:
            lines.append("--load-extension=%s" % ext)
            changed = True
        else:
            return changed, lines
    if changed:
        if os.path.exists(filepath):
            os.replace(filepath, filepath + ".najm-bak")
        with open(filepath, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
    return changed, lines

for name in confs:
    path = os.path.join(home, ".config", name + "-flags.conf")
    before = os.path.exists(path)
    try:
        changed, _ = update(path, name in core)
    except OSError as e:
        print("  error %s: %s" % (path, e))
        continue
    if not before and not os.path.exists(path):
        print("  skip  %s (does not exist)" % path)
    elif changed:
        print("  updated %s" % path)
    else:
        print("  ok    %s (already loaded)" % path)
PY

# ------------------------------------------------------------- deps check
# The host hardcodes these absolute paths (host lines 32-33); a yt-dlp found
# elsewhere on PATH still has to land at /usr/bin. Best-effort install via
# omarchy-pkg-add (sudo-less, Omarchy-only); otherwise warn with the hint.
YOUTUBE_OK=0
FFMPEG_OK=0
check_dep() {
  local bin="$1"
  if [[ -x /usr/bin/$bin ]]; then
    echo "ok    /usr/bin/$bin"
    return 0
  fi
  local found
  if found="$(command -v "$bin" || true)" && [[ -n "$found" ]]; then
    echo "warn  $bin found at $found but the host hardcodes /usr/bin/$bin - symlink it there"
    return 1
  fi
  if command -v omarchy-pkg-add >/dev/null 2>&1; then
    echo "trying omarchy-pkg-add $bin ..."
    if omarchy-pkg-add "$bin" >/dev/null 2>&1 && [[ -x /usr/bin/$bin ]]; then
      echo "ok    installed /usr/bin/$bin via omarchy-pkg-add"
      return 0
    fi
  fi
  echo "warn  $bin missing - the host requires /usr/bin/$bin"
  return 1
}
check_dep yt-dlp && YOUTUBE_OK=1
check_dep ffmpeg && FFMPEG_OK=1
if [[ "$YOUTUBE_OK" != 1 || "$FFMPEG_OK" != 1 ]]; then
  echo
  echo "NOTE: yt-dlp/ffmpeg must be at /usr/bin for the native host. Install them"
  echo "      (sudo pacman -S yt-dlp ffmpeg, or omarchy-pkg-add yt-dlp ffmpeg) and"
  echo "      re-run this script."
fi

# ---------------------------------------------------------------- marker
# The widget flips out of "setup needed" when this file exists and reads
# `profiles` for its success hint. Never written into the plugin dir, so
# `omarchy plugin update` stays a clean fast-forward.
mkdir -p "$STATE_DIR"
python3 - "$MARKER" "$EXT_DIR" "$ID" "$HOST" "$YOUTUBE_OK" "$FFMPEG_OK" "${written[@]}" <<'PY'
import json, sys, time
marker, ext_dir, ext_id, host = sys.argv[1:5]
yt = sys.argv[5] == "1"
ff = sys.argv[6] == "1"
profiles = sys.argv[7:]
data = {
    "extension_dir": ext_dir,
    "extension_id": ext_id,
    "host_binary": host,
    "profiles": profiles,
    "ytdlp": yt,
    "ffmpeg": ff,
    "installed_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
}
with open(marker, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
echo "marker -> $MARKER"

# ---------------------------------------------------------------- summary
echo
echo "Najm Downloader installed."
echo "  extension dir : $EXT_DIR"
echo "  extension id  : $ID"
echo "  profiles      : $(IFS=', '; echo "${written[*]}")"
echo "  yt-dlp        : $([ "$YOUTUBE_OK" = 1 ] && echo present || echo MISSING)"
echo "  ffmpeg        : $([ "$FFMPEG_OK" = 1 ] && echo present || echo MISSING)"
echo
echo "Restart the browsers (chromium, chrome, brave, edge, ...) for the extension to appear."