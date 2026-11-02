module serp_tool;

import serp;
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

fn Command* build_app()
{
	Command* app = serp::app("%s", "0.1.0", "My new command line app");
	commands::register(app);
	return app;
}

fn int main(String[] args)
{
	Command* app = build_app();
	defer app.free();
	return app.execute(args);
}
`;

fn void? new_project(Ctx* ctx) => @pool()
{
	String name = ctx.arg(0);
	if (!valid_name(name))
	{
		return ctx.fail("invalid project name '%s': use lower case letters, digits and single dashes, starting with a letter", name);
	}
	String mod = name.treplace("-", "_");
	if (is_reserved(mod)) return ctx.fail("'%s' cannot be used as a module name", mod);

	String serp_path = ctx.flag_string("serp-path");
	if (serp_path.contains("\"") || serp_path.contains("\\"))
	{
		return ctx.fail("--serp-path must not contain quotes or backslashes");
	}
	String dir = string::tformat("%s/%s", ctx.flag_string("dir"), name);
	if (file::exists(dir)) return ctx.fail("'%s' already exists", dir);
	// the project does not exist yet, so resolve `..` without touching the disk
	String lib = serp_path.starts_with("/") ? serp_path : path::normalize(string::tformat("%s/%s", dir, serp_path))!;
	if (!lib.len) lib = ".";
	if (!file::exists(string::tformat("%s/serp.c3l/manifest.json", lib)))
	{
		return ctx.fail("serp.c3l not found in '%s' (see --serp-path)", lib);
	}

	path::mkdir(string::tformat("%s/src/cmd", dir), true)!;
	file::save(string::tformat("%s/project.json", dir), string::tformat(PROJECT_TEMPLATE, serp_path, name))!;
	file::save(string::tformat("%s/.gitignore", dir), "build/\nobj/\n")!;
	file::save(string::tformat("%s/src/main.c3", dir), string::tformat(MAIN_TEMPLATE, mod, name))!;

	Project p = {.dir = dir, .mod = mod};
	p.entries.tinit(1);
	p.entries.push(make_entry({"hello"}));
	p.write_command(&p.entries.entries[0], "Say hello")!;
	p.write_registry()!;
	ctx.println("created %s/\n  cd %s && c3c run", dir, dir)!;
}
