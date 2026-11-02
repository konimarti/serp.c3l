module serp;

import std::collections::list;
import std::io;
import std::os::env;

// The flag called `name` (long name, or a short name given as 1 char string) visible to the running command.
fn Flag* Ctx.definition(&self, String name)
{
	Flag* f = self.cmd.lookup_long(name);
	if (!f && name.len == 1) f = self.cmd.lookup_short(name[0]);
	return f;
}

// Last occurrence of the flag on the command line.
fn Parsed* find_parsed(Ctx* self, Flag* f) @private
{
	for (sz i = self.parsed.len() - 1; i >= 0; i--)
	{
		if (self.parsed.entries[i].flag == f) return &self.parsed.entries[i];
	}
	return null;
}

// Value of the environment variable of the flag; empty if unset or empty.
fn String env_value(Flag* f) @private
{
	if (!f.env.len) return "";
	return env::tget_var(f.env) ?? "";
}

// Does the flag have a value: given, in its environment variable, or defaulted?
fn bool flag_is_set(Ctx* self, Flag* f) @private
{
	return find_parsed(self, f) != null || env_value(f).len > 0 || f.default_value.len > 0;
}

// Command line value, else environment variable, else default (empty if none).
fn String flag_value(Ctx* self, Flag* f) @private
{
	Parsed* p = find_parsed(self, f);
	if (p) return p.value;
	String v = env_value(f);
	return v.len ? v : f.default_value;
}

<*
 The value of a flag from the command line, else its environment variable, else
 its default, else `fallback`. Returns a view valid during the run.
*>
fn String Ctx.flag_string(&self, String name, String fallback = "")
{
	Flag* f = self.definition(name);
	return f && flag_is_set(self, f) ? flag_value(self, f) : fallback;
}

<*
 Every value given on the command line for the flag, in order (`-I a -I b`).
 For a bool flag it holds one entry per occurrence, so `.len` counts `-vvv`.
 Returns a view valid during the run.
*>
fn String[] Ctx.flag_strings(&self, String name)
{
	List {String} values;
	values.tinit(4);
	Flag* f = self.definition(name);
	if (f) foreach (&p : self.parsed) if (p.flag == f) values.push(p.value);
	return values.array_view();
}

<*
 True if the flag is on the command line (`--verbose`, `--verbose=true`),
 set through its environment variable, or true by default.
*>
fn bool Ctx.flag_bool(&self, String name)
{
	Flag* f = self.definition(name);
	return f && flag_truthy(self, f);
}

fn bool flag_truthy(Ctx* self, Flag* f) @private
{
	Parsed* p = find_parsed(self, f);
	if (p) return !is_false(p.value);
	String v = flag_value(self, f);
	return v.len > 0 && !is_false(v);
}

fn long Ctx.flag_int(&self, String name, long fallback = 0)
{
	String s = self.flag_string(name);
	if (!s.len) return fallback;
	return s.to_long() ?? fallback;
}

// Was the flag given explicitly on the command line?
fn bool Ctx.has(&self, String name)
{
	Flag* f = self.definition(name);
	return f && find_parsed(self, f) != null;
}

// i-th positional argument or `fallback`.
fn String Ctx.arg(&self, sz i, String fallback = "")
{
	return i < self.args.len ? self.args[i] : fallback;
}

fn void? Ctx.print_help(&self) => write_help(self.cmd, self.out, self.color);

fn void? Ctx.print(&self, String format, args...) @format(1)
{
	io::fprintf(self.out, format, ...args)!;
}

fn void? Ctx.println(&self, String format, args...) @format(1)
{
	io::fprintfn(self.out, format, ...args)!;
}

fn bool is_false(String s) @private => s == "false" || s == "0" || s == "no" || s == "off";
fn bool is_true(String s) @private => s == "true" || s == "1" || s == "yes" || s == "on";
