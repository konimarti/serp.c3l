module serp;

import std::collections::list;
import std::io;
import std::os::env;

// Last occurrence of a flag given on the command line, by long name (or short name as 1 char string).
fn Parsed* Ctx.find(&self, String name)
{
	for (sz i = self.parsed.len() - 1; i >= 0; i--)
	{
		Parsed* p = &self.parsed.entries[i];
		if (p.flag.name == name) return p;
		if (name.len == 1 && p.flag.short_name == name[0]) return p;
	}
	return null;
}

fn Flag* Ctx.definition(&self, String name)
{
	Flag* f = self.cmd.lookup_long(name);
	if (!f && name.len == 1) f = self.cmd.lookup_short(name[0]);
	return f;
}

<*
 The value of a flag from the command line, else its environment variable, else
 its default, else `fallback`. Returns a view valid during the run.
*>
fn String Ctx.flag_string(&self, String name, String fallback = "")
{
	Parsed* p = self.find(name);
	if (p) return p.value;
	Flag* f = self.definition(name);
	if (f)
	{
		if (f.env.len)
		{
			if (try v = env::tget_var(f.env)) return v;
		}
		if (f.default_value.len) return f.default_value;
	}
	return fallback;
}

<*
 True if the flag is on the command line (`--verbose`, `--verbose=true`),
 set through its environment variable, or true by default.
*>
fn bool Ctx.flag_bool(&self, String name)
{
	Parsed* p = self.find(name);
	if (p) return !is_false(p.value);
	Flag* f = self.definition(name);
	if (f)
	{
		if (f.env.len)
		{
			if (try v = env::tget_var(f.env)) return v.len > 0 && !is_false(v);
		}
		return f.default_value.len > 0 && !is_false(f.default_value);
	}
	return false;
}

fn long Ctx.flag_int(&self, String name, long fallback = 0)
{
	String s = self.flag_string(name);
	if (!s.len) return fallback;
	return s.to_long() ?? fallback;
}

// Was the flag given explicitly on the command line?
fn bool Ctx.has(&self, String name) => self.find(name) != null;

// i-th positional argument or `fallback`.
fn String Ctx.arg(&self, sz i, String fallback = "")
{
	return i < self.args.len ? self.args[i] : fallback;
}

fn void? Ctx.print_help(&self) => write_help(self.cmd, self.out, false);

fn void? Ctx.print(&self, String format, args...) @format(1)
{
	io::fprintf(self.out, format, ...args)!;
}

fn void? Ctx.println(&self, String format, args...) @format(1)
{
	io::fprintfn(self.out, format, ...args)!;
}

fn bool is_false(String s) @private
{
	return s == "false" || s == "0" || s == "no" || s == "off";
}
