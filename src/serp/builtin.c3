module serp;

import std::io;

<*
 Adds the built-in commands to the root: `help`, `completion`, and the hidden
 `docs`. Called once by `execute`; user defined commands with the same name win.
*>
fn void Command.prepare(&self)
{
	if (self.prepared) return;
	self.prepared = true;
	if (self.children.len() == 0) return;

	if (!self.find_child("help"))
	{
		self.add(cmd("help", "Help about any command", &help_run)
			.usage_args("[command]...")
			.grouped("Additional"));
	}
	if (!self.no_completion && !self.find_child("completion"))
	{
		self.add(cmd("completion", "Generate a shell completion script", &completion_run)
			.usage_args("<bash|zsh|fish>")
			.accepts(exact_args(1))
			.grouped("Additional"));
	}
	if (!self.find_child("docs"))
	{
		self.add(cmd("docs", "Generate documentation for this program", &docs_run)
			.usage_args("<markdown|man>")
			.accepts(exact_args(1))
			.hide());
	}
}

fn void? help_run(Ctx* ctx) @private
{
	Command* target = ctx.cmd.root();
	foreach (a : ctx.args)
	{
		Command* sub = target.find_child(a);
		if (!sub)
		{
			io::fprintfn(ctx.err, "Unknown help topic '%s'", a)!;
			return INVALID_ARGS~;
		}
		target = sub;
	}
	write_help(target, ctx.out, false)!;
}

fn void? completion_run(Ctx* ctx) @private
{
	Command* root = ctx.cmd.root();
	switch (ctx.args[0])
	{
		case "bash": write_bash_completion(root, ctx.out)!;
		case "zsh": write_zsh_completion(root, ctx.out)!;
		case "fish": write_fish_completion(root, ctx.out)!;
		default:
			io::fprintfn(ctx.err, "unsupported shell '%s' (use bash, zsh or fish)", ctx.args[0])!;
			return INVALID_ARGS~;
	}
}

fn void? docs_run(Ctx* ctx) @private
{
	Command* root = ctx.cmd.root();
	switch (ctx.args[0])
	{
		case "markdown": write_markdown(root, ctx.out)!;
		case "man": write_man(root, ctx.out)!;
		default:
			io::fprintfn(ctx.err, "unsupported format '%s' (use markdown or man)", ctx.args[0])!;
			return INVALID_ARGS~;
	}
}
