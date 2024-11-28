module serp::getopt;

import std::collections::list;
import std::io;

struct Flag
{
	char    shortopt;
	String 	longopt;
	bool 	optarg;
	String  desc;
}

struct Option (Printable)
{
	inline Flag flag;
	String arg;
}

fn usz! Option.to_format(&opt, Formatter *f) @dynamic
{
	usz n;
	if (opt.shortopt) n+= f.printf("-%c", opt.shortopt)!;
	if (opt.shortopt && opt.longopt) n += f.printf(", ")!;
	if (opt.longopt) n += f.printf("--%s", opt.longopt)!;
	if (opt.optarg) n += f.printf(" %s", opt.arg)!;
	if (opt.desc) n += f.printf("\t%s", opt.desc)!;
	if (n > 0) n += f.printf("\n")!;
	return n;
}

fault Error
{
	UNKNOWN_OPTION,
	MISSING_ARGUMENT
}

<*
 Parses command-line arguments..
 
 @param [in] args "Strings of options."
 @param [in] flags "Specification of options."
 @param [out] optind "Index of the first non-option argument"

 @require args.len > 0
 @return "Slice of options. Allocated on heap by default."
 @return! Error.UNKNOWN_OPTION, Error.MISSING_ARGUMENT

*>
fn Option[]! parse(String[] args, Flag[] flags, int *optind, Allocator allocator)
{
	int i;

	List(<Option>) opts;
	opts.temp_init(flags.len);

	// remove program name
	args = args[1..];
	i++;

	// parse arguments
	while LOOP: (args.len) {
		String arg = args[0];

		switch {
		case arg == "--":
			i++;
			break LOOP;
		case arg == "-":
			break LOOP;
		case arg.len == 0:
		 	break LOOP;
		case arg[0] != '-':
		 	break LOOP;
		}

		arg = arg[1..];
		if (arg.len > 0 && arg[0] == '-')
		{
			// parse long flag options
			arg = arg[1..];
			Flag flag;
			foreach (f : flags)
			{
				if (f.longopt == arg)
				{
					flag = f;
					break;
				}
			}
			if (flag.longopt.len == 0) return Error.UNKNOWN_OPTION?;
			if (flag.optarg) {
				if (args.len >= 2) {
					args = args[1..];
					i++;
					opts.push({.flag=flag, .arg=args[0]});
				} else {
					return Error.MISSING_ARGUMENT?;
				}
			} else {
				opts.push({.flag=flag});
			}
		}
		else
		{
			// parse single flag options
			foreach (c : arg) {
				Flag flag;
				foreach (f : flags)
				{
					if (f.shortopt == c)
					{
						flag = f;
						break;
					}
				}
				if (flag.shortopt == 0) return Error.UNKNOWN_OPTION?;
				if (flag.optarg) {
					if (args.len >= 2) {
						args = args[1..];
						i++;
						opts.push({.flag=flag, .arg=args[0]});
					} else {
						return Error.MISSING_ARGUMENT?;
					}
				} else {
					opts.push({.flag=flag});
				}
			}
		}

		args = args[1..];
		i++;
	}

	if (optind) {
		*optind = i;
	}
	
	return opts.to_new_array(allocator);
}

fn Option[]! parse_new(String[] args, Flag[] flags, int *optind = null) @inline
{
	return parse(args, flags, optind, allocator::heap());
}

fn Option[]! parse_temp(String[] args, Flag[] flags, int *optind = null) @inline
{
	return parse(args, flags, optind, allocator::temp());
}

fn Option[]! getopts(String[] args, String optstr, int *optind = null, Allocator allocator)
{
	@pool()
	{
		Flag[] flags = mem::temp_alloc_array(Flag, optstr.len);
		int i = 0;
		foreach (c : optstr)
		{
			if (c == ':')
			{
				flags[i].optarg = true;
			}
			else
			{
				flags[i].shortopt = c;
				i++;
			}
		}
		return parse(args, flags, optind, allocator);
	};
}

fn Option[]! getopts_new(String[] args, String optstr, int *optind = null) @inline
{
	return getopts(args, optstr, optind, allocator::heap());
}

fn Option[]! getopts_temp(String[] args, String optstr, int *optind = null) @inline
{
	return getopts(args, optstr, optind, allocator::temp());
}

