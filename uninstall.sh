#!/usr/bin/env bash
# Uninstall Najm Downloader: remove NativeMessagingHosts manifests, restore
# or strip the --load-extension= flag, delete the rendered manifest.
# The RSA key is kept (removes with --purge-key if you really want it gone).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$ROOT/extension"
KEY="$ROOT/host/najm-ytdlp-key.pem"
MANIFEST_NAME="com.najm.ytdlp.json"

PURGE_KEY=0
[[ "${1:-}" == "--purge-key" ]] && PURGE_KEY=1

remove_native() {
  local dir="$1"
  local file="$dir/NativeMessagingHosts/$MANIFEST_NAME"
  if [[ -f "$file" ]]; then
    rm -f "$file"
    echo "removed $file"
  fi
}
remove_native "$HOME/.config/chromium"
remove_native "$HOME/.config/BraveSoftware/Brave-Origin"

strip_flags() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # Always strip the flag in place — never restore the .najm-bak wholesale, or
  # flags other tools added after install would be lost. The backup install.sh
  # left behind stays on disk as a manual safety net.
  if ! grep -qF -- "$EXT_DIR" "$file"; then
    [[ -f "${file}.najm-bak" ]] && echo "no $EXT_DIR in $file (backup kept: ${file}.najm-bak)"
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
  if [[ -f "${file}.najm-bak" ]]; then
    echo "  backup kept at ${file}.najm-bak"
  fi
}
strip_flags "$HOME/.config/chromium-flags.conf"
strip_flags "$HOME/.config/brave-origin-flags.conf"

rm -f "$EXT_DIR/manifest.json"
echo "removed rendered $EXT_DIR/manifest.json"

if [[ "$PURGE_KEY" == 1 && -f "$KEY" ]]; then
  rm -f "$KEY"
  echo "removed $KEY (next install will generate a new extension id)"
fi

echo
echo "Najm Downloader uninstalled. Restart the browser to unload the extension."