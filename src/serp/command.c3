module serp;

import std::collections::list;
import std::io;

<*
 Create the root command of an application.

 @param name : "program name shown in usage output"
 @param version : "if not empty, enables `--version`"
 @param desc : "one line description"
 @param run : "action when no subcommand is given (may be null)"
*>
fn Command* app(String name, String version = "", String desc = "", RunFn run = null, Allocator allocator = mem)
{
	Command* c = cmd(name, desc, run, allocator);
	c.version = version;
	return c;
}

<*
 Create a (sub)command. Attach it with `parent.add(...)`.

 @param name : "name used on the command line"
*>
fn Command* cmd(String name, String desc = "", RunFn run = null, Allocator allocator = mem)
{
	Command* c = alloc::new(allocator, Command);
	c.name = name;
	c.desc = desc;
	c.run = run;
	c.allocator = allocator;
	// capacity 0: nothing is allocated until something is added
	c.flags.init(allocator, 0);
	c.children.init(allocator, 0);
	c.aliases.init(allocator, 0);
	return c;
}

<*
 Release the command, all its subcommands and everything allocated for them.
 Call it on the root only.
*>
fn void Command.free(&self)
{
	foreach (child : self.children) child.free();
	self.flags.free();
	self.children.free();
	self.aliases.free();
	alloc::free(self.allocator, self);
}

// ---- builders (all return the command so they can be chained) ----

fn Command* Command.describe(&self, String desc, String long_desc = "")
{
	self.desc = desc;
	if (long_desc.len) self.long_desc = long_desc;
	return self;
}

fn Command* Command.examples(&self, String text) { self.example = text; return self; }
fn Command* Command.usage_args(&self, String text) { self.args_usage = text; return self; }
fn Command* Command.grouped(&self, String group) { self.group = group; return self; }
fn Command* Command.deprecate(&self, String message) { self.deprecated = message; return self; }
fn Command* Command.hide(&self) { self.hidden = true; return self; }
fn Command* Command.accepts(&self, ArgSpec spec) { self.args = spec; return self; }
fn Command* Command.before(&self, RunFn f) { self.pre_run = f; return self; }
fn Command* Command.after(&self, RunFn f) { self.post_run = f; return self; }
fn Command* Command.before_all(&self, RunFn f) { self.persistent_pre_run = f; return self; }
fn Command* Command.aka(&self, String name) { self.aliases.push(name); return self; }

<*
 Add a flag. Flags are valid for this command only unless `persistent` is set.
*>
fn Command* Command.flag(&self, Flag f)
{
	assert(f.name.len > 0 || f.short_name != 0, "a flag needs a name or a short name");
	self.flags.push(f);
	return self;
}

fn Command* Command.persistent_flag(&self, Flag f)
{
	f.persistent = true;
	return self.flag(f);
}

<*
 Add a subcommand. The parent takes ownership of `child`.
*>
fn Command* Command.add(&self, Command* child)
{
	assert(child.parent == null, "command is already attached");
	assert(!self.find_child(child.name), "duplicate subcommand name");
	child.parent = self;
	self.children.push(child);
	return self;
}

// ---- lookups ----

fn bool Command.matches(&self, String s)
{
	if (self.name == s) return true;
	foreach (a : self.aliases) if (a == s) return true;
	return false;
}

fn Command* Command.find_child(&self, String s)
{
	foreach (child : self.children) if (child.matches(s)) return child;
	return null;
}

fn Command* Command.root(&self)
{
	Command* c = self;
	while (c.parent) c = c.parent;
	return c;
}

// Finds a flag visible from this command: its own and persistent ones of the ancestors.
fn Flag* Command.lookup_long(&self, String name)
{
	for (Command* c = self; c; c = c.parent)
	{
		foreach (&f : c.flags)
		{
			if ((c == self || f.persistent) && f.name.len && f.name == name) return f;
		}
	}
	return null;
}

fn Flag* Command.lookup_short(&self, char ch)
{
	for (Command* c = self; c; c = c.parent)
	{
		foreach (&f : c.flags)
		{
			if ((c == self || f.persistent) && f.short_name == ch) return f;
		}
	}
	return null;
}

// Visit all visible flags: own flags first, then persistent ones from the parents.
macro void Command.@each_flag(&self; @body(Flag* f, bool inherited))
{
	for (Command* c = self; c; c = c.parent)
	{
		foreach (&f : c.flags)
		{
			if (c == self)
			{
				@body(f, false);
			}
			else if (f.persistent)
			{
				@body(f, true);
			}
		}
	}
}

// Writes the space separated command path, e.g. `app serve`.
fn void? Command.write_path(&self, OutStream out)
{
	if (self.parent)
	{
		self.parent.write_path(out)!;
		io::fprint(out, " ")!;
	}
	io::fprint(out, self.name)!;
}

// Does this command or one of its subcommands (recursively) offer something to run?
fn bool Command.is_runnable(&self) => self.run != null;
