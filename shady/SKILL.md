---
name: shady
description: Drive, script, test and extend the Shady Wayland compositor (github.com/gloaming-dusk/shady). Use when working in a Shady checkout or on a machine running Shady, or when the task mentions shadyctl, the `shady.*` Lua API (config.lua, init.lua, rices such as Tide), the IPC socket, `shady.automation` headless tests, native C plugins (`libshady-plugin-*.so`), plugin or layer shaders, or environment loaders.
license: Apache-2.0
---

# Shady

Shady is an experimental 3D Wayland compositor on wlroots 0.20. It is the
compositor only: the bar, launcher and lock screen live in shady-shell, and the
desktop look in rices (Tide is the default). Everything a script or an agent
needs goes through five surfaces:

| Surface | Use it for | Reference |
|---|---|---|
| IPC socket + `shadyctl` | Reading state and driving a running session from outside: windows, workspaces, keys, screenshots, events, running Lua | [references/ipc.md](references/ipc.md) |
| Lua (`shady.*`) | Configuration (`config.lua`), runtime behaviour (`init.lua`): bindings, rules, events, layout, published values | [references/lua.md](references/lua.md) |
| Headless automation (`shady.automation`) | Deterministic regression tests on a headless backend | [references/headless.md](references/headless.md) |
| C plugins | Native modules: input hooks, render hooks, per-window shaders, 3D representations, hot reload | [references/plugins.md](references/plugins.md) |
| Shaders | Fullscreen passes, per-window shaders, layer backdrop effects | [references/shaders.md](references/shaders.md) |

Read the reference for the surface you are about to use before writing code
against it. In a checkout, `docs/*_API.md` is the full, authoritative text;
these references are a working summary with the traps called out.

## Orient yourself first

```sh
shadyctl version                       # is a Shady session reachable?
shadyctl windows                       # mapped windows, with their IPC ids
shadyctl lua 'return shady.has_capability("spatial"), shady.current_workspace()'
shadyctl plugins                       # loaded native plugins and their states
shadyctl shortcuts                     # every key the session answers to
```

`shadyctl` finds the socket from `-s path`, else `$SHADY_SOCKET`, else
`$XDG_RUNTIME_DIR/shady-$WAYLAND_DISPLAY.sock`. From a terminal *inside* Shady
`SHADY_SOCKET` is already set. From elsewhere (another compositor, an SSH
session, a nested Shady), pass `-s` explicitly. Two Shady instances never share
a socket, so be sure which one you are talking to.

## Configuration model

- Two Lua stages with separate states: `config.lua` runs before the compositor
  starts (settings, compositor bindings, plugin loading); `init.lua` runs once it
  is up (key bindings to functions, rules, event handlers, timers). Plugins can
  only be *loaded* in `config.lua`; at runtime they can only be listed,
  reloaded and unloaded.
- Files come from `~/.config/shady/` and, for any file missing there, from the
  rice (`SHADY_RICE`, default `tide`; `SHADY_RICE=none` is the bare compositor).
  A user `init.lua` **replaces** the rice's `init.lua` completely unless it calls
  `shady.base("tide")` first. This is the usual reason "Tide's keys stopped
  working".
- `shadyctl lua '…'` runs in the live `init.lua` state: globals, bindings and
  handlers you create there persist until the next reload.

## Workflows

**Inspect or change a live session.** Use `shadyctl` queries, then commands
(`window.focus window=<id>`, `workspace.switch name=2`, `key keys=Super+o`,
`screenshot path=/tmp/x.png`). For anything not covered by a command, `shadyctl
lua 'return …'` and return plain values (see the IPC reference for what
serializes).

**Look at the result of a change.** Run a second, nested Shady from the
checkout and screenshot it; do not experiment on the user's own session.
[`scripts/shady-nested.sh`](scripts/shady-nested.sh) starts one and prints its
socket; then drive it with `shadyctl -s <socket>` and read the PNG that
`screenshot` writes. Stop it with `shadyctl -s <socket> quit`.

**Write a regression test.** Copy
[`templates/headless-test.sh`](templates/headless-test.sh) and
[`templates/headless-test-init.lua`](templates/headless-test-init.lua) into
`tests/`, rename, fill in the steps. The pattern: a Lua scenario that spawns the
probe client, waits for `window.mapped`, drives input with `shady.automation`,
asserts, logs `<name>: PASS` and calls `shady.quit()`; the shell script runs
Shady on the headless backend and greps the log. Details in
[references/headless.md](references/headless.md).

**Build and run the tests (in a checkout).**

```sh
nix develop                       # the toolchain: wlroots 0.20.2, Lua 5.4, Meson
./tools/build.sh                  # configure and build into build/ (or: ninja -C build)
meson test -C build               # unit tests
SHADY_SPATIAL_TEST_BUILD_DIR=build ./tests/headless-overview.sh   # one headless test
./tests/spatial-suite.sh          # every spatial test, under ASan/UBSan
```

Outside `nix develop`, wrap commands: `nix develop -c ninja -C build`.

## Traps that cost time

- **IPC `key` and `shady.automation.key` never reach clients.** They go through
  module hooks, plugins, Lua bindings and compositor bindings only. To type into
  an application use `shady.automation.type_text` (needs `wtype`) or a real
  keyboard.
- **`window.id` in Lua is new.** Since Shady commit 53537a7 a Lua `Window` has
  `id`, the same id IPC uses. Older builds have none (it reads `nil`): there,
  take ids from `shadyctl windows` and match Lua windows by `app_id`/`title`.
- **`screenshot` replies before the file exists.** The reply carries the path;
  the PNG is written with the next frame. Wait for the published value
  `screenshot.saved` (or `screenshot.failed`), or poll for the file. Only one
  capture can be pending at a time.
- `shady.screenshot()` / IPC `screenshot` capture what Shady draws, 3D included,
  with no external tool. `shady.automation.screenshot` shells out to `grim` and
  is rarely what you want.
- `shady.layout.*`, `shady.camera`, layer effects and the overview exist only
  with the GL (spatial) renderer. Check `shady.has_capability("spatial")`; with
  `--safe` or `TIDE_LIGHT=1` they return false.
- Maximized and fullscreen windows are drawn flat in screen space, outside the
  3D scene, except in first-person mode and while the layout's overview has the
  camera.
- Bindings: a key has one binding, and the last `shady.bind` wins. Lua bindings
  run before compositor bindings (`quit`, `show_shortcuts`, `screenshot`, ...).
  The bare compositor binds `quit` to plain `Escape` by default.
- Coordinates in automation and IPC are logical layout pixels, not buffer
  pixels.
- Before Shady commit 53537a7, `shady.automation.after(0, fn)` never fires; use
  1 ms or more when the build may be older.
- A Lua error in `config.lua` (including a failed `shady.plugins.load`) stops
  the compositor from starting; wrap optional loads in `pcall`.

## When you change Shady itself

Keep `docs/*_API.md` and `CHANGELOG.md` (`## Unreleased`) in step with the code:
the docs are the contract other tools rely on. The public C headers in
`include/shady/` are append-only: never reorder or remove fields of
`struct shady_plugin_api_v1`; add new entries at the end and gate their use with
`SHADY_API_HAS(api, field)`.
