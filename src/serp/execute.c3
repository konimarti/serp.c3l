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

	Ctx ctx = {
		.cmd = self,
		.out = out,
		.err = err,
		.color = color_for(self, false),
		.err_color = color_for(self, true),
	};
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
					ctx.cmd = sub;
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
			// --long, --long=value, --long value, --no-long
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
			if (!f && !has_value && name.starts_with("no-"))
			{
				Flag* positive = cur.lookup_long(name[3..]);
				if (positive && positive.kind == BOOL)
				{
					ctx.parsed.push({positive, "false"});
					continue;
				}
			}
			if (!f)
			{
				if (name == "help") { want_help = true; continue; }
				if (name == "version" && self.version.len) { want_version = true; continue; }
				return unknown_flag(&ctx, string::tformat("--%s", name), flag_suggestion(cur, name));
			}
			if (f.kind == BOOL)
			{
				if (has_value && !(is_true(value) || is_false(value)))
				{
					return usage_error(&ctx, "flag --%s takes no value (got '%s')", name, value);
				}
			}
			else if (!has_value)
			{
				if (i + 1 >= args.len) return usage_error(&ctx, "flag --%s needs a value", name);
				value = args[++i];
			}
			if (!store(&ctx, f, value)) return EXIT_USAGE;
			continue;
		}

		// -a, -abc (cluster), -pVALUE, -p VALUE, -p=VALUE
		String cluster = a[1..];
		for (sz j = 0; j < cluster.len;)
		{
			sz size;
			Char32 ch = first_char(cluster[j..], &size);
			String shown = cluster[j:size];
			j += size;
			Flag* f = cur.lookup_short(ch);
			if (!f)
			{
				if (ch == 'h') { want_help = true; continue; }
				return unknown_flag(&ctx, string::tformat("-%s", shown), "");
			}
			if (f.kind == BOOL)
			{
				ctx.parsed.push({f, ""});
				continue;
			}
			String value;
			String rest = cluster[j..];
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
				return usage_error(&ctx, "flag -%s needs a value", shown);
			}
			if (!store(&ctx, f, value)) return EXIT_USAGE;
			break;
		}
	}

	ctx.args = pos.array_view();

	if (want_help)
	{
		if (catch write_help(cur, ctx.out, ctx.color)) return EXIT_ERROR;
		return EXIT_OK;
	}
	if (want_version)
	{
		if (catch io::fprintfn(ctx.out, "%s version %s", self.name, self.version)) return EXIT_ERROR;
		return EXIT_OK;
	}

	// a command with subcommands treats a leftover word as a typo
	if (cur.children.len() > 0 && pos.len() > 0 && (!cur.run || cur.args.kind == DEFAULT))
	{
		String sug = command_suggestion(cur, pos[0]);
		String path = path_of(cur);
		if (sug.len)
		{
			return usage_error(&ctx, "unknown command '%s' for '%s'\n\nDid you mean this?\n  %s", pos[0], path, sug);
		}
		return usage_error(&ctx, "unknown command '%s' for '%s'", pos[0], path);
	}

	// nothing to run: show the help instead
	if (!cur.run)
	{
		if (catch write_help(cur, ctx.out, ctx.color)) return EXIT_ERROR;
		return EXIT_OK;
	}

	if (!check_args(&ctx)) return EXIT_USAGE;
	if (!check_flags(&ctx)) return EXIT_USAGE;
	apply_bindings(&ctx);

	// failing to write a notice must not abort the program
	if (cur.deprecated.len)
	{
		(void)io::fprintfn(ctx.err, "Command '%s' is deprecated: %s", path_of(cur), cur.deprecated);
	}

	if (catch e = run_hooks(&ctx, cur))
	{
		if (e != FAILED) (void)print_error(&ctx, "%s", e);
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

// persistent pre-run hooks, outermost first
fn void? run_persistent(Ctx* ctx, Command* c) @private
{
	if (c.parent) run_persistent(ctx, c.parent)!;
	if (c.persistent_pre_run) c.persistent_pre_run(ctx)!;
}

fn void? run_hooks(Ctx* ctx, Command* cur) @private
{
	run_persistent(ctx, cur)!;
	if (cur.pre_run) cur.pre_run(ctx)!;
	cur.run(ctx)!;
	if (cur.post_run) cur.post_run(ctx)!;
}

// Empty if `v` is acceptable for the flag, else what is wrong with it.
fn String value_problem(Flag* f, String v) @private
{
	if (f.kind == BOOL) return "";
	if (f.kind == INT)
	{
		if (catch v.to_long()) return "expected an integer";
	}
	if (f.choices.len)
	{
		DString s = dstring::temp();
		s.append_string("expected one of: ");
		foreach (i, c : f.choices)
		{
			if (v == c) return "";
			if (i) s.append_string(", ");
			s.append_string(c);
		}
		return s.str_view();
	}
	return "";
}

fn bool store(Ctx* ctx, Flag* f, String value) @private
{
	String problem = value_problem(f, value);
	if (problem.len)
	{
		usage_error(ctx, "invalid value '%s' for %s: %s", value, flag_display(f), problem);
		return false;
	}
	ctx.parsed.push({f, value});
	return true;
}

fn bool check_args(Ctx* ctx) @private
{
	ArgSpec s = ctx.cmd.args;
	sz n = ctx.args.len;
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
	usage_error(ctx, "%s", problem);
	return false;
}

// Required flags are set, and values from the environment or defaults are valid.
fn bool check_flags(Ctx* ctx) @private
{
	bool ok = true;
	ctx.cmd.@each_flag(; Flag* f, bool inherited)
	{
		if (ok)
		{
			String v = flag_value(ctx, f);
			String problem = v.len ? value_problem(f, v) : "";
			if (problem.len)
			{
				usage_error(ctx, "invalid value '%s' for %s: %s", v, flag_display(f), problem);
				ok = false;
			}
			else if (f.required && !flag_is_set(ctx, f))
			{
				usage_error(ctx, "required flag %s not set", flag_display(f));
				ok = false;
			}
		}
	};
	return ok;
}

fn void apply_bindings(Ctx* ctx) @private
{
	ctx.cmd.@each_flag(; Flag* f, bool inherited)
	{
		if (flag_is_set(ctx, f))
		{
			if (f.bind_bool) *f.bind_bool = flag_truthy(ctx, f);
			if (f.bind_int) *f.bind_int = flag_value(ctx, f).to_long() ?? 0;
		}
	};
}

fn void? print_error(Ctx* ctx, String format, args...) @private
{
	io::fprintf(ctx.err, "%sError:%s ", ctx.err_color ? "\e[1;31m" : "", ctx.err_color ? RESET : "")!;
	io::fprintfn(ctx.err, format, ...args)!;
}

// The message, the usage of the command and a pointer to its help.
fn void? write_usage_error(Ctx* ctx, String format, args...) @private
{
	print_error(ctx, format, ...args)!;
	io::fprintn(ctx.err, "")!;
	write_usage(ctx.cmd, ctx.err, ctx.err_color)!;
	io::fprint(ctx.err, "\nRun '")!;
	ctx.cmd.write_path(ctx.err)!;
	io::fprintn(ctx.err, " --help' for more information.")!;
}

fn int usage_error(Ctx* ctx, String format, args...) @private
{
	(void)write_usage_error(ctx, format, ...args);
	return EXIT_USAGE;
}

fn int unknown_flag(Ctx* ctx, String shown, String suggestion) @private
{
	if (suggestion.len) return usage_error(ctx, "unknown flag: %s\n\nDid you mean this?\n  --%s", shown, suggestion);
	return usage_error(ctx, "unknown flag: %s", shown);
}

fn String flag_display(Flag* f) @private
{
	if (f.name.len) return string::tformat("--%s", f.name);
	return string::tformat("-%s", char_text(f.short_name));
}

// Temp string; only valid inside a `@pool`.
fn String path_of(Command* self) @private
{
	DString s = dstring::temp();
	self.write_path(&s)!!;
	return s.str_view();
}

fn bool color_for(Command* self, bool for_err) @private
{
	switch (self.color)
	{
		case ALWAYS: return true;
		case NEVER: return false;
		case AUTO:
			// redirected output is never colored
			if (for_err ? self.err != null : self.out != null) return false;
			if (try v = env::tget_var("NO_COLOR")) { if (v.len) return false; }
			return for_err ? io::stderr().isatty() : io::stdout().isatty();
	}
}
