```
 ___  ___ _ __ _ __
/ __|/ _ \ '__| '_ \
\__ \  __/ |  | |_) |
|___/\___|_|  | .__/
              |_|
```

# Serp: a commander for C3 command line apps

Serp is a small library for building modern CLI applications with
subcommands in [C3](https://c3-lang.org), inspired by Go's
[cobra](https://github.com/spf13/cobra). Needs `c3c` 0.8.x.

- Nested subcommands, aliases, hidden/deprecated commands, command groups
- POSIX flags: `-a`, `-abc`, `-pVALUE`, `-p VALUE`, `--port=80`, `--port 80`, `--`
- Persistent flags (inherited by subcommands), required flags, defaults,
  environment variable fallback, binding to variables
- Positional argument validators (`exact_args`, `min_args`, ...)
- Automatic `--help`/`-h`, `help <cmd>`, `--version`, colored help on terminals
- "Did you mean ...?" for mistyped commands and flags, usage shown with errors
- Shell completion for bash, zsh and fish (`app completion bash`)
- Markdown and man page generation (`app docs markdown|man`)
- Meaningful exit codes, errors on stderr, leak free (tested with `@assert_leak`)

## Quick start

```c3
module hello;

import serp;
import std::io;

fn void? greet(Ctx* ctx)
{
	ctx.println("%s, %s!", ctx.flag_string("greeting"), ctx.arg(0, "world"))!;
}

fn int main(String[] args)
{
	Command* app = serp::app("hello", "1.0.0", "Says hello");
	defer app.free();

	app.add(serp::cmd("greet", "Greet someone", &greet)
		.usage_args("[name]")
		.accepts(serp::max_args(1))
		.flag(serp::string_flag('g', "greeting", "what to say", "Hello")));

	return app.execute(args);   // 0 ok, 1 command failed, 2 bad command line
}
```

```
$ hello greet -g Hi Bob
Hi, Bob!
$ hello gret
Error: unknown command 'gret' for 'hello'

Did you mean this?
  greet
```

Or let the [`serp` tool](#the-serp-tool) create the project and add commands for you.

## Install

Add the folder that *contains* `serp.c3l` to `dependency-search-paths` in your
`project.json`, and add `serp` to the dependencies:

```json
{
    "dependency-search-paths": [ "<folder containing serp.c3l>" ],
    "dependencies": [ "serp" ]
}
```

Then `import serp;` — that is the only import you need.

## The `serp` tool

`serp` scaffolds and grows serp based apps. It is built with serp itself.

```
c3c build serp                    # builds build/serp
build/serp new myapp              # creates ./myapp, installs serp into myapp/lib with c3l
cd myapp
serp add serve build              # add commands
serp add create delete -p repo    # add subcommands: myapp repo create ...
serp list                         # show the command tree
serp remove repo -r               # remove a command and its subcommands
c3c run -- repo create
```

| Command | What it does |
|---|---|
| `new <name>` | New project with a sample `hello` command. Names are lower case letters, digits and `-`. The project uses `lib/` as its dependency folder; if [c3l](https://github.com/konimarti/c3l) is on the PATH, serp is installed there (`HEAD`, pinned in `c3l.lock`). Otherwise (or with `--no-install`) it prints the manual options, including `git submodule add`. `--serp-path` uses a local checkout instead: the folder containing `serp.c3l` or `serp.c3l` itself, relative to the project or absolute. |
| `add <name>...` | One new file per command. `-p "repo sub"` picks the parent, `-d` sets the description. |
| `remove <name>...` (`rm`) | Deletes the command files. A command with subcommands needs `-r`. |
| `list` (`ls`) | Prints the command tree. |

`--dir` selects the folder to work in: the project folder, or for `new` the folder
the project is created in.

**Generated layout**

```
myapp/
  src/main.c3        yours: builds the app with build_app() and runs it
  src/commands.c3    generated, do not edit: registers every command
  src/cmd/serve.c3   one file per command, yours to fill in
```

Each file in `src/cmd/` starts with a `// serp:cmd <path>` line. That line is the only
thing `serp` reads: `add` and `remove` create or delete these files and rewrite
`src/commands.c3` from them, and they never edit your code. Files without the line
are ignored, so you can keep helpers next to the commands.

**Safe by default:** all names are checked before anything is written, so a typo
leaves the project untouched; existing commands are never overwritten; a missing
parent is an error.

## Concepts

### Commands

`serp::app(name, version, desc)` creates the root, `serp::cmd(name, desc, run)`
creates a subcommand. Builders return the command, so they chain:

| Builder | Purpose |
|---|---|
| `.describe(short, long)` | one-line and long description |
| `.add(child)` | attach a subcommand (parent takes ownership) |
| `.flag(Flag)` / `.persistent_flag(Flag)` | add a flag (persistent = inherited) |
| `.aka("alias")` | alternative name |
| `.accepts(ArgSpec)` | validate positional args |
| `.usage_args("<file>...")` | shown in the usage line |
| `.examples("...")` | shown in help |
| `.grouped("Group")` | heading in the parent's command list |
| `.hide()` / `.deprecate("msg")` | hide from help / print a warning |
| `.before(fn)` / `.after(fn)` | hooks around `run` |
| `.before_all(fn)` | hook for the command *and* all its subcommands |

`parent.add_at({"repo"}, child)` adds a child below a nested command.
A command without `run` just shows its help. Freeing the root with `app.free()`
releases the whole tree. Strings are borrowed: use literals or keep them alive.

### Flags

```c3
serp::bool_flag('v', "verbose", "chatty");                 // switch
serp::string_flag('o', "output", "file", "out.txt");       // with default
serp::int_flag('p', "port", "port", "8080");               // validated integer
Flag f = {.name = "host", .kind = STRING, .required = true, .env = "APP_HOST"};  // full control
```

`Flag` fields: `short_name` (any Unicode codepoint, e.g. `'ü'`), `name`, `desc`, `kind` (`BOOL`, `STRING`, `INT`),
`required`, `persistent`, `hidden`, `default_value`, `choices`, `env`,
`value_name`, `bind_bool`, `bind_int`.

`choices` restricts a flag to a list of values (`.choices = {"json", "yaml"}`);
values from the command line, the environment and defaults are all validated.
Bool flags take `--verbose`, `--verbose=false` or `--no-verbose` (not
`--verbose false`).

Read values in the run function through `Ctx`:

```c3
ctx.flag_bool("verbose");  ctx.flag_string("output");  ctx.flag_int("port");
ctx.has("port");           // given explicitly?
ctx.flag_strings("include");   // every value of a repeated flag: -I a -I b
ctx.arg(0, "fallback");    ctx.args;   // positional arguments
```

Lookup order: command line, environment variable (if not empty), default. A flag
given twice keeps the last value; `flag_strings` returns all of them (for a bool
flag `.len` counts `-vvv`). Bindings are only written when the flag has a value.

### Failing

A run function returns a fault to fail (exit code 1, `Error: <fault>` on stderr).
`return ctx.fail("no such file: %s", name);` prints a plain message instead.

### Argument validation

`serp::no_args()`, `any_args()`, `min_args(n)`, `max_args(n)`, `exact_args(n)`,
`range_args(lo, hi)`. A command with subcommands rejects unknown words as
typos unless you set a validator.

### Output and testing

`app.out` / `app.err` redirect output (any `OutStream`, e.g. a `DString*`);
`app.color = NEVER|ALWAYS|AUTO`. `app.execute_line("app serve -p 80")` runs a
string, which makes command trees easy to test — see `src/test/serp_test.c3`.

## Layout

```
src/serp/       the library (manifest.json points here)
examples/demo/  small example app   (c3c run demo -- --help)
tools/serp/     `serp` scaffolder: new, add, remove, list
src/test/       tests               (c3c test)
```
