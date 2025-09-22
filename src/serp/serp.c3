module serp_app;

import serp;

import std::io;

fn void? root_cmd(Command *c, String[] args, Option[] opts)
	=> show_args_and_opts("root", c, args, opts);

fn void? init_cmd(Command *c, String[] args, Option[] opts)
	=> show_args_and_opts("init", c, args, opts);

fn void? add_cmd(Command *c, String[] args, Option[] opts)
	=> show_args_and_opts("add", c, args, opts);


fn void? show_args_and_opts(String cmd, Command *c, String[] args, Option[] opts)
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

fn void main(String[] args) => @assert_leak()
{
	Command *root = command::new(use: "app [commands] [flags]", run: &root_cmd)
	.describe("describe your command here")
	.add_command(
		command::new(use: "init [flags]", run: &init_cmd)
		.add_flag({.shortopt = 'p', .desc = "path", .optarg = true})
		.add_flag({.shortopt = 'n', .desc = "name", .optarg = true})
		.describe("'init' your app with this command")
	)
	.add_command(
		command::new(use: "add [flags] <name>", run: &add_cmd)
		.add_flag({.shortopt = 'f', .longopt = "force"})
		.describe("'add' something to your app")
	);

	defer root.free();

	root.execute(args)!!;
}
