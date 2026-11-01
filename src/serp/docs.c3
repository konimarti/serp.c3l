module serp;

import std::io;

// ---- markdown ----

<*
 Write reference documentation for the whole command tree as markdown.
*>
fn void? write_markdown(Command* c, OutStream out) => @pool()
{
	io::fprint(out, "## ")!;
	c.write_path(out)!;
	io::fprintn(out, "\n")!;
	String text = c.long_desc.len ? c.long_desc : c.desc;
	if (text.len) io::fprintfn(out, "%s\n", text)!;

	io::fprintn(out, "```\n")!;
	write_help_plain(c, out)!;
	io::fprintn(out, "```\n")!;

	if (c.parent)
	{
		io::fprint(out, "Parent: `")!;
		c.parent.write_path(out)!;
		io::fprintn(out, "`\n")!;
	}
	foreach (child : c.children)
	{
		if (!child.hidden) write_markdown(child, out)!;
	}
}

// ---- man page (roff) ----

fn void? write_man(Command* root, OutStream out) => @pool()
{
	String name = root.name;
	io::fprintfn(out, ".TH \"%s\" 1 \"\" \"%s\"", name.to_upper_tcopy(), root.version)!;
	io::fprintn(out, ".SH NAME")!;
	io::fprintfn(out, "%s \\- %s", name, roff(root.desc))!;
	io::fprintn(out, ".SH SYNOPSIS")!;
	io::fprintfn(out, ".B %s", name)!;
	io::fprintn(out, "[command] [flags]")!;
	if (root.long_desc.len || root.desc.len)
	{
		io::fprintn(out, ".SH DESCRIPTION")!;
		io::fprintn(out, roff(root.long_desc.len ? root.long_desc : root.desc))!;
	}
	io::fprintn(out, ".SH COMMANDS")!;
	man_command(root, out)!;
}

fn void? man_command(Command* c, OutStream out) @local
{
	io::fprint(out, ".SS ")!;
	c.write_path(out)!;
	io::fprintn(out, "")!;
	if (c.desc.len) io::fprintfn(out, "%s", roff(c.desc))!;
	c.@each_flag(; Flag* f, bool inherited)
	{
		if (!f.hidden && !inherited)
		{
			io::fprintn(out, ".TP")!!;
			io::fprint(out, ".B ")!!;
			if (f.short_name) io::fprintf(out, "\\-%c", f.short_name)!!;
			if (f.short_name && f.name.len) io::fprint(out, ", ")!!;
			if (f.name.len) io::fprintf(out, "\\-\\-%s", f.name)!!;
			io::fprintn(out, "")!!;
			io::fprintn(out, roff(f.desc))!!;
		}
	};
	foreach (child : c.children)
	{
		if (!child.hidden) man_command(child, out)!;
	}
}

fn String roff(String s) @local => s.treplace("-", "\\-");

// help text without ANSI codes (always plain)
fn void? write_help_plain(Command* c, OutStream out) @local => write_help(c, out, false);
