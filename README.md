```
 ___  ___ _ __ _ __
/ __|/ _ \ '__| '_ \
\__ \  __/ |  | |_) |
|___/\___|_|  | .__/
              |_|
```

# A Commander for C3 CLI applications

Serp is a library for creating powerful modern CLI applications in C3.
Inspired by [cobra](http://github.com/spf13/cobra).


## Overview

Serp provides:
- Easy subcommand-based CLIs: `app serve`, `app fetch`, etc.
- Fully POSIX-compliant flags (including short and long versions)
- Nested subcommands
- Automatic help generation for commands and flags

In the works:
- Automatic help flag recognition of `-h`, `--help` (TODO)
- Command aliases so you can change things without breaking them


## Concepts

Serp is built on a structure of commands and flags - heavely inspired by
[cobra](http://github.com/spf13/cobra).

*Commands* represent actions and *flags* are modifiers for those actions.

Well-designed CLI apps follow a certain usage pattern; the commands should 
read like sentences: `app verb noun` or `app command argument
--flags`.


### Commands

Command is the central point of the application.
A command can have children commands an optionally run an action.

Create a command with `command::new`:

```cpp
import serp::command;

Command root = command::new(
    use: "app",
    run: fn void!(String[] args, Option[] opts) {
        io::printn("hello app");
    }
);

```

To add subcommands, use the `Command.add_command(Command*)` function:

```cpp
root.add_command(
    command::new(
        use: "init",
        run: fn void!(String[] args, Option[] opts) {
            io::printn("app init");
        }
    )
);

```

### Flags

A flag is a way to modify the behavior of a command. POSIX-compliant flags are
supported.

Flags can be defined per command with `Command.add_flag(Flag)`:

```cpp
root.add_flag({.shortopt = 'p', .longopt = 'path', .optarg = true});
```
The above example will set a flag on the root command that expects an optional
argument. The flag can then be set with `-p` or `--path` on the command line.

The parameter to the `add_flag` function is a `struct Flag` that
contains the following fields:
```cpp
struct Flag {
        char    shortopt; // short option name, e.g. 'p'
        String  longopt;  // long option name, e.g. "path"
        bool    optarg;   // set true if flag has an optional argument
        String  desc;     // describe the purpose of the flag
}

```

## Examples

```cpp
```

## Install

Add the path to the `serp.c3l` folder to `dependency-search-paths` and
`getopt` to `dependencies` in your `project.json` file:

```json
{
    "dependency-search-paths": ["lib", "<path_to_getopt.c3l_folder>"],
    "dependencies": ["serp"]
}
```
