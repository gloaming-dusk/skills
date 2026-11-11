#!/usr/bin/env bash
# Start a nested Shady in a window of the current Wayland session, wait until it
# listens, and print how to reach it. The compositor keeps running in the
# background; stop it with `shadyctl -s "$SHADY_SOCKET" quit`.
#
#   shady-nested.sh [-b build-dir] [-r rice|none] [-- shady arguments...]
#
#   -b DIR   the build directory holding `shady` (default: ./build, then PATH)
#   -r RICE  SHADY_RICE for this instance (default: unchanged, i.e. Tide)
#
# Prints shell assignments, so `eval "$(shady-nested.sh)"` sets them:
#   SHADY_NESTED_DISPLAY  the nested compositor's WAYLAND_DISPLAY
#   SHADY_SOCKET          its IPC socket (for shadyctl -s)
#   SHADY_NESTED_PID      its process id
#   SHADY_NESTED_LOG      its log file
#
# Run clients in it with WAYLAND_DISPLAY="$SHADY_NESTED_DISPLAY" app.
set -euo pipefail

build=""
rice=""
while getopts "b:r:h" opt; do
  case $opt in
    b) build=$OPTARG ;;
    r) rice=$OPTARG ;;
    h) sed -n '2,19p' "$0"; exit 0 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[[ ${1:-} == -- ]] && shift

if [[ -n $build ]]; then
  shady="$build/shady"
elif [[ -x ./build/shady ]]; then
  shady=./build/shady
else
  shady=$(command -v shady || true)
fi
[[ -n $shady && -x $shady ]] || { echo "shady-nested: no shady binary (use -b)" >&2; exit 2; }
[[ -n ${WAYLAND_DISPLAY:-} ]] || { echo "shady-nested: needs a Wayland session to nest in" >&2; exit 2; }
[[ -n ${XDG_RUNTIME_DIR:-} ]] || { echo "shady-nested: XDG_RUNTIME_DIR is not set" >&2; exit 2; }

log=$(mktemp "${TMPDIR:-/tmp}/shady-nested.XXXXXX.log")
env=(WLR_BACKENDS=wayland)
[[ -n $rice ]] && env+=("SHADY_RICE=$rice")
# setsid: the compositor outlives this script and the caller's terminal.
env "${env[@]}" setsid "$shady" "$@" >"$log" 2>&1 </dev/null &
pid=$!

display=""
for _ in $(seq 1 150); do
  if ! kill -0 "$pid" 2>/dev/null; then
    tail -n 30 "$log" >&2
    echo "shady-nested: shady exited during startup (log: $log)" >&2
    exit 1
  fi
  display=$(sed -n 's/.*Running Wayland compositor on WAYLAND_DISPLAY=\([^ ]*\).*/\1/p' "$log" | head -n 1)
  [[ -n $display && -S "$XDG_RUNTIME_DIR/shady-$display.sock" ]] && break
  display=""
  sleep 0.1
done
[[ -n $display ]] || { echo "shady-nested: no socket after 15 s (log: $log)" >&2; exit 1; }

printf 'SHADY_NESTED_DISPLAY=%q\n' "$display"
printf 'SHADY_SOCKET=%q\n' "$XDG_RUNTIME_DIR/shady-$display.sock"
printf 'SHADY_NESTED_PID=%q\n' "$pid"
printf 'SHADY_NESTED_LOG=%q\n' "$log"
