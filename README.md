# gloaming-dusk skills

[Agent Skills](https://agentskills.io) for working with
[Shady](https://github.com/gloaming-dusk/shady), the experimental 3D Wayland
compositor, and its desktop. A skill is a folder of instructions, references
and scripts that an AI agent loads when a task calls for it.

| Skill | What it teaches |
|---|---|
| [`shady`](shady/SKILL.md) | Driving a running session with `shadyctl` and the IPC socket, computer use (seeing the screen, clicking and typing), the `shady.*` Lua API for `config.lua` / `init.lua`, headless regression tests with `shady.automation`, native C plugins, shaders and environment loaders, and the traps that cost time |

## Install

**Claude Code**, as a plugin marketplace:

```text
/plugin marketplace add gloaming-dusk/skills
/plugin install shady@gloaming-dusk-skills
```

The plugin also connects the `shady` MCP server, for computer use: install
[shady-mcp](https://github.com/gloaming-dusk/shady-mcp) so `shady-mcp` is on
`PATH` (`nix profile install github:gloaming-dusk/shady-mcp`). Without it the
skill works as before and only the server fails to start.

**Any agent that reads skill folders**: copy or link `shady/` into its skills
directory, for example `~/.claude/skills/shady` (personal) or
`.claude/skills/shady` inside a Shady checkout (that project only):

```sh
git clone https://github.com/gloaming-dusk/skills ~/src/gloaming-dusk-skills
ln -s ~/src/gloaming-dusk-skills/shady ~/.claude/skills/shady
```

## Layout

```text
shady/
├── SKILL.md                    entry point: which API to use, workflows, traps
├── references/
│   ├── ipc.md                  socket, wire format, commands, events, shadyctl
│   ├── lua.md                  config.lua / init.lua, bindings, rules, layout, events
│   ├── headless.md             headless backend, shady.automation, probe client
│   ├── plugins.md              C plugin ABI, host API, representations, loaders
│   └── shaders.md              fullscreen, per-window and layer backdrop shaders
├── scripts/
│   └── shady-nested.sh         start a nested Shady and print its socket
└── templates/
    ├── headless-test.sh        a headless test runner (3D and --safe)
    └── headless-test-init.lua  its Lua scenario
```

The references summarise Shady's `docs/*_API.md` for an agent and point out
where the code and the obvious reading of the docs disagree. When Shady
changes, the docs in its repository are authoritative; update the skill to
match.

## License

[Apache License 2.0](LICENSE), the same as Shady.
