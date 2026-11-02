module serp;

import std::io;

// ---- bash ----

fn void? write_bash_completion(Command* root, OutStream out) => @pool()
{
	String n = root.name;
	String id = fn_ident(n);
	io::fprintfn(out, "# bash completion for %s", n)!;
	io::fprintfn(out, "_%s_complete() {", id)!;
	io::fprintn(out, "  local cur=\"${COMP_WORDS[COMP_CWORD]}\" path w opts=\"\"")!;
	io::fprintfn(out, "  path=\"%s\"", n)!;
	io::fprintn(out, "  for w in \"${COMP_WORDS[@]:1:COMP_CWORD-1}\"; do")!;
	io::fprintn(out, "    case \"$w\" in -*) continue;; esac")!;
	io::fprintn(out, "    case \"$path:$w\" in")!;
	bash_transitions(root, out)!;
	io::fprintn(out, "    esac")!;
	io::fprintn(out, "  done")!;
	io::fprintn(out, "  case \"$path\" in")!;
	bash_options(root, out)!;
	io::fprintn(out, "  esac")!;
	io::fprintn(out, "  COMPREPLY=( $(compgen -W \"$opts\" -- \"$cur\") )")!;
	io::fprintn(out, "}")!;
	io::fprintfn(out, "complete -F _%s_complete %s", id, n)!;
}

fn void? write_zsh_completion(Command* root, OutStream out)
{
	io::fprintfn(out, "#compdef %s", root.name)!;
	io::fprintn(out, "autoload -U +X bashcompinit && bashcompinit")!;
	write_bash_completion(root, out)!;
}

fn void? bash_transitions(Command* c, OutStream out) @local
{
	foreach (child : c.children)
	{
		if (child.hidden) continue;
		bash_transition(c, child, child.name, out)!;
		foreach (a : child.aliases) bash_transition(c, child, a, out)!;
		bash_transitions(child, out)!;
	}
}

fn void? bash_transition(Command* c, Command* child, String word, OutStream out) @local
{
	io::fprint(out, "      \"")!;
	c.write_path(out)!;
	io::fprintf(out, ":%s\") path=\"", word)!;
	child.write_path(out)!;
	io::fprintn(out, "\";;")!;
}

fn void? bash_options(Command* c, OutStream out) @local
{
	io::fprint(out, "    \"")!;
	c.write_path(out)!;
	io::fprint(out, "\") opts=\"")!;
	foreach (child : c.children)
	{
		if (child.hidden) continue;
		io::fprintf(out, "%s ", child.name)!;
		foreach (a : child.aliases) io::fprintf(out, "%s ", a)!;
	}
	io::fprint(out, "--help ")!;
	if (c.parent == null && c.version.len) io::fprint(out, "--version ")!;
	c.@each_flag(; Flag* f, bool inherited)
	{
		if (!f.hidden)
		{
			if (f.name.len) io::fprintf(out, "--%s ", f.name)!;
			if (f.short_name) io::fprintf(out, "-%c ", f.short_name)!;
		}
	};
	io::fprintn(out, "\";;")!;
	foreach (child : c.children)
	{
		if (!child.hidden) bash_options(child, out)!;
	}
}

// ---- fish ----

fn void? write_fish_completion(Command* root, OutStream out) => @pool()
{
	io::fprintfn(out, "# fish completion for %s", root.name)!;
	io::fprintfn(out, "complete -c %s -f", root.name)!;
	fish_command(root, root, out)!;
}

fn void? fish_command(Command* root, Command* c, OutStream out) @local
{
	// condition: this command's name was seen, and none of its children yet
	DString cond = dstring::temp();
	if (c.parent == null)
	{
		cond.append_string("__fish_use_subcommand");
	}
	else
	{
		cond.appendf("__fish_seen_subcommand_from %s", c.name);
		if (c.children.len() > 0)
		{
			cond.append_string("; and not __fish_seen_subcommand_from");
			foreach (child : c.children) cond.appendf(" %s", child.name);
		}
	}
	foreach (child : c.children)
	{
		if (child.hidden) continue;
		io::fprintfn(out, "complete -c %s -n \"%s\" -a %s -d '%s'", root.name, cond.str_view(), child.name, quote(child.desc))!;
	}
	DString fcond = dstring::temp();
	if (c.parent == null)
	{
		fcond.append_string("true");
	}
	else
	{
		fcond.appendf("__fish_seen_subcommand_from %s", c.name);
	}
	c.@each_flag(; Flag* f, bool inherited)
	{
		if (!f.hidden)
		{
			io::fprintf(out, "complete -c %s -n \"%s\"", root.name, fcond.str_view())!;
			if (f.short_name) io::fprintf(out, " -s %c", f.short_name)!;
			if (f.name.len) io::fprintf(out, " -l %s", f.name)!;
			if (f.kind != BOOL) io::fprint(out, " -r")!;
			io::fprintfn(out, " -d '%s'", quote(f.desc))!;
		}
	};
	foreach (child : c.children) fish_command(root, child, out)!;
}

// ---- helpers ----

// escapes single quotes for use inside '...'
fn String quote(String s) @local
{
	return s.treplace("'", "\\'");
}

// a shell function name part: non-alphanumerics become '_'
fn String fn_ident(String s) @local
{
	char[] buf = mem::talloc_array(char, s.len);
	foreach (i, ch : s) buf[i] = ch.is_alnum() ? ch : '_';
	return (String)buf;
}
