module serp;

import std::collections::list;
import std::io;

faultdef
	UNKNOWN_FLAG,
	UNKNOWN_COMMAND,
	MISSING_VALUE,
	UNEXPECTED_VALUE,
	INVALID_VALUE,
	REQUIRED_FLAG,
	INVALID_ARGS;

// Exit codes returned by `Command.execute`.
const int EXIT_OK    = 0;
const int EXIT_ERROR = 1; // the command itself failed
const int EXIT_USAGE = 2; // bad command line

<*
 A function that implements a command (also used for the hooks).
 The `Ctx` gives access to the positional arguments and the parsed flags.
*>
alias RunFn = fn void?(Ctx* ctx);

enum FlagKind : char
{
	BOOL,   // switch, takes no value: `--verbose`
	STRING, // `--name foo`, `--name=foo`, `-nfoo`
	INT,    // like STRING but validated as an integer
}

<*
 Describes a flag. All strings must outlive the command (use literals).

 `{.short_name = 'p', .name = "port", .kind = INT, .default_value = "8080"}`
*>
struct Flag
{
	char     short_name;    // `-p`
	String   name;          // `--port`
	String   desc;          // help text
	FlagKind kind;          // BOOL by default
	bool     required;      // error out if not supplied
	bool     persistent;    // also valid in every subcommand
	bool     hidden;        // do not list in help
	String   default_value; // used if the flag was not given
	String   env;           // environment variable used as fallback
	String   value_name;    // placeholder in help, default "string"/"int"
	// Optional bindings, written when the flag is present (after parsing).
	bool*    bind_bool;
	long*    bind_int;
}

// A flag as it was found on the command line.
struct Parsed
{
	Flag*  flag;
	String value;
}

enum ArgKind : char
{
	DEFAULT, // any number of args, but unknown subcommands are an error
	NONE,
	ANY,
	MIN,
	MAX,
	EXACT,
	RANGE,
}

<*
 Positional argument validator, see `no_args`, `any_args`, `min_args`,
 `max_args`, `exact_args` and `range_args`.
*>
struct ArgSpec
{
	ArgKind kind;
	sz      min;
	sz      max;
}

fn ArgSpec no_args()                 => {.kind = NONE};
fn ArgSpec any_args()                => {.kind = ANY};
fn ArgSpec min_args(sz n)            => {.kind = MIN, .min = n};
fn ArgSpec max_args(sz n)            => {.kind = MAX, .max = n};
fn ArgSpec exact_args(sz n)          => {.kind = EXACT, .min = n, .max = n};
fn ArgSpec range_args(sz lo, sz hi)  => {.kind = RANGE, .min = lo, .max = hi};

// Shorthand constructors for the common flag types.
fn Flag bool_flag(char short_name, String name, String desc = "")
	=> {.short_name = short_name, .name = name, .desc = desc};
fn Flag string_flag(char short_name, String name, String desc = "", String default_value = "")
	=> {.short_name = short_name, .name = name, .desc = desc, .kind = STRING, .default_value = default_value};
fn Flag int_flag(char short_name, String name, String desc = "", String default_value = "")
	=> {.short_name = short_name, .name = name, .desc = desc, .kind = INT, .default_value = default_value};

<*
 A command or sub command. Create with `serp::app` / `serp::cmd`; the root
 command owns the whole tree, so one `root.free()` releases everything.
 All strings are borrowed and must outlive the command.
*>
struct Command
{
	String   name;
	String   desc;       // one line, shown in the parent's command list
	String   long_desc;  // shown in `--help`; falls back to `desc`
	String   example;    // free-form, may span several lines
	String   args_usage; // e.g. "<file>..." shown in the usage line
	String   group;      // heading used in the parent's command list
	String   deprecated; // non-empty: message printed when the command is used
	String   version;    // root only: enables `--version`
	bool     hidden;
	bool     no_completion; // root only: do not add `completion`
	ArgSpec  args;
	RunFn    run;
	RunFn    pre_run;
	RunFn    post_run;
	RunFn    persistent_pre_run; // runs for this command and all its subcommands
	// Root only: output redirection (null means stdout/stderr) and color.
	OutStream out;
	OutStream err;
	ColorMode color;

	Command* parent;
	List {Flag}     flags;
	List {Command*} children;
	List {String}   aliases;
	Allocator       allocator;
	bool            prepared;
}

enum ColorMode : char
{
	AUTO,   // only when writing to a terminal and NO_COLOR is unset
	ALWAYS,
	NEVER,
}

// Passed to every run function.
struct Ctx
{
	Command*      cmd;
	String[]      args;   // positional arguments
	List {Parsed} parsed; // temp allocated, valid during the run
	OutStream     out;
	OutStream     err;
}
