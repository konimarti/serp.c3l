# Ideas

- Typed positional args (`ctx.arg_int(0)`), enum/choice validated flags
- Flag groups: mutually exclusive / required together
- Auto env prefix (`MYAPP_PORT` for `--port`) via `app.env_prefix`
- Dynamic shell completion (`__complete`) for flag values and file names
- Config file support (flag defaults from TOML/JSON)
- Interactive prompts for missing required flags
