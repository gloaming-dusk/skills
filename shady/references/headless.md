# Headless tests and automation

Full text: `docs/HEADLESS_API.md` and `docs/DEVELOPMENT.md`; the `tests/headless-*`
files in the checkout are the best examples (39 suites).

## Running Shady headless

```sh
export XDG_RUNTIME_DIR="$(mktemp -d)"     # private socket dir (mode 0700)
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1
export WLR_RENDERER=gles2 LIBGL_ALWAYS_SOFTWARE=1   # GL path without a GPU
export SHADY_ROOT="$PWD"                  # find shaders, plugins and rices in the checkout
export SHADY_LUA_INIT="$PWD/tests/my-test-init.lua"
timeout 30s ./build/shady -c tests/my-test-config.lua >"$log" 2>&1
```

- Headless outputs are 1280x720 at scale 1.
- `--safe` runs the plain 2D scene-graph path (no 3D renderer, no shipped
  plugins); run a test in both modes when it touches rendering.
- `WLR_RENDERER=pixman` works only for 2D (`spatial_mode = false`).
- The spatial suite builds `build-spatial-asan/` with sanitizers; a single test
  also runs against the normal build with `SHADY_SPATIAL_TEST_BUILD_DIR=build`.
- Set `ASAN_OPTIONS=abort_on_error=1:halt_on_error=1:detect_leaks=0` and
  `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`, and fail the test when the
  log contains `AddressSanitizer` or `runtime error:`.

A test config usually turns off what would make it slow or nondeterministic:

```lua
shady.set("spatial_mode", true)
shady.set("physics_enabled", false)
shady.set("window_gravity", false)
shady.set("window_wobble", false)
shady.set("close_animation", false)
shady.modules({ ["window-motion"] = false, ["physics"] = false, ["fps"] = false, ["lua"] = true })
shady.bind("quit", "none")   -- or an Escape in the test ends the session
```

## `shady.automation`

| Function | |
|---|---|
| `after(ms, fn)` | run `fn` once after `ms` milliseconds; `0` means the next pass of the event loop (builds before 53537a7 never fire a 0 ms timer, so use 1 or more there) |
| `key(shortcut) -> handled, sent` | press and release; `handled` when a binding took it, else (0.4.0) `sent` to the focused window |
| `key_down(shortcut)` / `key_up(shortcut)` | one half; `key_down("Super_L"); key_up("Super_L")` is a Super tap |
| `type_text(text) -> count \| nil, err` | types any text into the focused window (0.4.0; before, it spawned `wtype` and returned a pid) |
| `move_pointer(x, y)` | logical layout coordinates |
| `click(button)` | `"left"`, `"right"`, `"middle"` or a Linux button code; the argument is required |
| `button_down(button)` / `button_up(button)` | for drags that wait on the client between steps |
| `drag(x1, y1, x2, y2[, button[, steps]])` | default left, 8 steps (1..256) |
| `swipe(fingers, dx, dy[, steps]) -> bool` | a touchpad swipe as the scrolling layout sees it |
| `scroll([vertical[, horizontal]])` | pointer-axis events |
| `screenshot(path[, fn(ok, path)]) -> pid \| nil, err` | runs `grim`; prefer `shady.screenshot(path)` |

Automated keys go through compositor, plugin and Lua bindings but are never sent
to clients. Pointer events do reach clients. Coordinates are logical pixels.

## Probe client

`build/headless-automation-probe` is a tiny xdg-toplevel (320x200 by default,
fixed size) controlled by environment variables:

| Variable | Effect |
|---|---|
| `SHADY_AUTOMATION_PROBE_APP_ID` | app id (default `shady-automation-probe`) |
| `SHADY_AUTOMATION_PROBE_TITLE` | title |
| `SHADY_AUTOMATION_PROBE_COLOR` | ARGB fill, e.g. `0xffcc3344` |
| `SHADY_AUTOMATION_PROBE_PATTERN` | draw a pattern instead of a flat fill |
| `SHADY_AUTOMATION_PROBE_RESIZABLE` | drop the fixed size, so the window tiles |
| `SHADY_AUTOMATION_PROBE_RETITLE` (+ `_MS`, default 1000) | change the title after a delay |
| `SHADY_AUTOMATION_PROBE_STATUS` | file the probe appends to: `KEY=PASS`, `CLICK=PASS`, `DRAG=PASS`, `SCROLL=PASS` |
| `SHADY_AUTOMATION_POINTER_TEST` | also log `BUTTON=<code> <x> <y>` on each press |

Spawn it from the scenario: `shady.spawn("SHADY_AUTOMATION_PROBE_APP_ID=a " .. probe)`
where the script exported `SHADY_AUTOMATION_PROBE="$ROOT/build/headless-automation-probe"`.

## Scenario pattern

Wait for events, not for fixed startup sleeps. Run steps one after another so
each sees the settled result of the last, and turn every failure into a log line
and a quit, so the shell script fails fast instead of timing out:

```lua
local A = shady.automation
local function check(cond, msg) if not cond then error("mytest: " .. msg) end end

local steps = {}
local function step(ms, fn) steps[#steps + 1] = { ms, fn } end
local function run(i)
    local s = steps[i]
    if not s then shady.log("mytest: PASS") shady.quit() return end
    A.after(s[1], function()
        local ok, err = pcall(s[2])
        if not ok then shady.log(tostring(err)) shady.quit() return end
        run(i + 1)
    end)
end

shady.bind("Super+m", function() shady.focused_window():maximize(true) end)

step(100, function() check(#shady.windows() == 1, "the probe did not map") end)
step(100, function() check(A.key("Super+m"), "Super+m was not handled") end)
step(300, function() check(shady.focused_window().maximized, "the window did not maximize") end)

local started = false
shady.on("window.mapped", function()
    if started then return end
    started = true
    run(1)
end)
shady.spawn(os.getenv("SHADY_AUTOMATION_PROBE"))
```

The shell side passes when the exit status is 0, the log has the PASS line and
no sanitizer report. `templates/headless-test.sh` and
`templates/headless-test-init.lua` in this skill are a ready-to-copy pair.

## Checking pixels

`shady.screenshot(path)` writes a PNG of what Shady drew (3D included), and
publishes `screenshot.saved` once written; poll for it with `after`. Check the
size from the PNG header (`1280x720` headless) and, when it matters, sample
pixels with Python outside the compositor. In 3D, windows are transformed:
derive expected positions from the scene, or test known screen-space states.

## Nested sessions (interactive checks)

For looking at a change by eye, or with real applications, run Shady inside the
current Wayland session instead: `WLR_BACKENDS=wayland ./build/shady -c <config>`
(it opens a window). `scripts/shady-nested.sh` in this skill does that and
prints the socket; drive it with `shadyctl -s <socket>` and start clients in it
with `WAYLAND_DISPLAY=<its display>`.
