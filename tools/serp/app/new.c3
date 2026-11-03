module serp_tool;

import serp;
import std::io::file;
import std::io::path;
import std::os::process;

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

const String SERP_URL = "https://github.com/konimarti/serp.c3l";

// Runs in the new project: needs c3l (exit 127 if missing), writes c3l.lock and installs serp into lib/.
const String INSTALL_SCRIPT = `command -v c3l >/dev/null 2>&1 || exit 127; cd "$1" && c3l init && c3l add "$2"`;

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
	bool local = serp_path.len > 0;   // use a serp.c3l checkout instead of installing it into lib/
	if (serp_path.contains("\"") || serp_path.contains("\\"))
	{
		return ctx.fail("--serp-path must not contain quotes or backslashes");
	}
	String dir = string::tformat("%s/%s", ctx.flag_string("dir"), name);
	if (file::exists(dir)) return ctx.fail("'%s' already exists", dir);
	if (local)
	{
		// accept the path of serp.c3l itself as well as the folder containing it
		while (serp_path.len > 1 && serp_path[^1] == '/') serp_path = serp_path[:^1];
		if (serp_path == "serp.c3l")
		{
			serp_path = ".";
		}
		else if (serp_path.ends_with("/serp.c3l"))
		{
			serp_path = serp_path.len == 9 ? "/" : serp_path[:^9];
		}
		// the project does not exist yet, so resolve `..` without touching the disk
		String lib = serp_path.starts_with("/") ? serp_path : path::normalize(string::tformat("%s/%s", dir, serp_path))!;
		if (!lib.len) lib = ".";
		if (!file::exists(string::tformat("%s/serp.c3l/manifest.json", lib)))
		{
			return ctx.fail("serp.c3l not found in '%s' (see --serp-path)", lib);
		}
	}
	else
	{
		serp_path = "lib";
	}

	path::mkdir(string::tformat("%s/src/cmd", dir), true)!;
	file::save(string::tformat("%s/project.json", dir), string::tformat(PROJECT_TEMPLATE, serp_path, name))!;
	file::save(string::tformat("%s/src/main.c3", dir), string::tformat(MAIN_TEMPLATE, mod, name))!;

	Project p = {.dir = dir, .mod = mod};
	p.entries.tinit(1);
	p.entries.push(make_entry({"hello"}));
	p.write_command(&p.entries.entries[0], "Say hello")!;
	p.write_registry()!;
	file::save(string::tformat("%s/.gitignore", dir), local ? "build/\nobj/\n" : "build/\nobj/\nlib/\n")!;
	ctx.println("created %s/", dir)!;
	if (!local && !install_serp(ctx, name, dir, ctx.flag_bool("no-install"))!)
	{
		return;
	}
	ctx.println("  cd %s && c3c run", dir)!;
}

const String MANUAL_HINT = `
  serp is not installed yet. Pick one:
    c3l (https://github.com/konimarti/c3l):  cd %s && c3l init && c3l add %s
    git submodule:                           cd %s && git init && git submodule add %s lib/serp.c3l
    local checkout:                          serp new %s --serp-path <folder containing serp.c3l>
`;

<*
 Installs serp into the project's lib/ folder with c3l (pinned in c3l.lock).
 Without c3l (or with --no-install) it prints the manual options instead.
*>
fn bool? install_serp(Ctx* ctx, String name, String dir, bool skip) @local => @pool()
{
	if (!skip && !env::WIN32)
	{
		int? rc = process::run({"sh", "-c", INSTALL_SCRIPT, "sh", dir, string::tformat("%s@HEAD", SERP_URL)}, SpawnOptions.INHERIT_ENV | SpawnOptions.INHERIT_STDIO);
		if (try rc)
		{
			if (rc == 0)
			{
				ctx.println("  installed serp into %s/lib, pinned in %s/c3l.lock", dir, dir)!;
				return true;
			}
			if (rc != 127) io::fprintfn(ctx.err, "warning: c3l failed (exit %d)", rc)!;
		}
	}
	ctx.println(MANUAL_HINT, dir, SERP_URL, dir, SERP_URL, name)!;
	return false;
}

