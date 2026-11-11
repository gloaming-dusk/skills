# Lua API (`shady.*`)

Full text: `docs/LUA_API.md`, `docs/CUSTOMIZING.md` and `docs/PLUGIN_MANAGER.md`
in the Shady checkout. Lua 5.4; the global table is `shady`.

## Stages, files, rices

| Stage | File | Runs | Typical content |
|---|---|---|---|
| Bootstrap | `config.lua` (`-c path`) | before the compositor starts | `shady.set`, `shady.bind(action, keys)`, `shady.modules{}`, `shady.plugins.load` |
| Runtime | `init.lua` (`SHADY_LUA_INIT` overrides) | once it is up, and again on reload | `shady.bind(keys, fn, desc)`, `shady.rule`, `shady.on`, timers, idle |

- Each file is taken from `~/.config/shady/` (`$XDG_CONFIG_HOME/shady/`), else
  from the rice. Rice lookup, file by file: `$SHADY_RICE_PATH`,
  `$XDG_DATA_HOME/shady/rices`, `$SHADY_ROOT/rices`, `$XDG_DATA_DIRS/shady/rices`.
- `SHADY_RICE` picks the rice (default `tide`, `none` = bare compositor).
- A file of the user's replaces the rice's file entirely. Build on the rice by
  calling `shady.base("tide")` first, then override:

```lua
-- ~/.config/shady/init.lua
shady.base("tide")
shady.bind("Super+Return", function() shady.spawn("kitty") end, "Open a terminal")
shady.unbind("Super+c")
shady.rule({ app_id = "mpv", floating = true })
```

## Core

| Function | |
|---|---|
| `shady.log(msg)` | write to the compositor log |
| `shady.set(key, value)` / `shady.config` | set a configuration value (booleans become `"true"`/`"false"`) |
| `shady.bind(action, keys)` | (config.lua) rebind a compositor action; `"none"` removes it |
| `shady.bind(keys, fn[, desc \| {description=, group=}])` | (init.lua) bind keys to a function; with a description it is listed in the shortcut overlay |
| `shady.unbind(keys) -> bool` | remove a runtime binding |
| `shady.base(rice)` | run that rice's file for the current stage |
| `shady.rule{app_id=, title=, workspace=, maximized=, fullscreen=, floating=, width=}` | window rule; the first match applies as the window maps |
| `shady.spawn(cmd) -> bool` | run through `/bin/sh -lc` |
| `shady.quit()` | end the compositor |
| `shady.screenshot([path[, delay_ms]]) -> path \| nil` | capture the next frame (3D included); nil while one is pending |
| `shady.publish(key, value \| nil) -> bool` / `shady.value(key)` | share strings with IPC clients and shady-shell; keys `[A-Za-z0-9._-]{1,128}`, values <= 4096 bytes |
| `shady.toggle_launcher() -> bool` | ask shady-shell for its launcher; false when no shell heard it |
| `shady.shell_connected() -> bool` | is shady-shell connected |
| `shady.toggle_shortcuts()` | the shortcut overlay, like `Super+Shift+/` |
| `shady.shortcuts()` | the overlay's list: `{keys, group, description}` |
| `shady.describe(keys, desc[, group])` | list a shortcut without binding it (`nil` removes) |
| `shady.has_capability(name) -> bool` | `"spatial"`, `"spatial.physics"`, `"spatial.fps"`, ... |

Key syntax: `Super+Shift+z`, `Ctrl+Alt+Delete`, `Print`, `XF86AudioRaiseVolume`.
Modifiers `Super`/`Logo`, `Ctrl`/`Control`, `Alt`, `Shift`; the key is an xkb
keysym name, case-insensitive. `shady.bind("Super", fn)` binds a *tap* of Super
(pressed and released alone within 500 ms).

Compositor actions for `shady.bind(action, keys)` and their defaults:
`show_shortcuts` Super+Shift+slash, `screenshot` Print, `quit` Escape,
`cycle_windows` Alt+Tab, `close_window` Alt+F11, `fps_toggle` F2,
`fps_capture` F3, `gravity_toggle` F4, `debug_ray` F5, `camera_left/right/up/down`
Alt+arrows, `camera_yaw_left/right` Alt+Q/E, `camera_zoom_in/out` Alt+=/-,
`camera_reset` Alt+0. Lua bindings on the same keys run first.

## Frequently used settings

`spatial_mode` (the GL 3D renderer), `layout` (`"floating"` or `"scrolling"`),
`layout_gap`, `layout_default_width`, `layout_center_single`,
`layout_animation`, `gesture_fingers`, `window_titlebar`,
`window_titlebar_height`, `window_corner_radius`, `window_border_width`,
`window_border_color`, `window_border_focus_color` (`"#RRGGBB"`),
`window_opacity`, `window_focused_exact`, `window_wobble`, `window_sides`,
`shadows`, `floor`, `sky`, `environment`, `environment_path`,
`physics_enabled`, `window_gravity`, `fps_mode`, `close_animation`,
`output_scale` (0 = guess per panel), `cursor_theme`, `cursor_size`,
`xkb_layout`, `xkb_variant`, `xkb_options`, `numlock`, `repeat_rate`,
`repeat_delay`, `touchpad_tap`, `touchpad_natural_scroll`, `prefer_no_csd`.
Set from `init.lua` or `shadyctl lua`, they apply at once.

## Runtime objects

```lua
for _, w in ipairs(shady.windows()) do shady.log(w.app_id .. " " .. w.title) end
local w = shady.focused_window()
```

Window fields: `title`, `app_id`, `mapped`, `visible`, `x`, `y`, `width`,
`height` (surface, including client shadows), `geometry_width`,
`geometry_height` (the window itself), `z` (spatial), `workspace`, `maximized`,
`fullscreen`, `tiled`. There is **no `id`**. Methods: `focus()`, `close()`,
`maximize([on])`, `set_fullscreen([on])`, `move_to_workspace(name)`,
`toggle_floating()`. A destroyed window reads as `nil`, methods return false.

`shady.outputs()` -> `{name, scale, x, y, width, height}` (logical).
`shady.pointer()` -> `x, y`. `shady.seat().name`. `shady.modules()` ->
`{name, active}`. `shady.workspaces()`, `shady.current_workspace()`,
`shady.workspace(name)`.

## Events

```lua
local id = shady.on("window.mapped", function(window) shady.log(window.app_id) end)
shady.off(id)
```

`window.created`, `window.mapped`, `window.unmapped`, `window.focused`,
`window.resized`, `window.destroyed`, `window.state_changed`,
`window.title_changed`, `output.added`, `output.removed`, `module.started`,
`module.stopped`, `workspace.changed` (receives the name). A window goes
`created -> mapped -> focused` and ends `unmapped -> destroyed`.

## Scrolling layout (`shady.layout`, GL renderer only)

`focus(dir)` / `move(dir)` with `"left"`, `"right"`, `"up"`, `"down"`,
`"first"`, `"last"`; `consume_or_expel("left"|"right")`; `set_width(spec)` /
`set_height(spec)` with `"+10%"`, `"50%"`, `"900"`, `"+40"`;
`cycle_width([forward])`; `presets{1/3, 1/2, 2/3}`; `reset_height()`;
`full_width()`; `center()`; `toggle_floating()`; `workspace(delta[, take])`;
`overview([on])`; `state()` -> `{scrolling, columns, active, view, visible, overview}`.
Each returns false when there was nothing to do.

## Idle, power, effects

- `shady.idle(seconds, on_idle[, on_resume]) -> id`, `shady.idle_clear()`,
  `shady.idle_inhibited()`, `shady.idle_inhibit(bool)`, `shady.output_power(on)`.
- `shady.layer_effect(namespace, {blur=, saturation=, tint="#RRGGBBAA", shader=, uniforms=} | nil)`:
  frosted backdrop behind layer-shell surfaces of that namespace (spatial only).
- `shady.layer_transform(namespace, {tilt=, yaw=, roll=, depth=, perspective=, pivot="anchor"|"center"} | nil)`:
  place layer surfaces on a 3D plane, input mapped through it (spatial only).
- Spatial extras when available: `shady.camera(prop, value)` (`yaw`, `pitch`,
  `distance`, `target_x/y/z`), `shady.toggle_gravity()`, `shady.respawn_all()`,
  `shady.toggle_fps()`, `shady.expand_all()`, `shady.fold_all()`.

## Plugins from Lua

- config.lua: `shady.plugins.path(dir)`, `shady.plugins.load(name_or_path)`
  (raises on failure, which aborts startup; use `pcall` for optional ones),
  `shady.plugins.enable(name)` / `disable(name)`, `shady.modules{name = bool}`.
- Runtime: `shady.plugins.list()` -> `{name, spec, path, builtin, state}`,
  `shady.plugins.reload(name)`, `shady.plugins.unload(name)`.
- Search order: `shady.plugins.path()` dirs, `$SHADY_PLUGIN_PATH`, the `shady`
  binary's directory, `$XDG_DATA_HOME/shady/plugins`, `libdir/shady/plugins`.
  A name `foo` resolves to `libshady-plugin-foo.so`.
- States: `pending`, `disabled`, `failed`, `inactive`, `active`, `unloaded`.
