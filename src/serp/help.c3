module serp;

import std::collections::list;
import std::io;
import std::math;

const String BOLD  = "\e[1m";
const String RESET = "\e[0m";

<*
 Write the help text of `c`: description, usage, aliases, examples,
 available commands (grouped), flags and inherited flags.
*>
fn void? write_help(Command* c, OutStream out, bool color) => @pool()
{
	String b = color ? BOLD : "";
	String r = color ? RESET : "";

	String text = c.long_desc.len ? c.long_desc : c.desc;
	if (text.len) io::fprintfn(out, "%s\n", text)!;

	write_usage(c, out, color)!;

	if (c.aliases.len() > 0)
	{
		io::fprintfn(out, "\n%sAliases:%s", b, r)!;
		io::fprintf(out, "  %s", c.name)!;
		foreach (a : c.aliases) io::fprintf(out, ", %s", a)!;
		io::fprintn(out, "")!;
	}

	if (c.example.len) io::fprintfn(out, "\n%sExamples:%s\n%s", b, r, c.example)!;

	// commands, in groups (ungrouped first)
	sz commands = visible_child_count(c);
	if (commands > 0)
	{
		sz width = 0;
		foreach (child : c.children) if (!child.hidden) width = math::max(width, child.name.len);

		List {String} groups;
		groups.tinit(4);
		groups.push("");
		foreach (child : c.children)
		{
			if (!child.hidden && !groups.contains(child.group)) groups.push(child.group);
		}
		foreach (g : groups)
		{
			bool found;
			foreach (child : c.children)
			{
				if (child.hidden || child.group != g) continue;
				if (!found)
				{
					found = true;
					io::fprintfn(out, "\n%s%s Commands:%s", b, g.len ? g : "Available", r)!;
				}
				io::fprintfn(out, "  %-*s   %s", (int)width, child.name, child.desc)!;
			}
		}
	}

	write_flag_section(c, out, false, "Flags", b, r)!;
	write_flag_section(c, out, true, "Global Flags", b, r)!;

	if (commands > 0)
	{
		io::fprint(out, "\nUse \"")!;
		c.write_path(out)!;
		io::fprintn(out, " [command] --help\" for more information about a command.")!;
	}
}

// The "Usage:" heading and its lines.
fn void? write_usage(Command* c, OutStream out, bool color)
{
	io::fprintfn(out, "%sUsage:%s", color ? BOLD : "", color ? RESET : "")!;
	if (c.run || c.children.len() == 0)
	{
		io::fprint(out, "  ")!;
		c.write_path(out)!;
		if (visible_flag_count(c) > 0) io::fprint(out, " [flags]")!;
		if (c.args_usage.len) io::fprintf(out, " %s", c.args_usage)!;
		io::fprintn(out, "")!;
	}
	if (visible_child_count(c) > 0)
	{
		io::fprint(out, "  ")!;
		c.write_path(out)!;
		io::fprintn(out, " [command]")!;
	}
}

fn void? write_flag_section(Command* c, OutStream out, bool inherited_section, String title, String b, String r) @private
{
	// the built-in flags, unless the user defined their own
	Flag help = {.short_name = c.lookup_short('h') ? 0 : 'h', .name = "help", .desc = "help for this command"};
	Flag version = {.name = "version", .desc = "version for this program"};
	List {Flag*} flags;
	flags.tinit(8);
	if (!inherited_section)
	{
		if (!c.lookup_long("help")) flags.push(&help);
		if (c.parent == null && c.version.len && !c.lookup_long("version")) flags.push(&version);
	}
	c.@each_flag(; Flag* f, bool inherited)
	{
		if (!f.hidden && inherited == inherited_section) flags.push(f);
	};
	if (flags.is_empty()) return;

	// align the descriptions
	sz width;
	foreach (f : flags) width = math::max(width, flag_label(f).len);
	io::fprintfn(out, "\n%s%s:%s", b, title, r)!;
	foreach (f : flags)
	{
		io::fprintf(out, "  %-*s   %s", (int)width, flag_label(f), f.desc)!;
		if (f.default_value.len && f.kind != BOOL) io::fprintf(out, " (default %s)", f.default_value)!;
		if (f.choices.len)
		{
			io::fprint(out, " (")!;
			foreach (i, choice : f.choices)
			{
				if (i) io::fprint(out, "|")!;
				io::fprint(out, choice)!;
			}
			io::fprint(out, ")")!;
		}
		if (f.env.len) io::fprintf(out, " [$%s]", f.env)!;
		if (f.required) io::fprint(out, " (required)")!;
		io::fprintn(out, "")!;
	}
}

// e.g. `-p, --port int`
fn String flag_label(Flag* f) @private
{
	DString s = dstring::temp();
	if (f.short_name) s.appendf("-%c", f.short_name)!!;
	if (f.short_name && f.name.len)
	{
		s.append_string(", ");
	}
	else if (f.name.len)
	{
		s.append_string("    ");
	}
	if (f.name.len) s.appendf("--%s", f.name)!!;
	if (f.kind != BOOL)
	{
		String vn = f.value_name;
		if (!vn.len) vn = f.kind == INT ? "int" : "string";
		s.appendf(" %s", vn)!!;
	}
	return s.str_view();
}

fn sz visible_child_count(Command* c) @private
{
	sz n;
	foreach (child : c.children) if (!child.hidden) n++;
	return n;
}

fn sz visible_flag_count(Command* c) @private
{
	sz n;
	c.@each_flag(; Flag* f, bool inherited) { if (!f.hidden) n++; };
	return n;
}
