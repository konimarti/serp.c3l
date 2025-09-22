module serp::command;

import serp::getopt;

import std::collections::list;
import std::io;

alias RunFunc = fn void?(Command *c, String[], Option[]);

struct Command
{
	// User-provided data
	String use;
	RunFunc run;
	String desc;

	// Internal data
	List {Flag} flags;
	List {Command*} cmds;
	Allocator allocator;
}

fn Command new(String use, RunFunc run, Allocator allocator = mem)
{
	Command cmd = {.use = use, .run = run, .allocator = allocator};
	cmd.flags.init(allocator, 4);
	cmd.cmds.init(allocator, 4);
	return cmd;
}

fn Command temp(String use, RunFunc run) => new(use, run, tmem);

fn void Command.free(&self)
{
	if (!self.allocator) return;

	self.flags.free();

	foreach (cmd : self.cmds) cmd.free();
	self.cmds.free();

	if (self.desc) self.desc.free(self.allocator);

	*self = {};
}

fn Command* Command.describe(&self, String s)
{
	self.desc = s.copy(self.allocator);
	return self;
}

fn Command* Command.add_flag(&self, Flag f)
{
	self.flags.push(f);
	return self;
}

fn Command* Command.add_command(&self, Command *c)
{
	if (c) self.cmds.push(c);
	return self;
}

fn void? Command.usage(&self, OutStream out = io::stdout())
{
	const PREFIX = "  ";
	if (self.desc) io::fprintf(out, "\n%s\n", self.desc)!;
	io::fprintf(out, "\nUsage:\n%s%s\n", PREFIX, self.use)!;
	if (self.cmds.len() > 0)
	{
		io::fprintf(out, "\nAvailabe Commands:\n")!;
		foreach (sub : self.cmds)
		{
			String cmd = sub.use;
			if (try n = cmd.index_of_char(' ')) cmd = cmd[:n];
			io::fprintf(out, "%s%s\t%s\n", PREFIX, cmd, self.desc)!;
		}
	}
	if (self.flags.len() > 0)
	{
		io::fprintf(out, "\nFlags:\n")!;
		foreach (f : self.flags)
		{
			io::fprintf(out, "%s", PREFIX)!;
			if (f.shortopt) io::fprintf(out, "-%c", f.shortopt)!;
			if (f.shortopt && f.longopt)
			{
				io::fprintf(out, ", ")!;
			}
			else
			{
				io::fprintf(out, "    ")!;
			}
			if (f.longopt) io::fprintf(out, "--%s", f.longopt)!;
			if (f.optarg) io::fprintf(out, " string")!;
			if (f.desc) io::fprintf(out, "\t%s", f.desc)!;
			io::fprintf(out, "\n")!;
		}
		io::fprintf(out, "\n")!;
	}
}


fn void? Command.execute(&self, String[] args) => @pool()
{
	int optind;
	Option[]? opts = getopt::parse_temp(args, self.flags.to_tarray(), &optind);
	if (catch err = opts)
	{
		io::eprintf("Failed to parse option: %s\n", err);
		return self.usage();
	}
	if (optind < args.len) {
		String arg = args[optind];
		foreach (sub : self.cmds)
		{
			String cmd = sub.use;
			if (try n = cmd.index_of_char(' ')) cmd = cmd[:n];
			if (arg == cmd)
			{
				$if $feature(DEBUG):
				io::printfn("execute sub-command: %s", cmd);
				$endif
				return sub.execute(args[optind..]);
			}
		}
		$if $feature(DEBUG):
		io::printfn("positional arguments: %s", args[optind..]);
		$endif
	}
	$if $feature(DEBUG):
	io::printfn("run command: %s", self.use);
	$endif
	return self.run(self, args[optind..], opts);
}
