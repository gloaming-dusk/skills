#!/usr/bin/env bash
# Template for a Shady headless test. Copy into tests/ as headless-<name>.sh,
# next to tests/headless-<name>-init.lua, set NAME, and run it from anywhere:
#
#   SHADY_SPATIAL_TEST_BUILD_DIR=build tests/headless-<name>.sh
#
# It runs the compositor on the headless backend with software GL, once in the
# 3D renderer and once with --safe (the 2D path), and passes when the Lua
# scenario logged "<NAME>: PASS" with no Lua, ASan or UBSan error.
set -euo pipefail

NAME=example                      # the scenario logs "$NAME: PASS"
MODES=(spatial safe)              # drop "safe" for features that need the GL renderer

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="${SHADY_SPATIAL_TEST_BUILD_DIR:-build}"
COMPOSITOR="$BUILD_DIR/shady"
PROBE="$BUILD_DIR/headless-automation-probe"
for bin in "$COMPOSITOR" "$PROBE"; do
  [[ -x $bin ]] || { echo "$NAME: missing $bin; build first" >&2; exit 2; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=gles2 LIBGL_ALWAYS_SOFTWARE=1
export SHADY_ROOT="$ROOT"
export SHADY_RICE=none            # no rice: only what the scenario binds
export SHADY_AUTOMATION_PROBE="$ROOT/$PROBE"
export SHADY_LUA_INIT="$ROOT/tests/headless-$NAME-init.lua"
export ASAN_OPTIONS="${ASAN_OPTIONS:-abort_on_error=1:halt_on_error=1:detect_leaks=0}"
export UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}"

config="$tmp/config.lua"
cat >"$config" <<'EOF'
shady.set("spatial_mode", true)
shady.set("physics_enabled", false)
shady.set("window_gravity", false)
shady.set("window_wobble", false)
shady.set("close_animation", false)
shady.modules({ ["window-motion"] = false, ["physics"] = false, ["fps"] = false, ["lua"] = true })
shady.bind("quit", "none")
EOF

for mode in "${MODES[@]}"; do
  runtime="$tmp/runtime-$mode"
  mkdir -m 700 "$runtime"
  log="$tmp/$mode.log"
  args=(-c "$config")
  [[ $mode == safe ]] && args+=(--safe)
  set +e
  XDG_RUNTIME_DIR="$runtime" timeout 30s "$COMPOSITOR" "${args[@]}" >"$log" 2>&1
  rc=$?
  set -e
  if [[ $rc -ne 0 ]] || grep -Eq 'AddressSanitizer|runtime error:|\[ERROR\].*\[SHADY LUA\]' "$log" ||
      ! grep -q "$NAME: PASS" "$log"; then
    tail -n 60 "$log" >&2
    echo "$NAME[$mode]: FAIL (status $rc)" >&2
    exit 1
  fi
  echo "$NAME[$mode]: PASS"
done
