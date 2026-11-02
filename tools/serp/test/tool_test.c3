module serp_tool_test;

import serp;
import serp_tool;
import std::io;
import std::io::file;
import std::io::path;

struct Tool
{
	Command* app;
	DString  out;
	DString  err;
	String   dir;
}

// A scratch folder that holds a fake `serp.c3l`, so `serp new` finds the library.
fn void Tool.init(&self, String name)
{
	self.out = dstring::new(mem);
	self.err = dstring::new(mem);
	self.app = serp_tool::build_tool();
	self.app.out = &self.out;
	self.app.err = &self.err;
	self.dir = string::tformat("%s/serp_tool_test_%s", (String)path::temp_directory(tmem)!!, name);
	if (file::exists(self.dir)) path::rmtree(path::tnew(self.dir)!!)!!;
	path::mkdir(string::tformat("%s/serp.c3l", self.dir), true)!!;
	file::save(string::tformat("%s/serp.c3l/manifest.json", self.dir), "{}")!!;
}

fn void Tool.free(&self)
{
	self.app.free();
	self.out.free();
	self.err.free();
	path::rmtree(path::tnew(self.dir)!!)!!;
}

// Runs `serp <args>` inside the project (or the scratch folder for `new`) and returns the exit code.
fn int Tool.run(&self, String project, String... args)
{
	self.out.clear();
	self.err.clear();
	String[] line = mem::talloc_array(String, args.len + 3);
	line[0] = "serp";
	foreach (i, a : args) line[i + 1] = a;
	line[args.len + 1] = "--dir";
	line[args.len + 2] = project.len ? string::tformat("%s/%s", self.dir, project) : self.dir;
	return self.app.execute(line);
}

fn String Tool.read(&self, String relative)
{
	return (String)file::load_temp(string::tformat("%s/%s", self.dir, relative))!!;
}

fn void test_new_validates_names() @test => @assert_leak()
{
	Tool t;
	t.init("new");
	defer t.free();
	foreach (bad : (String[]){"Bad", "9app", "my--app", "app-", "for", "serp", "a_b", "a b"})
	{
		assert(t.run("", "new", bad) == 1, "should reject '%s'", bad);
	}
	assert(!file::exists(string::tformat("%s/Bad", t.dir)));
	assert(t.run("", "new", "my-app", "--serp-path", "/nonexistent") == 1);
	assert(t.err.str_view().contains("serp.c3l not found"));
	assert(t.run("", "new", "my-app") == 0);
	assert(t.run("", "new", "my-app") == 1);                               // exists
	assert(t.read("my-app/src/main.c3").contains("module my_app;"));
	assert(t.read("my-app/src/commands.c3").contains("root.add(cmd_hello());"));
	assert(t.read("my-app/src/cmd/hello.c3").contains("// serp:cmd hello"));
}

fn void test_add_list_remove() @test => @assert_leak()
{
	Tool t;
	t.init("add");
	defer t.free();
	assert(t.run("", "new", "app") == 0);

	assert(t.run("app", "add", "repo", "serve") == 0);
	assert(t.run("app", "add", "create", "delete", "-p", "repo", "-d", "Do it") == 0);
	assert(t.run("app", "add", "deep", "-p", "repo create") == 0);
	String registry = t.read("app/src/commands.c3");
	assert(registry.contains("root.add_at({\"repo\", \"create\"}, cmd_repo__create__deep());"));
	assert(t.read("app/src/cmd/repo__create.c3").contains("\"Do it\""));

	assert(t.run("app", "list") == 0);
	assert(t.out.str_view() == "hello\nrepo\n  create\n    deep\n  delete\nserve\n");

	// mistakes change nothing
	assert(t.run("app", "add", "Bad") == 1);
	assert(t.run("app", "add", "ok", "serve") == 1);                       // `ok` is not created either
	assert(!file::exists(string::tformat("%s/app/src/cmd/ok.c3", t.dir)));
	assert(t.run("app", "add", "x", "-p", "nope") == 1);
	assert(t.err.str_view().contains("parent command 'nope' not found"));
	assert(t.run("app", "add", "x", "-d", "a\"b") == 1);
	assert(t.run("app", "remove", "repo") == 1);                          // has subcommands
	assert(t.err.str_view().contains("--recursive"));
	assert(t.run("app", "remove", "nope") == 1);

	assert(t.run("app", "rm", "deep", "-p", "repo create") == 0);
	assert(t.run("app", "rm", "repo", "repo", "-r") == 0);
	assert(t.run("app", "ls") == 0);
	assert(t.out.str_view() == "hello\nserve\n");
	assert(!t.read("app/src/commands.c3").contains("repo"));
	assert(t.run("", "ls") == 1);                                         // not a project
	assert(t.err.str_view().contains("not a serp project"));
}
