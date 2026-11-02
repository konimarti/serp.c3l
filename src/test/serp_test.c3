module serp_test;

import serp;
import std::io;
import std::os::env;

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

fn void test_repeat_choices_negation() @test => @assert_leak()
{
	Command* app = serp::app("app");
	defer app.free();
	DString err = dstring::new(mem);
	defer err.free();
	app.err = &err;
	app.flag(serp::string_flag('I', "include"));
	app.flag({.name = "format", .kind = STRING, .choices = {"json", "yaml"}});
	app.flag({.name = "color", .default_value = "true"});
	app.flag(serp::bool_flag('v', "verbose"));
	app.run = fn void?(Ctx* ctx)
	{
		if (!ctx.has("include")) return;
		String[] inc = ctx.flag_strings("include");
		assert(inc.len == 2 && inc[0] == "a" && inc[1] == "b");
		assert(ctx.flag_string("include") == "b");
		assert(ctx.flag_strings("verbose").len == 3);
		assert(!ctx.flag_bool("color"));
	};
	assert(app.execute_line("app -I a --include=b -vvv --no-color") == 0);
	assert(app.execute_line("app --format xml") == 2);
	assert(err.str_view().contains("expected one of: json, yaml"));
	assert(app.execute_line("app --format yaml") == 0);
	assert(app.execute_line("app --no-format x") == 2);   // only bool flags can be negated
}

fn void test_env_and_defaults_validated() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	defer env::clear_var("SERP_TEST_PORT");
	defer env::clear_var("SERP_TEST_TOK");
	h.app.add(serp::cmd("env", "", &record)
		.flag({.name = "port", .kind = INT, .env = "SERP_TEST_PORT"})
		.flag({.name = "tok", .required = true, .env = "SERP_TEST_TOK"}));
	env::set_var("SERP_TEST_PORT", "xyz");
	env::set_var("SERP_TEST_TOK", "");
	assert(h.app.execute_line("app env") == 2);           // empty env does not satisfy `required`
	env::set_var("SERP_TEST_TOK", "t");
	assert(h.app.execute_line("app env") == 2);           // invalid integer from the environment
	assert(h.err.str_view().contains("invalid value 'xyz'"));
	env::set_var("SERP_TEST_PORT", "9");
	assert(h.app.execute_line("app env") == 0);
	assert(last_port == 9);
}

fn void test_bindings_keep_value_when_absent() @test => @assert_leak()
{
	bool verbose = true;
	Command* app = serp::app("app");
	defer app.free();
	app.flag({.name = "verbose", .bind_bool = &verbose});
	app.run = &record;
	assert(app.execute_line("app") == 0);
	assert(verbose);
	assert(app.execute_line("app --verbose=false") == 0);
	assert(!verbose);
}

int hooks_seen;

fn void? count_hook(Ctx* ctx)
{
	hooks_seen++;
}

fn void test_deep_hooks_and_usage() @test => @assert_leak()
{
	Command* app = serp::app("app");
	defer app.free();
	DString err = dstring::new(mem);
	defer err.free();
	app.err = &err;
	app.before_all(&count_hook);
	Command* cur = app;
	for (int i = 0; i < 20; i++)
	{
		Command* next = serp::cmd("n", "", &record);
		cur.add(next);
		cur = next;
	}
	hooks_seen = 0;
	assert(app.execute_line(string::tformat("app %s", "n n n n n n n n n n n n n n n n n n n n")) == 0);
	assert(hooks_seen == 1);
	// usage is shown with the error; a word after `--` is never a command suggestion
	assert(app.execute_line("app -- n") == 2);
	assert(err.str_view().contains("Usage:"));
	assert(!err.str_view().contains("Did you mean"));
}

fn void test_docs_no_duplicate_and_man_escape() @test => @assert_leak()
{
	Command* app = serp::app("app", "1.0", ".dot \\ back");
	defer app.free();
	DString out = dstring::new(mem);
	defer out.free();
	app.out = &out;
	app.add(serp::cmd("x", "", &record));
	assert(app.execute_line("app docs man") == 0);
	assert(out.str_view().contains("\\&.dot \\e back"));
	out.clear();
	app.desc = "unique-description";
	assert(app.execute_line("app docs markdown") == 0);
	String o = out.str_view();
	sz first = o.index_of("unique-description")!!;
	assert(!o[first + 1..].contains("unique-description"));
}

fn void test_unicode_short_flags() @test => @assert_leak()
{
	Command* app = serp::app("app");
	defer app.free();
	DString out = dstring::new(mem);
	DString err = dstring::new(mem);
	defer out.free();
	defer err.free();
	app.out = &out;
	app.err = &err;
	app.flag(serp::bool_flag('ü', "grün", "green"));
	app.flag(serp::string_flag('世', "welt", "world"));
	app.flag(serp::bool_flag('v', "verbose"));
	app.run = &record;
	assert(app.execute_line("app -ü") == 0 && last_verbose == false);
	assert(app.execute_line("app -vü世 x") == 0 && last_arg == "");   // value flag takes the next arg
	assert(app.execute_line("app -世x") == 0);
	assert(app.execute_line("app -ö") == 2);
	assert(err.str_view().contains("unknown flag: -ö"));
	assert(app.execute_line("app --help") == 0);
	assert(out.str_view().contains("-ü, --grün"));
	assert(out.str_view().contains("-世, --welt string"));
	assert(app.execute_line("app -世") == 2);
	assert(err.str_view().contains("flag -世 needs a value"));
}

fn void test_fail_and_add_at() @test => @assert_leak()
{
	Harness h;
	h.init();
	defer h.free();
	h.app.add_at({"repo"}, serp::cmd("rm", "", &failing));
	assert(h.app.execute_line("app repo rm") == 1);
	String e = h.err.str_view();
	assert(e.contains("Error: nothing to remove: x"));
	assert(!e.contains("FAILED"));
	h.err.clear();
	assert(h.app.execute_line("app help nope") == 1);
	assert(!h.err.str_view().contains("INVALID_ARGS"));
}

fn void? failing(Ctx* ctx) => ctx.fail("nothing to remove: %s", "x");
