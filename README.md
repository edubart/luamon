# Luamon
Luamon is a utility that will monitor for any changes in your sources and automatically restart it. Best used for live development. It works by
watching for file and directories changes using the `inotify` API.

It was inspirated by nodemon, but made for Lua.

## Features

* Default support for lua scripts, but easy to run any executable (such as other langs, make, etc)
* Ignoring specific files or directories
* Watch specific directories
* Works with server applications or one time run utilities and REPLs.

## Installation

Install it using luarocks.

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

Alternativily you can run any command with `-x`:
```bash
luamon -e js -x "nodejs app.js my args"
```

By default it watches for any lua file change in the working directory,
with option `-e` you can specify which .

## Help
```
Usage: luamon [-h] [-v] [-q] [-V] [-f] [-o] [-s] [-x] [-r] [-t]
       [--no-color] [--no-hup] [-e <ext>] [-w <watch>] [-i <ignore>]
       [-l <lua>] [-c <chdir>] [-d <delay>] <input> [<runargs>] ...

luamon 0.3.3

Arguments:
   input                 Input lua script to run
   runargs               Script arguments

Options:
   -h, --help            Show this help message and exit.
   -v, --version         Print current luamon version and exit
   -q, --quiet           Be quiet, luamon don't print any message
   -V, --verbose         Show details on what is causing restart
   -f, --fail-exit       Exit when the running command fails
   -o, --only-input      Watch only the input file for changes
   -s, --skip-first      Skip first run (wait for changes before running)
   -x, --exec            Execute a command instead of running lua script
   -r, --restart         Automatically restart upon exit (run forever)
   -t, --term-clear      Clear terminal before each run
   --no-color            Don't colorize output
   --no-hup              Don't stop when terminal closes (SIGHUP signal)
      -e <ext>,          Extensions to watch, separated by commas
   --ext <ext>
        -w <watch>,      Directories to watch, separated by commas
   --watch <watch>
         -i <ignore>,    Shell pattern of paths to ignore, separated by commas
   --ignore <ignore>
      -l <lua>,          Lua binary to run (or any other binary)
   --lua <lua>
        -c <chdir>,      Change into directory before running the command
   --chdir <chdir>
        -d <delay>,      Delay between restart in milliseconds
   --delay <delay>
```

## Limitations

The packages depends on POSIX and [Inotify](https://en.wikipedia.org/wiki/Inotify) API so it works only on systems that supports them, such as Linux.

## License
MIT
