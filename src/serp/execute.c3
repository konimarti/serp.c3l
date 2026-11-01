module serp;

import std::collections::list;
import std::io;
import std::os::env;

<*
 Parse the command line, find the subcommand and run it.

 Typical use: `return app.execute(args);` from `fn int main(String[] args)`.
 `args[0]` is the program name, as passed to `main`.

 Handles `-h/--help`, `--version`, unknown commands/flags, required flags,
 argument validation and the hooks. Errors are printed to stderr.

 @return "0 on success, 1 if a command failed, 2 for a bad command line"
*>
fn int Command.execute(&self, String[] args) => @pool()
{
	assert(self.parent == null, "execute() must be called on the root command");
	self.prepare();

	OutStream out = io::stdout();
	OutStream err = io::stderr();
	if (self.out) out = self.out;
	if (self.err) err = self.err;
	bool color = self.use_color();

	Ctx ctx = {.cmd = self, .out = out, .err = err};
	ctx.parsed.tinit(8);
	List {String} pos;
	pos.tinit(8);

	Command* cur = self;
	bool only_pos;
	bool want_help;
	bool want_version;

	for (sz i = 1; i < args.len; i++)
	{
		String a = args[i];

		// positional argument or subcommand
		if (only_pos || a.len < 2 || a[0] != '-')
		{
			if (!only_pos && pos.is_empty())
			{
				Command* sub = cur.find_child(a);
				if (sub)
				{
					cur = sub;
					continue;
				}
			}
			pos.push(a);
			continue;
		}

		if (a == "--")
		{
			only_pos = true;
			continue;
		}

		if (a[1] == '-')
		{
			// --long, --long=value, --long value
			String name = a[2..];
			String value;
			bool has_value;
			if (try eq = name.index_of_char('='))
			{
				value = name[eq + 1..];
				name = name[:eq];
				has_value = true;
			}
			Flag* f = cur.lookup_long(name);
			if (!f)
			{
				if (name == "help") { want_help = true; continue; }
				if (name == "version" && self.version.len) { want_version = true; continue; }
				return unknown_flag(cur, err, color, string::tformat("--%s", name), flag_suggestion(cur, name));
			}
			if (f.kind == BOOL)
			{
				if (has_value && !is_bool_text(value))
				{
					return usage_error(cur, err, color, "flag --%s takes no value (got '%s')", name, value);
				}
			}
			else if (!has_value)
			{
				if (i + 1 >= args.len) return usage_error(cur, err, color, "flag --%s needs a value", name);
				value = args[++i];
			}
			if (!store(&ctx, f, value, cur, err, color)) return EXIT_USAGE;
			continue;
		}

		// -a, -abc (cluster), -pVALUE, -p VALUE, -p=VALUE
		String cluster = a[1..];
		for (sz j = 0; j < cluster.len; j++)
		{
			char ch = cluster[j];
			Flag* f = cur.lookup_short(ch);
			if (!f)
			{
				if (ch == 'h') { want_help = true; continue; }
				return unknown_flag(cur, err, color, string::tformat("-%c", ch), "");
			}
			if (f.kind == BOOL)
			{
				ctx.parsed.push({f, ""});
				continue;
			}
			String value;
			String rest = cluster[j + 1..];
			if (rest.len)
			{
				value = rest[0] == '=' ? rest[1..] : rest;
			}
			else if (i + 1 < args.len)
			{
				value = args[++i];
			}
			else
			{
				return usage_error(cur, err, color, "flag -%c needs a value", ch);
			}
			if (!store(&ctx, f, value, cur, err, color)) return EXIT_USAGE;
			break;
		}
	}

	ctx.cmd = cur;
	ctx.args = pos.array_view();

	if (want_help)
	{
		if (catch write_help(cur, out, color)) return EXIT_ERROR;
		return EXIT_OK;
	}
	if (want_version)
	{
		if (catch io::fprintfn(out, "%s version %s", self.name, self.version)) return EXIT_ERROR;
		return EXIT_OK;
	}

	// a command with subcommands treats a leftover word as a typo
	if (cur.children.len() > 0 && pos.len() > 0 && (!cur.run || cur.args.kind == DEFAULT))
	{
		String sug = command_suggestion(cur, pos[0]);
		String path = cur.path_string();
		if (sug.len)
		{
			return usage_error(cur, err, color, "unknown command '%s' for '%s'\n\nDid you mean this?\n  %s", pos[0], path, sug);
		}
		return usage_error(cur, err, color, "unknown command '%s' for '%s'", pos[0], path);
	}

	// nothing to run: show the help instead
	if (!cur.run)
	{
		if (catch write_help(cur, out, color)) return EXIT_ERROR;
		return EXIT_OK;
	}

	if (!check_args(cur, pos.len(), err, color)) return EXIT_USAGE;
	if (!check_required(&ctx, cur, err, color)) return EXIT_USAGE;
	apply_bindings(&ctx, cur);

	if (cur.deprecated.len)
	{
		io::fprintfn(err, "Command '%s' is deprecated: %s", cur.path_string(), cur.deprecated)!!;
	}

	if (catch e = run_hooks(&ctx, cur))
	{
		io::fprintfn(err, "%sError:%s %s", color ? "\e[1;31m" : "", color ? "\e[0m" : "", e)!!;
		return EXIT_ERROR;
	}
	return EXIT_OK;
}

<*
 Convenience for tests and tools: split `line` on spaces and execute it.
 The first word is the program name.
*>
fn int Command.execute_line(&self, String line) => @pool()
{
	return self.execute(line.tsplit(" ", skip_empty: true));
}

// ---- internals ----

fn void? run_hooks(Ctx* ctx, Command* cur) @private
{
	// persistent pre-run hooks, outermost first
	Command*[16] chain;
	sz n;
	for (Command* c = cur; c && n < chain.len; c = c.parent) chain[n++] = c;
	for (sz i = n - 1; i >= 0; i--)
	{
		if (chain[i].persistent_pre_run) chain[i].persistent_pre_run(ctx)!;
	}
	if (cur.pre_run) cur.pre_run(ctx)!;
	cur.run(ctx)!;
	if (cur.post_run) cur.post_run(ctx)!;
}

fn bool is_bool_text(String s) @private
	=> s == "true" || s == "false" || s == "1" || s == "0" || s == "yes" || s == "no" || s == "on" || s == "off";

fn bool store(Ctx* ctx, Flag* f, String value, Command* cur, OutStream err, bool color) @private
{
	if (f.kind == INT)
	{
		if (catch value.to_long())
		{
			usage_error(cur, err, color, "invalid value '%s' for %s: expected an integer", value, flag_display(f));
			return false;
		}
	}
	ctx.parsed.push({f, value});
	return true;
}

fn bool check_args(Command* cur, sz n, OutStream err, bool color) @private
{
	ArgSpec s = cur.args;
	String problem;
	switch (s.kind)
	{
		case DEFAULT:
		case ANY: return true;
		case NONE: if (n > 0) problem = string::tformat("accepts no arguments, received %d", n);
		case MIN: if (n < s.min) problem = string::tformat("requires at least %d arg(s), received %d", s.min, n);
		case MAX: if (n > s.max) problem = string::tformat("accepts at most %d arg(s), received %d", s.max, n);
		case EXACT: if (n != s.min) problem = string::tformat("accepts %d arg(s), received %d", s.min, n);
		case RANGE: if (n < s.min || n > s.max) problem = string::tformat("accepts between %d and %d arg(s), received %d", s.min, s.max, n);
	}
	if (!problem.len) return true;
	usage_error(cur, err, color, "%s", problem);
	return false;
}

fn bool check_required(Ctx* ctx, Command* cur, OutStream err, bool color) @private
{
	bool ok = true;
	cur.@each_flag(; Flag* f, bool inherited)
	{
		if (ok && f.required && !ctx.is_set(f))
		{
			usage_error(cur, err, color, "required flag %s not set", flag_display(f));
			ok = false;
		}
	};
	return ok;
}

fn void apply_bindings(Ctx* ctx, Command* cur) @private
{
	cur.@each_flag(; Flag* f, bool inherited)
	{
		String key = flag_key(f);
		if (f.bind_bool) *f.bind_bool = ctx.flag_bool(key);
		if (f.bind_int) *f.bind_int = ctx.flag_int(key);
	};
}

fn int usage_error(Command* cur, OutStream err, bool color, String format, args...) @private
{
	io::fprintf(err, "%sError:%s ", color ? "\e[1;31m" : "", color ? "\e[0m" : "")!!;
	io::fprintf(err, format, ...args)!!;
	io::fprint(err, "\nRun '")!!;
	cur.write_path(err)!!;
	io::fprintn(err, " --help' for usage.")!!;
	return EXIT_USAGE;
}

fn int unknown_flag(Command* cur, OutStream err, bool color, String shown, String suggestion) @private
{
	if (suggestion.len) return usage_error(cur, err, color, "unknown flag: %s\n\nDid you mean this?\n  --%s", shown, suggestion);
	return usage_error(cur, err, color, "unknown flag: %s", shown);
}

// Is this flag present on the command line, in the environment, or defaulted?
fn bool Ctx.is_set(&self, Flag* f)
{
	foreach (p : self.parsed) if (p.flag == f) return true;
	if (f.env.len) { if (try env::tget_var(f.env)) return true; }
	return f.default_value.len > 0;
}

fn String flag_key(Flag* f) @private
{
	if (f.name.len) return f.name;
	return (String)((char*)&f.short_name)[:1];
}

fn String flag_display(Flag* f) @private
{
	if (f.name.len) return string::tformat("--%s", f.name);
	return string::tformat("-%c", f.short_name);
}

fn String Command.path_string(&self)
{
	DString s = dstring::temp();
	self.write_path(&s)!!;
	return s.str_view();
}

fn bool Command.use_color(&self)
{
	switch (self.color)
	{
		case ALWAYS: return true;
		case NEVER: return false;
		case AUTO:
			if (self.err || self.out) return false;
			if (try env::tget_var("NO_COLOR")) return false;
			return io::stdout().isatty();
	}
}
