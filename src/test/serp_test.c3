module serp_test;

import serp;
import std::io;

int ran;
String last_arg;
long last_port;
bool last_verbose;

fn void? record(Ctx* ctx)
{
	ran++;
	last_arg = ctx.arg(0);
	last_port = ctx.flag_int("port", -1);
	last_verbose = ctx.flag_bool("verbose");
}

fn void? boom(Ctx* ctx) => io::EOF~;

struct Harness
{
	Command* app;
	DString out;
	DString err;
}

fn void Harness.init(&h)
{
	h.out = dstring::new(mem);
	h.err = dstring::new(mem);
	h.app = serp::app("app", "1.2.3", "test app");
	h.app.out = &h.out;
	h.app.err = &h.err;
	h.app.persistent_flag(serp::bool_flag('v', "verbose", "chatty"));
	h.app.add(serp::cmd("serve", "serve things", &record)
		.aka("s")
		.flag(serp::int_flag('p', "port", "port"))
		.flag({.name = "name", .short_name = 'n', .kind = STRING, .required = true}));
	h.app.add(serp::cmd("one", "one arg", &record).accepts(serp::exact_args(1)));
	h.app.add(serp::cmd("boom", "fails", &boom));
	Command* repo = serp::cmd("repo", "group");
	repo.add(serp::cmd("add", "add a repo", &record));
	h.app.add(repo);
	ran = 0;
	last_arg = "";
	last_port = 0;
	last_verbose = false;
}

fn void Harness.free(&self)
{
	self.app.free();
	self.out.free();
	self.err.free();
}

fn void test_dispatch() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	assert(h.app.execute_line("app serve -n x -p 80 pos") == 0);
	assert(ran == 1);
	assert(last_port == 80);
	assert(last_arg == "pos");
	assert(h.app.execute_line("app s --name=x --port 81") == 0);
	assert(last_port == 81);
	assert(h.app.execute_line("app repo add") == 0);
	assert(ran == 3);
}

fn void test_flags_forms() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	assert(h.app.execute_line("app -v serve -n x -p9") == 0);
	assert(last_verbose && last_port == 9);
	assert(h.app.execute_line("app serve -vn x --port=10 --verbose=false") == 0);
	assert(!last_verbose && last_port == 10);
	// flags may follow positional args; `--` ends flag parsing
	assert(h.app.execute_line("app serve file -n x") == 0);
	assert(last_arg == "file");
	assert(h.app.execute_line("app serve -n x -- -p") == 0);
	assert(last_arg == "-p");
}

fn void test_errors() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	assert(h.app.execute_line("app serve") == 2);                 // required flag
	assert(h.err.str_view().contains("required flag --name"));
	h.err.clear();
	assert(h.app.execute_line("app serve -n x --nope") == 2);
	assert(h.err.str_view().contains("unknown flag"));
	h.err.clear();
	assert(h.app.execute_line("app serve -n x -p abc") == 2);
	assert(h.app.execute_line("app serve -n") == 2);              // missing value
	assert(h.app.execute_line("app one") == 2);                   // arg validator
	assert(h.app.execute_line("app one a b") == 2);
	assert(h.app.execute_line("app one a") == 0);
	h.err.clear();
	assert(h.app.execute_line("app serv") == 2);
	assert(h.err.str_view().contains("Did you mean"));
	assert(h.err.str_view().contains("serve"));
	assert(h.app.execute_line("app boom") == 1);                  // run failure
}

fn void test_help_version() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	assert(h.app.execute_line("app --version") == 0);
	assert(h.out.str_view().contains("1.2.3"));
	h.out.clear();
	assert(h.app.execute_line("app serve --help") == 0);
	assert(h.out.str_view().contains("--port int"));
	assert(h.out.str_view().contains("Global Flags"));
	h.out.clear();
	assert(h.app.execute_line("app help repo") == 0);
	assert(h.out.str_view().contains("add a repo"));
	h.out.clear();
	assert(h.app.execute_line("app") == 0);                       // no run: shows help
	assert(h.out.str_view().contains("Available Commands"));
	assert(!h.out.str_view().contains("\e["));                    // no color when redirected
}

fn void test_generators() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	String[5] kinds = {"completion bash", "completion zsh", "completion fish", "docs markdown", "docs man"};
	foreach (kind : kinds)
	{
		h.out.clear();
		assert(h.app.execute_line(string::tformat("app %s", kind)) == 0);
		assert(h.out.len() > 50);
	}
	assert(h.app.execute_line("app completion nushell") == 1);
}

fn void test_bindings_and_defaults() @test => @assert_leak()
{
	bool verbose;
	long port;
	Command* app = serp::app("app");
	defer app.free();
	app.flag({.name = "verbose", .bind_bool = &verbose});
	app.flag({.name = "port", .kind = INT, .default_value = "7", .bind_int = &port});
	app.run = &record;
	assert(app.execute_line("app --verbose") == 0);
	assert(verbose && port == 7);
	assert(app.execute_line("app --port 5") == 0);
	assert(port == 5);
}
