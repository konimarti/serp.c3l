module serp_tool;

import serp;

const String VERSION = "0.8.0";

fn Command* build_tool()
{
	Command* app = serp::app("serp", VERSION, "Create and extend command line apps built with serp");
	app.persistent_flag(serp::string_flag(0, "dir", "folder to work in (for `new`: where the project is created)", "."));

	app.add(serp::cmd("new", "Create a new project", &new_project)
		.usage_args("<name>")
		.accepts(serp::exact_args(1))
		.flag(serp::string_flag(0, "serp-path", "folder containing serp.c3l, relative to the new project", ".."))
		.examples("  serp new myapp\n  serp new myapp --serp-path ~/src"));

	app.add(serp::cmd("add", "Add commands to the project", &add_commands)
		.usage_args("<name>...")
		.accepts(serp::min_args(1))
		.flag(serp::string_flag('p', "parent", "parent command, e.g. \"repo\" or \"repo sub\""))
		.flag(serp::string_flag('d', "desc", "one line description"))
		.examples("  serp add serve build\n  serp add create delete -p repo"));

	app.add(serp::cmd("remove", "Remove commands from the project", &remove_commands)
		.aka("rm")
		.usage_args("<name>...")
		.accepts(serp::min_args(1))
		.flag(serp::string_flag('p', "parent", "parent command, e.g. \"repo\" or \"repo sub\""))
		.flag(serp::bool_flag('r', "recursive", "also remove all subcommands"))
		.examples("  serp remove serve\n  serp rm repo -r"));

	app.add(serp::cmd("list", "Show the commands of the project", &list_commands)
		.aka("ls")
		.accepts(serp::no_args()));
	return app;
}
