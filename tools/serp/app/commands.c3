module serp_tool;

import serp;
import std::collections::list;
import std::io::file;
import std::io::path;

fn void? add_commands(Ctx* ctx) => @pool()
{
	Project p;
	p.open(ctx, ctx.flag_string("dir"))!;
	String[] parent = split_path(ctx.flag_string("parent"));
	if (parent.len && !p.find(join(parent, " ")))
	{
		return ctx.fail("parent command '%s' not found (see `serp list`)", join(parent, " "));
	}
	String desc = ctx.flag_string("desc");
	if (desc.contains("\"") || desc.contains("\\") || desc.contains("\n"))
	{
		return ctx.fail("the description must not contain quotes, backslashes or newlines");
	}

	// check everything first so that a bad name does not leave half the commands behind
	Entry[] added = mem::talloc_array(Entry, ctx.args.len);
	foreach (i, name : ctx.args)
	{
		if (!valid_name(name))
		{
			return ctx.fail("invalid command name '%s': use lower case letters, digits and single dashes, starting with a letter", name);
		}
		String[] path = mem::talloc_array(String, parent.len + 1);
		path[:parent.len] = parent[..];
		path[parent.len] = name;
		added[i] = make_entry(path);
		if (p.find(added[i].key)) return ctx.fail("command '%s' already exists", added[i].key);
		p.entries.push(added[i]);
	}

	path::mkdir(string::tformat("%s/src/cmd", p.dir), true)!;
	foreach (&e : added)
	{
		p.write_command(e, desc.len ? desc : string::tformat("The %s command", e.path[e.path.len - 1]))!;
		ctx.println("created src/cmd/%s", e.file)!;
	}
	p.sort();
	p.write_registry()!;
}

fn void? remove_commands(Ctx* ctx) => @pool()
{
	Project p;
	p.open(ctx, ctx.flag_string("dir"))!;
	String[] parent = split_path(ctx.flag_string("parent"));
	bool recursive = ctx.flag_bool("recursive");

	// collect the files to delete first, then delete
	List {Entry} doomed;
	doomed.tinit(8);
	foreach (name : ctx.args)
	{
		String[] path = mem::talloc_array(String, parent.len + 1);
		path[:parent.len] = parent[..];
		path[parent.len] = name;
		String key = join(path, " ");
		if (!p.find(key)) return ctx.fail("command '%s' not found (see `serp list`)", key);
		String prefix = string::tformat("%s ", key);
		foreach (e : p.entries)
		{
			bool child = e.key.starts_with(prefix);
			if (child && !recursive) return ctx.fail("command '%s' has subcommands; use --recursive to remove them too", key);
			bool listed;
			foreach (d : doomed) if (d.key == e.key) listed = true;
			if ((child || e.key == key) && !listed) doomed.push(e);
		}
	}
	foreach (d : doomed)
	{
		file::delete(string::tformat("%s/src/cmd/%s", p.dir, d.file))!;
		ctx.println("removed src/cmd/%s", d.file)!;
	}
	List {Entry} kept;
	kept.tinit(p.entries.len());
	foreach (e : p.entries)
	{
		bool gone;
		foreach (d : doomed) if (d.key == e.key) gone = true;
		if (!gone) kept.push(e);
	}
	p.entries = kept;
	p.write_registry()!;
}

fn void? list_commands(Ctx* ctx) => @pool()
{
	Project p;
	p.open(ctx, ctx.flag_string("dir"))!;
	foreach (e : p.entries)
	{
		for (sz i = 1; i < e.path.len; i++) ctx.print("  ")!;
		ctx.println("%s", e.path[e.path.len - 1])!;
	}
}
