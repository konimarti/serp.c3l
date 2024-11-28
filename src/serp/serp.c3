module serp;

import std::io;

fn void! root_cmd(Command *c, String[] args, Option[] opts)
{
	return show_args_and_opts("root", c, args, opts);
}

fn void! init_cmd(Command *c, String[] args, Option[] opts)
{
	return show_args_and_opts("init", c, args, opts);
}

fn void! add_cmd(Command *c, String[] args, Option[] opts)
{
	return show_args_and_opts("add", c, args, opts);
}

fn void! show_args_and_opts(String cmd, Command *c, String[] args, Option[] opts)
{
	io::printfn("Command: %s", cmd);
	io::printn("--------");
	io::printfn("Positional arguments:\n\t%s", args);
	if (opts.len)
	{
		io::printfn("\nParsed flags:");
		foreach (opt : opts) io::printf("\t%s", opt);
	}
	io::printf("\nUsage message:\n");
	io::printf("--------------");
	return c.usage();
}

fn void! main(String[] args)
{
	Command root = command::new(use: "app [commands] [flags]", run: &root_cmd)
	.set_desc("describe your command here")
	.add_command(
		command::new(use: "init [flags]", run: &init_cmd)
		.add_flag({.shortopt = 'p', .desc = "path", .optarg = true})
		.add_flag({.shortopt = 'n', .desc = "name", .optarg = true})
		.set_desc("'init' your app with this command")
	)
	.add_command(
		command::new(use: "add [flags] <name>", run: &add_cmd)
		.add_flag({.shortopt = 'f', .longopt = "force"})
		.set_desc("'add' something to your app")
	);

	defer root.free();

	return root.execute(args);
}
