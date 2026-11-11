# Shaders

Full text: `docs/SHADER_API.md`. GLES2-style GLSL, file based. Core shaders are
in `compositor/shaders/` (`window.vert/.frag`, `window_ext.frag`, `side`,
`shadow`, `floor`, `background`, `titlebar`, `copy`, `debug`); plugins keep
theirs next to their source (`plugins/shaders/`). Uniforms are optional: the
host assigns only the ones a shader declares.

## Fullscreen passes (render hooks)

```glsl
// vertex
attribute vec2 a_pos;
varying vec2 v_uv;
void main() { v_uv = a_pos * 0.5 + 0.5; gl_Position = vec4(a_pos, 0.0, 1.0); }
```

```glsl
// fragment
precision mediump float;
uniform float u_time;
uniform vec2 u_resolution;
varying vec2 v_uv;
void main() { gl_FragColor = vec4(v_uv, 0.5 + 0.5 * sin(u_time), 0.15); }
```

Draw from a render hook with `api->shader_draw_fullscreen(host, program)`.
`shader_draw_fullscreen_scene` first copies the output drawn so far into
`u_scene` (`sampler2D`, unit 0, RGB) with `u_scene_size`; it only works inside a
hook and costs one full-output copy per call, so call it only while the effect is
visible. Output is premultiplied; alpha 1 replaces the pixel.

## Per-window shaders

`api->window_set_shader(host, window, program)` replaces the built-in window
shader on Shady's subdivided window mesh; `window_reset_shader` restores it.
Attributes: `a_pos` (vec3, location 0) and, for MESH representations, `a_uv`
(location 2, active when `u_use_vertex_uv` is 1).

Host uniforms (declare the ones you need):

| Uniform | |
|---|---|
| `u_tex` | client content, unit 0, always a 2D sampler (external textures are copied first) |
| `u_uv_rect` | the window inside `u_tex` without client shadows; sample `u_uv_rect.xy + uv * u_uv_rect.zw` |
| `u_mvp`, `u_model` | matrices |
| `u_frame_rect` | this pass's sub-rect of the decorated frame (title bar and client are separate passes) |
| `u_frame_px`, `u_frame_shape` | frame size in px, corner radius and border px; `0,0` when the rounded frame does not apply |
| `u_time`, `u_resolution`, `u_window_size` | seconds, output buffer px, logical client size |
| `u_has_alpha` | 0 when the content must be treated as opaque |
| `u_tint`, `u_brightness`, `u_effect_strength`, `u_light_dir` | the window's look |
| `u_wobble`, `u_water`, `u_water_surface` | motion and water state |
| `u_border_color`, `u_border_width` | border |
| `u_close_progress`, `u_close_effect` | close animation |
| `u_params[4]` (vec4) | per-window values from `window_set_shader_params` |
| `u_portal_tex`, `u_portal_available`, `u_portal_size` | another window set with `window_set_shader_source` |

Vertex pattern for frame-aware shaders:

```glsl
attribute vec3 a_pos;
attribute vec2 a_uv;
uniform float u_use_vertex_uv;
uniform vec4 u_frame_rect;
vec2 local_pos = a_pos.xy;
vec2 local_uv = mix(local_pos, a_uv, step(0.5, u_use_vertex_uv));
vec2 frame_pos = u_frame_rect.xy + local_pos * u_frame_rect.zw;
// texture coordinates: v_uv = vec2(local_uv.x, 1.0 - local_uv.y);
```

Output premultiplied alpha. For rounded corners, copy `frame_distance()` from
`compositor/shaders/window.frag`. A shader that fails to compile falls back to the
built-in one.

## Layer backdrop effects (from Lua)

`shady.layer_effect(namespace, { shader = "/path/effect.frag", uniforms = { strength = 0.6 } })`.
Write only `vec4 effect()`; Shady supplies `main()` and masks by the surface's
alpha. Available: `vec4 scene(vec2 pixel)`, `vec2 local()`, `float mask()`,
`u_time` (using it redraws every frame), `u_size`, `u_scale`, `u_region`,
`u_capture`, and your uniforms as `u_<name>`. Pixel coordinates are the output
buffer's, top-down. Taps reach at most the `blur` radius beyond the surface, so
set `blur` to how far the shader looks. Example: `examples/layer-effects/refract.frag`.

```glsl
uniform float u_strength;
vec4 effect() {
    vec2 p = gl_FragCoord.xy;
    vec2 ripple = vec2(sin(p.y * 0.08 + u_time), cos(p.x * 0.05)) * 6.0 * u_strength;
    return mix(scene(p + ripple), vec4(0.9, 0.95, 1.0, 1.0), 0.08);
}
```
