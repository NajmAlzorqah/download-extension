#!/usr/bin/env bash
# perf-check.sh — measure RSS + CPU of the Video Downloader Ultra processes (and the
# Omarchy shell hosting its widgets) so each perf fix can be verified with real
# before/after numbers (per the performance-optimization skill's
# measure → fix → re-measure → keep-or-revert rule).
#
# Dep-free: only bash + /proc (no ps-arg variance between installs).
#
# Usage:
#   tools/perf-check.sh                 # 30s window: RSS + CPU% for agent, shims, quickshell
#   tools/perf-check.sh --seconds 15    # custom window length
#   tools/perf-check.sh --spawns 60     # count omarchy-shell najmalzorqah.video-downloader-ultra.osd "show" spawns/s over 60s
#
# Exit code: 0 even on empty matches (it's a reporter, not a gate).

CLK=$(getconf CLK_TCK 2>/dev/null); CLK=${CLK:-100}

snapshot() {
  # $1 = pid. Prints: rss_kb utime stime comm
  local pid=$1
  local rss utime stime comm
  rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
  read -r utime stime < <(awk '{print $14, $15}' "/proc/$pid/stat" 2>/dev/null)
  comm=$(tr '\0' ' ' < "/proc/$pid/comm" 2>/dev/null)
  printf '%s %s %s %s\n' "${rss:-0}" "${utime:-0}" "${stime:-0}" "${comm:-?}"
}

# Per-thread CPU is only readable via /proc/<pid>/task/<tid>/stat (the direct
# /proc/<tid>/stat path reports process-wide utime/stime on this kernel).
snapshot_tid() {
  local pid=$1 tid=$2 utime stime comm
  read -r utime stime < <(awk '{print $14, $15}' "/proc/$pid/task/$tid/stat" 2>/dev/null)
  comm=$(tr '\0' ' ' < "/proc/$pid/task/$tid/comm" 2>/dev/null)
  printf '%s %s %s\n' "${utime:-0}" "${stime:-0}" "${comm:-?}"
}

agents()   { pgrep -f 'video-downloader-ultra-host --agent' 2>/dev/null; }
shims()    { pgrep -f 'video-downloader-ultra-host chrome-extension' 2>/dev/null; }
shells()   { pgrep -f 'quickshell -n -p /usr/share/omarchy/shell' 2>/dev/null; }

idle_mode() {
  local seconds=$1 pid t
  local -A before=()
  local agent_pids=() shim_pids=() shell_pids=()
  mapfile -t agent_pids < <(agents)
  mapfile -t shim_pids < <(shims)
  mapfile -t shell_pids < <(shells)
  printf 'Sampling %ss window (RSS + CPU delta across the whole window):\n' "$seconds"
  for pid in "${agent_pids[@]}"; do
    before[$pid]=$(snapshot "$pid")
  done
  for pid in "${shim_pids[@]}"; do
    before[$pid]=$(snapshot "$pid")
  done
  for pid in "${shell_pids[@]}"; do
    before[$pid]=$(snapshot "$pid")
    for t in /proc/$pid/task/*; do
      t=${t##*/}
      before["${pid}.${t}"]=$(snapshot_tid "$pid" "$t")
    done
  done
  sleep "$seconds"
  printf '  %-14s %-9s %8s\n' "component" "pid" "delta"
  for pid in "${agent_pids[@]}"; do
    printf '  %-14s %-9s ' agent "$pid"
    cpu_delta "${before[$pid]}" "$pid" "$seconds"
  done
  for pid in "${shim_pids[@]}"; do
    printf '  %-14s %-9s ' shim "$pid"
    cpu_delta "${before[$pid]}" "$pid" "$seconds"
  done
  for pid in "${shell_pids[@]}"; do
    printf '  %-14s %-9s ' quickshell "$pid"
    cpu_delta "${before[$pid]}" "$pid" "$seconds"
    for t in /proc/$pid/task/*; do
      t=${t##*/}
      [ "$t" = "$pid" ] && continue
      printf '  %-14s %-9s ' "  └ thread" "$t"
      tid_cpu_delta "${before[${pid}.${t}]}" "$pid" "$t" "$seconds"
    done
  done
  printf '\nQuick summary (idle posture):\n'
  if [ ${#agent_pids[@]} -gt 0 ]; then
    printf '  agent:   alive (keepalive held by widget/shim) — should still be ~0%% CPU\n'
  else
    printf '  agent:   NOT running — idle-exit is working\n'
  fi
  if [ ${#shim_pids[@]} -gt 0 ]; then
    printf '  shim(s): %d alive — a native port is currently open (SW connected)\n' "${#shim_pids[@]}"
  else
    printf '  shim(s): none — no native port open\n'
  fi
}

cpu_delta() {
  local ref=$1 pid=$2 seconds=$3 rss utime stime d
  read -r rss utime stime _ <<<"$ref"
  local now
  now=$(snapshot "$pid")
  read -r _ b1 b2 _ <<<"$now"
  d=$((b1 + b2 - utime - stime))
  printf 'RSS %4d MB   CPU %4d.%02d%% (%s ticks)\n' \
    "$((rss / 1024))" "$((d * 100 / seconds / CLK))" \
    "$((d * 10000 / seconds / CLK % 100))" "$d"
}

tid_cpu_delta() {
  local ref=$1 pid=$2 tid=$3 seconds=$4 utime stime d comm
  read -r utime stime comm <<<"$ref"
  local now
  now=$(snapshot_tid "$pid" "$tid")
  read -r b1 b2 _ <<<"$now"
  d=$((b1 + b2 - utime - stime))
  printf 'CPU %4d.%02d%% (%4d ticks)  [%s]\n' \
    "$((d * 100 / seconds / CLK))" "$((d * 10000 / seconds / CLK % 100))" "$d" "$comm"
}

spawns_mode() {
  local seconds=$1 t n total=0 prev
  printf 'Sampling omarchy-shell najmalzorqah.video-downloader-ultra.osd "show" spawns for %ss (1 sample/s):\n' "$seconds"
  # pgrep -fc prints the count; on this procps it emits "0" yet returns exit 1,
  # so take just the first token — the ||echo 0 fallback is not needed.
  prev=$(pgrep -fc 'omarchy-shell -q najmalzorqah.video-downloader-ultra.osd show' 2>/dev/null)
  prev=${prev%%$'\n'*}
  for ((t = 0; t < seconds; t++)); do
    n=$(pgrep -fc 'omarchy-shell -q najmalzorqah.video-downloader-ultra.osd show' 2>/dev/null); n=${n%%$'\n'*}
    # A rise means new spawns happened between the two samples.
    [ "$n" -gt "$prev" ] 2>/dev/null && total=$((total + n - prev))
    prev=$n
    sleep 1
  done
  printf '  ~%d OSD-show spawns in %ss (≈ %s/s)\n' \
    "$total" "$seconds" "$(awk -v n="$total" -v s="$seconds" 'BEGIN { printf "%.2f", n / s }')"
}

case "${1:-}" in
  --seconds) idle_mode "${2:-30}" ;;
  --spawns) spawns_mode "${2:-60}" ;;
  *) idle_mode 30 ;;
esac