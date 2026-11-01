module serp;

import std::math;

// Levenshtein distance, used for "did you mean" hints.
fn sz edit_distance(String a, String b) @private => @pool()
{
	if (a.len == 0) return b.len;
	if (b.len == 0) return a.len;
	sz[] prev = mem::talloc_array(sz, b.len + 1);
	sz[] cur = mem::talloc_array(sz, b.len + 1);
	for (sz j = 0; j <= b.len; j++) prev[j] = j;
	for (sz i = 1; i <= a.len; i++)
	{
		cur[0] = i;
		for (sz j = 1; j <= b.len; j++)
		{
			sz cost = a[i - 1] == b[j - 1] ? 0 : 1;
			cur[j] = math::min(math::min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
		}
		sz[] t = prev;
		prev = cur;
		cur = t;
	}
	return prev[b.len];
}

fn bool close_enough(String typed, String candidate) @private
{
	if (candidate.len == 0) return false;
	sz limit = typed.len <= 4 ? 1 : 2;
	if (candidate.starts_with(typed) && typed.len >= 2) return true;
	return edit_distance(typed, candidate) <= limit;
}

// Closest subcommand name (temp string or literal), empty if nothing is close.
fn String command_suggestion(Command* cur, String typed) @private
{
	foreach (child : cur.children)
	{
		if (child.hidden) continue;
		if (close_enough(typed, child.name)) return child.name;
		foreach (a : child.aliases) if (close_enough(typed, a)) return child.name;
	}
	return "";
}

fn String flag_suggestion(Command* cur, String typed) @private
{
	String best;
	cur.@each_flag(; Flag* f, bool inherited)
	{
		if (!best.len && !f.hidden && close_enough(typed, f.name)) best = f.name;
	};
	return best;
}
