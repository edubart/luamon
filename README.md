# Luamon

Luamon is a utility for quick live development in Lua.
It will monitor for any changes in your source and automatically restart your Lua script or application.
It works by watching for file and directories changes using the [inotify API](https://en.wikipedia.org/wiki/Inotify).
It was inspired by [nodemon](https://nodemon.io/), but made for Lua.

[![asciicast](https://asciinema.org/a/eYx200v7YnHxSWqVet5yjnBpS.svg)](https://asciinema.org/a/eYx200v7YnHxSWqVet5yjnBpS)

## Features

* Automatic restarting of application.
* Default for lua, but easy to run any executable (such as python, make, etc).
* Ignoring specific files or directories.
* Watch specific directories.
* Works with server applications or one time run utilities and REPLs.

## Installation

Install using [LuaRocks](https://luarocks.org/):

```bash
luarocks install luamon
```

## Example Usage

Make sure that you have luarocks binary `PATH` in your environment.
And just run luamon with your script file as the input argument.

```bash
luamon myscript.lua
```

You can pass arguments to the script after `--`:
```bash
luamon myscript.lua -- --arg1 arg2
```

You can run with a different lua or any other language runner with `-l`:

```bash
luamon -l luajit myscript.lua
```

By default luamon tries to detect the language to be run and watches file extensions based
on the detect language, for example in case you to run some file with `.lua` extension
then it watches for any `.lua` file change in the working directory and runs `lua`.

Alternatively you can monitor different extensions with `-e`, for running python3 scripts
for example you could do:

```bash
luamon -l python3 -e py myscript.py
```

Although you can just run python scripts by doing:

```bash
luamon myscript.py
```

Alternatively you can run any command with `-x`:

```bash
luamon -e js -x "nodejs app.js my args"
```

You could use for quick compile and testing C applications too:

```bash
luamon -e c,h -x "make && make test"
```

## Advanced Usage

You can make more complex commands for live coding and testing:

```bash
luamon -e c,h,Makefile -l "make <input> && ./build/<input> <args>" example hello
```

The above calls `make example && ./build/example hello` on every `.h`, `.c` or `Makefile` file change.

Any option can be saved to a config file globally called `.luamonrc` in the user home folder
or locally in the running folder, for example:

```bash
ext = {'h', 'c', 'Makefile'}
lang = "make <input> && ./build/<input> <args>"
```

Then you can just call:

```bash
luamon example
```

And will run as the example before.

You can override the languages to be detected in that config too, for example to make it uses
always lua5.4 and python3 upon detection:

```bash
langs = {
  lua = {lang = 'lua5.4', ext = {'lua'}},
  python = {lang = 'python3', ext = {'py'}, ignore = {'.*', '*__pycache__*'}},
}
```

Some common languages comes pre configured like Lua, Python and Ruby,
for all see the default config in luamon sources.

## Help

```
Usage: luamon [-h] [-v] [-q] [-V] [-f] [-o] [-s] [-x] [-r] [-t]
       [--no-color] [--no-hup] [-e <ext>] [-w <watch>] [-i <ignore>]
       [-c <chdir>] [-d <delay>] [-l <lang>] <input> [<args>] ...

luamon

Arguments:
   input                 Input script to run
   args                  Script arguments

Options:
   -h, --help            Show this help message and exit.
   -v, --version         Print current luamon version and exit
   -q, --quiet           Be quiet, don't print any message
   -V, --verbose         Show details on what is causing restart
   -f, --fail-exit       Exit when the running command fails
   -o, --only-input      Watch only the input file for changes
   -s, --skip-first      Skip first run (wait for changes before running)
   -x, --exec            Execute a command instead of running a script
   -r, --restart         Automatically restart upon exit (run forever)
   -t, --term-clear      Clear terminal before each run
   --no-color            Don't colorize output
   --no-hup              Don't stop when terminal closes (SIGHUP signal)
      -e <ext>,          Extensions to watch, separated by commas (auto detected by default)
   --ext <ext>
        -w <watch>,      Directories to watch, separated by commas (default: .)
   --watch <watch>
         -i <ignore>,    Shell pattern of paths to ignore, separated by commas (default: .*)
   --ignore <ignore>
        -c <chdir>,      Change into directory before running the command
   --chdir <chdir>
        -d <delay>,      Delay between restart in milliseconds
   --delay <delay>
       -l <lang>,        Language runner to run (auto detected by default)
   --lang <lang>
```

## Limitations

The packages depends on POSIX and Inotify APIs so it works only on systems that supports them, such as Linux.

## License
MIT
