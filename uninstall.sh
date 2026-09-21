#!/usr/bin/env bash
# Uninstall Najm Downloader's browser side: remove the NativeMessagingHosts
# manifests from every Chromium-family profile, strip --load-extension= from
# the flags confs (preserving other tools' entries), remove the setup marker.
# The extension id is pinned by the committed key in extension/manifest.json,
# so there is nothing to purge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$ROOT/extension"
MANIFEST_NAME="com.najm.ytdlp.json"
STATE_DIR="$HOME/.local/state/najm-downloads"
MARKER="$STATE_DIR/installed.json"

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

remove_native() {
  local file="$1/NativeMessagingHosts/$MANIFEST_NAME"
  if [[ -f "$file" ]]; then
    rm -f "$file"
    echo "removed $file"
  fi
}
for dir in "${NATIVE_DIRS[@]}"; do
  remove_native "$dir"
done

strip_flags() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # Always strip in place - never restore a .najm-bak wholesale, or flags other
  # tools added after install would be lost. The backup install.sh left behind
  # stays on disk as a manual safety net.
  if ! grep -qF -- "$EXT_DIR" "$file"; then
    return 0
  fi
  local esc
  esc="$(printf '%s' "$EXT_DIR" | sed 's/[][\\.^$*?+(){}|]/\\&/g')"
  sed -i -E \
    -e "s~--load-extension=$esc,~--load-extension=~g" \
    -e "s~,$esc,~,~g" \
    -e "s~,$esc([[:space:]]|\$)~\1~g" \
    -e "s~--load-extension=$esc([[:space:]]|\$)~--load-extension=\1~g" \
    -e "s~[[:space:]]*--load-extension=([[:space:]]|\$)~\1~g" \
    -e 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    "$file"
  sed -i '/^[[:space:]]*$/d' "$file"
  echo "stripped $EXT_DIR from $file"
  [[ -f "${file}.najm-bak" ]] && echo "  backup kept at ${file}.najm-bak"
}
for name in "${FLAGS_CONFS[@]}"; do
  strip_flags "$HOME/.config/$name-flags.conf"
done

if [[ -f "$MARKER" ]]; then
  rm -f "$MARKER"
  echo "removed $MARKER"
fi

echo
echo "Najm Downloader uninstalled. Restart the browsers to unload the extension."
echo "The extension id stays pinned to the committed key; re-install with ./install.sh"