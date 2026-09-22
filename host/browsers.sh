#!/usr/bin/env bash
# Shared browser coverage for Video Downloader Ultra's install/uninstall.
#
# Sourced by install.sh and uninstall.sh (the previously duplicated NATIVE_DIRS
# / FLAGS_CONFS lists drifted; this is the single source). Canonical roots are
# written unconditionally — the native manifest is idempotent and harmless in an
# absent or unused root. Discovery is strictly conservative: a Chromium-family
# root we did not ship with is only registered when its flags conf already
# exists on disk, so we never invent paths or create config files.

# Known Chromium-family profile roots that use the NativeMessagingHosts layout
# (Omarchy-parity + this project's own Brave-Origin).
browser_roots() {
  printf '%s\n' \
    "$HOME/.config/chromium" \
    "$HOME/.config/google-chrome" \
    "$HOME/.config/google-chrome-beta" \
    "$HOME/.config/google-chrome-unstable" \
    "$HOME/.config/BraveSoftware/Brave-Browser" \
    "$HOME/.config/BraveSoftware/Brave-Browser-Beta" \
    "$HOME/.config/BraveSoftware/Brave-Browser-Nightly" \
    "$HOME/.config/BraveSoftware/Brave-Origin" \
    "$HOME/.config/microsoft-edge" \
    "$HOME/.config/microsoft-edge-dev"
}

# Flags conf names (matches the Omarchy yt-dlp migration list + Brave-Origin).
browser_conf_names() {
  printf '%s\n' \
    chromium chrome google-chrome brave brave-beta brave-nightly \
    brave-origin brave-origin-beta microsoft-edge-stable
}

# Core browsers: create their flags conf even if it doesn't exist yet so the
# extension is guaranteed for the profiles this project targets.
browser_core_confs() {
  printf '%s\n' chromium brave-origin
}

# Map a Chromium-family profile root to its distro's flags-conf name, or "" if
# unknown. Only consulted for roots outside the canonical list.
browser_conf_for_root() {
  local root="$1"
  case "$root" in
    */BraveSoftware/Brave-Browser-Beta) echo "brave-beta" ;;
    */BraveSoftware/Brave-Browser-Nightly) echo "brave-nightly" ;;
    */BraveSoftware/Brave-Browser) echo "brave" ;;
    */BraveSoftware/Brave-Origin-Beta) echo "brave-origin-beta" ;;
    */BraveSoftware/Brave-Origin) echo "brave-origin" ;;
    */google-chrome-*) echo "google-chrome" ;;
    */microsoft-edge-dev) echo "" ;; # no dev stable conf convention
    */microsoft-edge) echo "microsoft-edge-stable" ;;
    */vivaldi) echo "vivaldi" ;;
    *) echo "" ;;
  esac
}

# Conservative discovery, emitting "root\tconf" lines for Chromium-family roots
# that: are not in the canonical list, look like a real profile root
# (`Local State` or `Preferences` present), and whose target flags conf already
# exists. Never creates a flags conf and never invents a name.
browser_discover() {
  local base="$HOME/.config" gone
  gone="$(mktemp)"
  browser_roots > "$gone"
  shopt -s nullglob
  local candidates=(
    "$base"/chromium*
    "$base"/google-chrome*
    "$base"/vivaldi*
    "$base"/microsoft-edge*
    "$base"/BraveSoftware/Brave-*
  )
  shopt -u nullglob
  local root conf
  for root in "${candidates[@]}"; do
    [[ -d "$root" ]] || continue
    [[ -e "$root/Local State" || -e "$root/Preferences" ]] || continue
    grep -qxF "$root" "$gone" && continue
    conf="$(browser_conf_for_root "$root")"
    [[ -n "$conf" ]] || continue
    [[ -f "$base/$conf-flags.conf" ]] || continue
    printf '%s\t%s\n' "$root" "$conf"
  done
  rm -f "$gone"
}