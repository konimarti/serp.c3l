module getopt_test;

import serp::getopt;

struct TestCase
{
	String cmdline;
	Flag[] flags;
	Option[] want;
}

macro Flag shortopt(char c, bool arg = false)
{
	return {.shortopt = c, .optarg = arg};
}

macro Flag longopt(String s, bool arg = false)
{
	return {.longopt = s, .optarg = arg};
}

macro Flag opt(char c, String s, bool arg = false)
{
	return {.shortopt = c, .longopt = s, .optarg = arg};
}

macro bool cmp(a, b) {
	return a.shortopt == b.shortopt && a.longopt == b.longopt && a.arg == b.arg;
}

fn void test_getopts() @test {

	TestCase[] tests = {
		{
			.cmdline = "app -a",
			.flags = {shortopt('a')},
			.want = {{.flag = shortopt('a')}},
		},
		{
			.cmdline = "app -a",
			.flags = {shortopt('a'), shortopt('b')},
			.want = {{.flag = shortopt('a')}},
		},
		{
			.cmdline = "app -ab",
			.flags = {shortopt('a'), shortopt('b')},
			.want = {{.flag = shortopt('a')},{.flag = shortopt('b')}},
		},
		{
			.cmdline = "app -b -a",
			.flags = {shortopt('a'), shortopt('b')},
			.want = {{.flag = shortopt('b')},{.flag = shortopt('a')}},
		},
		{
			.cmdline = "app --version",
			.flags = {longopt("version")},
			.want = {{.flag = longopt("version")}},
		},
		{
			.cmdline = "app",
			.flags = {longopt("version")},
			.want = {},
		},
		{
			.cmdline = "app -a --version",
			.flags = {shortopt('a'), longopt("version")},
			.want = {{.flag = shortopt('a')},{.flag = longopt("version")}},
		},
		{
			.cmdline = "app --version 1.0",
			.flags = {opt('v', "version", true)},
			.want = {{.flag = opt('v', "version", true), .arg = "1.0"}},
		},
		{
			.cmdline = "app -v 1.0",
			.flags = {opt('v', "version", true)},
			.want = {{.flag = opt('v', "version", true), .arg = "1.0"}},
		},
		{
			.cmdline = "app -av 1.0",
			.flags = {shortopt('a'), opt('v', "version", true)},
			.want = {{.flag = shortopt('a')},{.flag = opt('v', "version", true), .arg = "1.0"}},
		},
	};

	@pool()
	{
		foreach (t : tests) {
			Option[] opts = getopt::parse_temp(t.cmdline.tsplit(" "), t.flags)!!;
			assert(opts.len == t.want.len, "wrong length: got: %d, want: %d", opts.len, t.want.len);
			foreach (i, got : opts) {
				assert(cmp(got, t.want[i]), "wrong option: got: %s, want: %s", got, t.want[i]);
			}
		}
	};
}


