# IPC and shadyctl

Full text: `docs/IPC_API.md` in the Shady checkout.

## Socket and wire format

- Socket: `$XDG_RUNTIME_DIR/shady-<wayland socket>.sock`, e.g.
  `/run/user/1000/shady-wayland-0.sock`. Mode `0700`, removed on exit. Shady
  exports it as `SHADY_SOCKET` to the programs it starts. No `XDG_RUNTIME_DIR`
  means no IPC.
- Newline-delimited JSON both ways. Request: `{"id": 1, "cmd": "windows", ...args}`.
  `id` (number or string, optional) is echoed back. Argument values are strings,
  numbers, booleans, `null` or arrays of strings; nested objects are rejected.
  A request line is at most 64 KiB.
- Every request gets exactly one response, in order:
  `{"id":1,"ok":true,"data":...}` or `{"id":2,"ok":false,"error":"..."}`.
  `data` is omitted when a command returns nothing.
- Protocol version 1 (`version`). Fields and events may be added within a
  version: ignore what you do not know.

## Objects

Window: `{"id","app_id","title","workspace","focused","mapped","maximized","fullscreen","x","y","width","height"}`.
`id` is stable for the window's lifetime (and matches the `shady-shell-v1` id).
Only mapped windows are listed.

Output: `{"name","width","height","scale","enabled"}` (logical size).

## Queries

| Command | Data |
|---|---|
| `version` | `{"protocol": 1, "compositor": "shady"}` |
| `windows` | array of windows |
| `focused` | the focused window or `null` |
| `workspaces` | `{"current": "main", "list": [...]}` |
| `outputs` | array of outputs |
| `plugins` | array of `{"name","spec","state","builtin"}` |
| `values` | every published value, `{"key": "value", ...}` |
| `value` | `key=...` -> that value or `null` |
| `shortcuts` | array of `{"keys","group","description"}` |

## Commands

| Command | Arguments | Effect |
|---|---|---|
| `window.focus` | `window` | focus it, switching to its workspace first |
| `window.close` | `window` | ask the client to close |
| `window.maximize` | `window`, `state`? | set, or toggle without `state` |
| `window.fullscreen` | `window`, `state`? | set, or toggle without `state` |
| `window.move` | `window`, `workspace` | move to a workspace (created if needed) |
| `workspace.switch` | `name` | switch (created if needed) |
| `key` | `keys` | press and release a shortcut; data `{"handled": bool}` |
| `screenshot` | `path`?, `delay`? (0-10000 ms) | save the next frame as PNG; data `{"path": ...}` |
| `shortcuts.toggle` | | shells show/hide their overlay; with none subscribed Shady draws its own |
| `lua` | `code`, `name`? | run Lua in the live runtime; data is the array of return values |
| `plugin.reload` / `plugin.unload` | `name` | hot reload / unload |
| `subscribe` | `events`? | start receiving events (all without `events`) |
| `quit` | | end the compositor |

`window` is the IPC window id (a number).

`key` uses the `shady.bind` syntax (`Super+Shift+z`) and goes through module
hooks, native plugins, Lua bindings and compositor bindings like a real key
press, so any plugin or rice shortcut can be triggered. It is **not** delivered
to the focused client: `handled: false` means no binding took it, and the key
went nowhere.

`screenshot` replies immediately; the file is written with the next frame drawn.
`screenshot.saved` (or `screenshot.failed`) is then published with the path.
Default path: `$XDG_PICTURES_DIR` or `~/Pictures`, `shady-<YYYYmmdd-HHMMSS>.png`.
A second request while one is pending fails with "a screenshot is already
pending".

## Events

After `subscribe`, event lines (with an `event` field) are interleaved with
responses:

```json
{"event": "window.focused", "window": {"id": 3, "app_id": "foot", ...}}
{"event": "window.destroyed", "window": {"id": 3}}
{"event": "workspace.changed", "workspace": "two"}
{"event": "output.added", "output": {"name": "DP-1", ...}}
{"event": "module.started", "module": "border-accent"}
{"event": "value.changed", "key": "layout.overview", "value": "1"}
{"event": "shortcuts.toggle", "count": 2}
{"event": "shortcut", "keys": "Super+Shift+slash", "group": "Shady", "description": "Show these shortcuts"}
```

Names: `window.created`, `window.mapped`, `window.unmapped`, `window.focused`,
`window.resized`, `window.state_changed`, `window.title_changed`,
`window.destroyed`, `output.added`, `output.removed`, `workspace.changed`,
`module.started`, `module.stopped`, `value.changed`, `shortcuts.toggle`.
`window.unmapped` and `window.destroyed` carry only the id. Subscribing to
`value.changed` first replays every current value. A subscriber that stops
reading is dropped once 4 MiB is queued for it.

Published values worth knowing: `layout.overview` (`"1"` while the overview
shows), `layout.strip` (the scrolling strip, for minimaps), `screenshot.saved`,
`screenshot.failed`, `session.lock`, plus whatever rices and plugins publish
(`shadyctl values` lists them).

## shadyctl

```sh
shadyctl [-s socket] [--json] <command> [key=value ...]
shadyctl [-s socket] [--json] lua '<code>' | lua -f file.lua | lua -
shadyctl [-s socket] --raw '<json request>'
```

- `key=value`: `true`, `false`, `null` and numbers become JSON values; `events`
  is split on commas; everything else is a string.
- Prints `data` (the whole response with `--json`). Exit 1 on an error
  response, 2 on usage/read errors.
- After `subscribe` it prints one event per line until the compositor exits:

```sh
shadyctl subscribe events=window.focused,workspace.changed | while read -r line; do
    jq -r '.window.title // .workspace' <<<"$line"
done
```

### Running Lua over IPC

```sh
shadyctl lua 'shady.set("window_opacity", 0.9)'
shadyctl lua 'return shady.current_workspace(), shady.workspaces()'
shadyctl lua 'local w = shady.focused_window(); return w and {app_id = w.app_id, title = w.title}'
shadyctl lua -f ./script.lua          # read locally, sent as text
printf 'return 6 * 7\n' | shadyctl lua -
```

- Same Lua state as `init.lua`; globals and handlers persist. Requires the
  `lua` module.
- Return values become a JSON array (`return 42, true, nil` -> `[42,true,null]`).
  Strings, finite numbers, booleans, nil and plain tables serialize; sequences
  become arrays and string keys objects. Userdata (Window, Output), functions,
  sparse/mixed tables and non-finite numbers are errors, so return fields, not
  objects. Limits: depth 16, 16 384 values, 1 MiB of JSON.
- The Lua `Window` has no `id`. To act on a window over IPC, take its id from
  `shadyctl windows`.
- `print` and `shady.log` go to the compositor log, not to shadyctl.
- Runs synchronously on the compositor thread: do not block; use
  `shady.automation.after(ms, fn)` to wait.
