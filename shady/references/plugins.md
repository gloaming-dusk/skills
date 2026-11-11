# Native C plugins

Full text: `docs/C_PLUGIN_API.md`, `docs/PLUGIN_MANAGER.md`,
`docs/ENVIRONMENT_API.md` and the headers in `include/shady/` (`plugin.h`,
`module.h`, `event.h`, `types.h`, `motion.h`, `representation.h`,
`environment.h`). Small examples: `examples/plugins/{hello,counter,orbit_layout}.c`;
larger ones: `plugins/*.c`. Out-of-tree plugins live in
github.com/gloaming-dusk/shady-plugins.

A plugin is native code inside the compositor, with access to every window and
key. Write one when Lua is not enough: per-frame work, input hooks, render hooks,
per-window shaders, 3D representations, asset loaders.

## Building and loading

- Build a shared library named `libshady-plugin-<name>.so` against
  `include/` (the headers need wlroots/wayland includes from the dev shell).
- Load it from `config.lua` only: `shady.plugins.load("<name>")` (search path)
  or `shady.plugins.load("./build/libshady-plugin-<name>.so")`. A failed load
  aborts startup; use `pcall` for optional plugins.
- At runtime: `shady.plugins.reload(name)` / `unload(name)`, or
  `shadyctl plugin.reload name=<name>`. Reload migrates state for ABI v2
  plugins; unload needs a stateless plugin with no active dependents. Loading new
  plugins at runtime is not supported.
- The host runs a private copy of the `.so`: use `api->plugin_path(host, module)`
  (from `init` on) to find files next to it, never `dladdr()`.

## Entry points

```c
#include <shady/plugin.h>

static const struct shady_plugin_api_v1 *api;
static shady_host host;

static bool init(struct shady_server *server) {
    (void)server;
    api->log(SHADY_PLUGIN_LOG_INFO, "hello from plugin");
    return true;
}

static const char *provides[] = { "example.hello", NULL };

static const struct shady_module module = {
    .name = "hello",
    .provides = provides,
    .init = init,
};

const struct shady_module *shady_plugin_entry_v1(uint32_t abi,
        const struct shady_plugin_api_v1 *host_api, shady_host host_handle) {
    if (abi != SHADY_PLUGIN_ABI_V1 || !host_api) return NULL;
    api = host_api;
    host = host_handle;
    return &module;
}
```

- ABI v1: `shady_plugin_entry_v1` returns a `struct shady_module`.
- ABI v2: `shady_plugin_entry_v2` returns a `struct shady_plugin_v2` wrapping the
  module plus snapshot size/save/restore callbacks and a schema version, for state
  that survives hot reload (`plugins/window_motion.c` is a full example).
- The API table is append-only: check `SHADY_API_HAS(api, field)` before any
  newer entry (`declare_shortcut`, `plugin_path`, `publish_value`,
  `window_set_shader_params`, `shader_draw_fullscreen_scene`, `query_api`, ...).

## Module descriptor

`struct shady_module`: `name`, `provides`, `requires`, `optional_requires`
(NULL-terminated capability arrays, used for dependency ordering), `state_size`,
`toplevel_state_size`, lifecycle callbacks (`load -> init -> start -> ... ->
stop -> destroy -> unload`), window lifecycle callbacks, input hooks (`key`,
pointer), a picking hook, a movement hook, and a per-frame `tick`.

Private state: `api->module_state(host, "name")`, per window
`api->window_state(window, "name")`. Handles (`shady_window`, `shady_output`)
are opaque: never dereference them.

## What the API offers

- Windows: `window_count`, `window_at`, title, app id, state, workspace, size,
  position; focus, close, maximize, fullscreen, move to workspace, set XYZ.
- Outputs, seat, modules, workspaces (list and switch),
  `has_capability(host, "spatial")`, `schedule_render(host)` after any change
  that needs a redraw.
- Events: `subscribe_event(host, SHADY_EVENT_WINDOW_MAPPED, fn, data)` or
  `subscribe_event_handle` / `unsubscribe_event`. Event types are in
  `shady/event.h`; subscriptions are removed when the plugin unloads.
- Shortcuts: `declare_shortcut(host, "Super+Z", "What it does")` lists a key the
  plugin's `key` hook handles in the overlay and the IPC `shortcuts` query
  (it binds nothing). Declare from the entry function, which runs on every reload.
- Published values: `publish_value(host, "myplugin.state", "on")`,
  `published_value(host, key)`. Removed when the plugin unloads.
- Window effects owned by the compositor: water deformation and surface,
  border override/reset, close-effect override/reset
  (`window_set_close_effect`).
- Render: `shader_program_create(host, vert_path, frag_path)` (0 = failure),
  `shader_uniform_float/int/vec2/vec4`, `render_hook_add(host, stage, fn, data)`
  with `SHADY_RENDER_STAGE_AFTER_BACKGROUND`, `BEFORE_WINDOWS`, `AFTER_WINDOWS`,
  `OVERLAY`; inside a hook `shader_draw_fullscreen` or
  `shader_draw_fullscreen_scene` (binds the output so far as `u_scene`).
  `window_set_shader` / `window_reset_shader` replace one window's shader,
  `window_set_shader_params` gives it 16 per-window floats (`u_params[4]`),
  `window_set_shader_source` samples another live window as `u_portal_tex`.
  The host owns all GL objects and frees a plugin's programs, hooks and window
  associations when it unloads. See [shaders.md](shaders.md).
- Camera-aware render context (check `SHADY_RENDER_CONTEXT_HAS(ctx, aspect)`):
  `camera_position`, `camera_forward/right/up`, `tan_half_fov_y`, `aspect`.
- Versioned feature tables through `api->query_api(host, name, version)`:
  `shady.window-motion` (`shady/motion.h`), `shady.window-representation`
  (`shady/representation.h`), `shady.environment` (`shady/environment.h`).
  NULL means unavailable.

## 3D window representations (first-person mode)

`window_set_representation` gives a folded window a box
(`SHADY_WINDOW_REPRESENTATION_BOX`) or a mesh (`_MESH`). A provider
(`window_set_representation_provider`) computes it per frame: `model`, `mesh`,
`collision`, `collision_hull`, `collision_compound`, optional per-window state
(`state_size`, `state_init`, `update(dt)` returning true while animating,
`state_destroy`). Bump `revision` whenever geometry changes. Limits: 16 384 mesh
vertices / 49 152 indices; hulls 256 vertices / 1 536 indices; compounds 1-8
parts within the same budget. Keep the provider descriptor in static storage and
pass the same pointer to reset. Examples: `plugins/fps_cube.c`, `fps_squash.c`,
`fps_jelly.c`, `fps_folded_paper.c`, `fps_origami.c`.

## Environment loaders

A loader plugin parses a model format into a `struct shady_environment_scene`
(world-space vertices with optional indices, plus collision `boxes` and
`triangles`; the visual mesh is never used for collision) and registers per
extension with `env->register_loader(host, &loader)` from the module's `init`
(it requires `spatial`). The host deep-copies, renders and collides; the loader
frees its memory in `release`. `environment_path` with a matching extension
triggers it; `set_scene` installs a procedural scene. Limits: 32 boxes (one is
the floor), 4096 collision triangles. Example: `plugins/loaders/obj/obj_loader.c`.

## Shipping a plugin with Shady

Build it as `libshady-plugin-<name>.so` into the build directory and
`libdir/shady/plugins`; to load it by default add
`shady_plugin_manager_add_default(server, "<name>")` in
`compositor/src/module/builtin.c` behind its meson feature define. Test it with a
headless scenario (see [headless.md](headless.md)) and a reload test if it keeps
state.
