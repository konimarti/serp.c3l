module demo;

import serp;
import std::io;

fn void? serve(Ctx* ctx)
{
	ctx.println("serving on port %d (verbose=%s, host=%s)",
		ctx.flag_int("port"), ctx.flag_bool("verbose"), ctx.flag_string("host"))!;
}

fn void? greet(Ctx* ctx)
{
	foreach (name : ctx.args) ctx.println("%s, %s!", ctx.flag_string("greeting"), name)!;
}

fn void? fail(Ctx* ctx) => io::EOF~;

fn int main(String[] args)
{
	Command* app = serp::app("demo", "1.0.0", "A demo of the serp command line library");
	defer app.free();

	app.persistent_flag(serp::bool_flag('v', "verbose", "print more"));

	app.add(serp::cmd("serve", "Start the server", &serve)
		.aka("s")
		.flag(serp::int_flag('p', "port", "port to listen on", "8080"))
		.flag({.name = "host", .kind = STRING, .desc = "interface", .env = "DEMO_HOST", .default_value = "localhost"})
		.examples("  demo serve -p 9000\n  demo serve --host=0.0.0.0"));

	app.add(serp::cmd("greet", "Greet people", &greet)
		.usage_args("<name>...")
		.accepts(serp::min_args(1))
		.flag(serp::string_flag('g', "greeting", "what to say", "Hello")));

	app.add(serp::cmd("fail", "Always fails", &fail).hide());

	return app.execute(args);
}
