- Persistent flags:

     `Command.add_persistent_flag(..)`

    Persistent flag must then be passed down the call stack.

- Required flags:

    Have an option to set `bool required`. Which is also validated (see args
    validator).

- Args validator for positional arguments
    `Command.args` (probably same function ptr as for run?)

    1. NoArgs
    2. ArbitraryArgs
    3. MinimumNArgs(int)
    4. MaximumNArgs(int)
    5. ExactArgs(int)
    6. RangeArgs(min, max)
