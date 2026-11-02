module serp_tool;

import serp;
import std::io;
import std::io::file;
import std::io::path;

const String PROJECT_TEMPLATE = `{
	"authors": [],
	"version": "0.1.0",
	"output": "build",
	"dependency-search-paths": [ "%s" ],
	"dependencies": [ "serp" ],
	"sources": [ "src/**" ],
	"targets": {
		"%s": { "type": "executable" }
	}
}
`;

const String MAIN_TEMPLATE = `module %s;

import serp;
import std::io;

fn void? hello(Ctx* ctx)
{
	ctx.println("%%s, %%s!", ctx.flag_string("greeting"), ctx.arg(0, "world"))!;
}

fn int main(String[] args)
{
	Command* app = serp::app("%s", "0.1.0", "My new command line app");
	defer app.free();

	app.add(serp::cmd("hello", "Say hello", &hello)
		.usage_args("[name]")
		.accepts(serp::max_args(1))
		.flag(serp::string_flag('g', "greeting", "what to say", "Hello")));

	return app.execute(args);
}
`;

fn void? new_project(Ctx* ctx) => @pool()
{
	String name = ctx.arg(0);
	String serp_path = ctx.flag_string("serp-path");
	foreach (ch : name)
	{
		if (!ch.is_alnum() && ch != '-' && ch != '_')
		{
			io::fprintfn(ctx.err, "invalid project name '%s': use letters, digits, '-' and '_'", name)!;
			return serp::INVALID_ARGS~;
		}
	}
	if (file::exists(name))
	{
		io::fprintfn(ctx.err, "'%s' already exists", name)!;
		return serp::INVALID_ARGS~;
	}
	path::mkdir(string::tformat("%s/src", name), true)!;
	String project = string::tformat(PROJECT_TEMPLATE, serp_path, name);
	String main_c3 = string::tformat(MAIN_TEMPLATE, name.treplace("-", "_"), name);
	file::save(string::tformat("%s/project.json", name), project)!;
	file::save(string::tformat("%s/src/main.c3", name), main_c3)!;
	ctx.println("created %s/\n  cd %s && c3c run", name, name)!;
}

fn int main(String[] args)
{
	Command* app = serp::app("serp", "0.8.0", "Scaffolding for serp based command line apps");
	defer app.free();

	app.add(serp::cmd("new", "Create a new project using serp", &new_project)
		.usage_args("<name>")
		.accepts(serp::exact_args(1))
		.flag(serp::string_flag(0, "serp-path", "folder that contains the serp.c3l directory, relative to the new project", ".."))
		.examples("  serp new myapp --serp-path ~/src"));

	return app.execute(args);
}
