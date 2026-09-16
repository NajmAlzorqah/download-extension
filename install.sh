#!/usr/bin/env bash
# Install Najm Downloader for Chromium and Brave-Origin.
# - generates a persistent RSA key (stable extension ID)
# - renders extension/manifest.json with the key
# - registers the NativeMessagingHosts manifest for both browsers
# - appends the extension dir to each browser's --load-extension= flag
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="$ROOT/host/najm-ytdlp-host"
KEY="$ROOT/host/najm-ytdlp-key.pem"
EXT_DIR="$ROOT/extension"
MN_IN="$ROOT/extension/manifest.json.in"
MN_OUT="$ROOT/extension/manifest.json"
NATIVE_TPL="$ROOT/host/com.najm.ytdlp.json.tpl"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1" >&2; exit 1; }; }
need openssl; need sha256sum

chmod +x "$HOST"

# ------------------------------------------------------------------ key / id
if [[ ! -f "$KEY" ]]; then
  umask 077
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$KEY"
  echo "generated $KEY"
fi
DER="$(mktemp)"
openssl pkey -in "$KEY" -pubout -outform DER > "$DER"
KEYB64="$(base64 -w0 "$DER")"
HEX="$(sha256sum "$DER" | cut -d' ' -f1)"
rm -f "$DER"
HEX="${HEX:0:32}"
MAP="abcdefghijklmnop"
ID=""
for ((i = 0; i < ${#HEX}; i++)); do
  v=$((16#"${HEX:$i:1}"))
  ID+="${MAP:$v:1}"
done
echo "extension id: $ID"

# ---------------------------------------------------------- render manifest
sed "s|@@KEY@@|$KEYB64|" "$MN_IN" > "$MN_OUT"
if command -v jq >/dev/null 2>&1; then
  jq empty "$MN_OUT" || { echo "error: rendered manifest invalid" >&2; exit 1; }
fi

# --------------------------------------------------- NativeMessaging hosts
write_native() {
  local dir="$1"
  mkdir -p "$dir/NativeMessagingHosts"
  sed -e "s|@@HOST_PATH@@|$HOST|" \
      -e "s|@@EXT_ORIGIN@@|chrome-extension://$ID/|" \
      "$NATIVE_TPL" > "$dir/NativeMessagingHosts/com.najm.ytdlp.json"
  echo "host manifest -> $dir/NativeMessagingHosts/com.najm.ytdlp.json"
}
write_native "$HOME/.config/chromium"
write_native "$HOME/.config/BraveSoftware/Brave-Origin"

# ------------------------------------------------------------- flags merge
merge_flags() {
  local file="$1"
  local ext="$2"
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    printf -- '--load-extension=%s\n' "$ext" > "$file"
    echo "created $file"
    return
  fi
  if awk -v e="$ext" 'index($0,"--load-extension=") && index($0,e) { found=1 } END { exit !found }' "$file"; then
    echo "already loaded in $file"
    return
  fi
  cp -a "$file" "${file}.najm-bak"
  if grep -q -- "--load-extension=" "$file"; then
    sed -i -E "s~^(.*--load-extension=[^[:space:]]+)$~\1,$ext~" "$file"
  else
    printf -- '\n--load-extension=%s\n' "$ext" >> "$file"
  fi
  echo "added extension to $file (backup: ${file}.najm-bak)"
}
merge_flags "$HOME/.config/chromium-flags.conf" "$EXT_DIR"
merge_flags "$HOME/.config/brave-origin-flags.conf" "$EXT_DIR"

# ---------------------------------------------------------------- summary
echo
echo "Najm Downloader installed."
echo "  extension dir : $EXT_DIR"
echo "  extension id  : $ID"
echo
echo "Restart Chromium and Brave-Origin for the extension to appear."
echo "The popup must be pinned: use the toolbar icon (or inspector override)."