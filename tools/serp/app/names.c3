module serp_tool;

// C3 keywords (and modules that cannot be shadowed) that are not usable as a module name.
const String[*] RESERVED = {
	"serp", "std", "void", "bool", "char", "double", "float", "int", "long", "short", "uint", "ulong", "ushort",
	"any", "fault", "typeid", "alias", "assert", "asm", "bitstruct", "break", "case", "catch", "const", "continue",
	"default", "defer", "do", "else", "enum", "extern", "false", "for", "foreach", "foreach_r", "fn", "if", "inline",
	"import", "macro", "module", "nextcase", "null", "interface", "return", "static", "struct", "switch", "true",
	"try", "typedef", "union", "var", "while", "tlocal", "attrdef", "constdef", "faultdef", "iptr", "uptr", "usz",
	"sz", "ichar", "bfloat", "lengthof",
};

fn bool is_reserved(String s)
{
	foreach (r : RESERVED) if (r == s) return true;
	return false;
}

<*
 A command or project name: lower case letters, digits and single dashes,
 starting with a letter and not ending with a dash. Such names map to C3
 identifiers without collisions (`-` becomes `_`, a path joins with `__`).
*>
fn bool valid_name(String s)
{
	if (!s.len || s[0] < 'a' || s[0] > 'z' || s[s.len - 1] == '-') return false;
	foreach (i, ch : s)
	{
		bool ok = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-';
		if (!ok || (ch == '-' && s[i - 1] == '-')) return false;
	}
	return true;
}

// `repo add` -> `repo__add`, `rm-all` -> `rm_all`.
fn String ident(String[] path)
{
	return join(path, "__").treplace("-", "_");
}

fn String join(String[] words, String sep)
{
	DString s = dstring::temp();
	foreach (i, w : words)
	{
		if (i) s.append_string(sep);
		s.append_string(w);
	}
	return s.str_view();
}

// "repo sub" or "repo/sub" -> {"repo", "sub"}
fn String[] split_path(String text)
{
	return text.treplace("/", " ").tsplit(" ", skip_empty: true);
}
