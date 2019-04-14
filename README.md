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

By default it watches for any file change in the working directory.

## Help
```
Usage: luamon [-v] [-q] [-V] [-f] [-s] [-x] [--no-color] [-e <ext>]
       [-w <watch>] [-i <ignore>] [-l <lua>] [-c <chdir>] [-d <delay>]
       [-h] <input> [<runargs>] ...

luamon 0.1

Arguments:
   input                 Input lua script to run
   runargs               Script arguments

Options:
   -v, --version         Print current luamon version and exit
   -q, --quiet           Be quiet, luamon don't any message
   -V, --verbose         Show details on what is causing restart
   -f, --fail-exit       Exit when the running command fails
   -s, --skip-first      Skip first run (wait for changes before running)
   -x, --exec            Execute a command instead of running lua script
   --no-color            Don't colorize output
      -e <ext>,          Extensions to watch, separated by commas (default: lua)
   --ext <ext>
        -w <watch>,      Files/directories to watch, separated by commas (default: .)
   --watch <watch>
         -i <ignore>,    Files/directories shell patterns to ignore, separated by commas (default: .*)
   --ignore <ignore>
      -l <lua>,          Lua binary (default: lua)
   --lua <lua>
        -c <chdir>,      Change into directory before running the command
   --chdir <chdir>
        -d <delay>,      Delay between restart in seconds
   --delay <delay>
   -h, --help            Show this help message and exit.
```

## Limitations

The packages depends on POSIX and [Inotify](https://en.wikipedia.org/wiki/Inotify) API so it works only on systems that supports them, such as Linux.

## License
MIT
