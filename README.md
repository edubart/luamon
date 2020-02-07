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

You can run with different lua binary with `-l`:

```bash
luamon -l luajit myscript.lua
```

By default it watches for any `.lua` file change in the working directory and runs `lua`.
Alternatively you can monitor different extensions with `-e` and run any command with `-x`:

```bash
luamon -e js -x "nodejs app.js my args"
```

You could use for quick compile and testing C applications to:

```bash
luamon -e c,h -x "make && make test"
```

## Help

```
Usage: luamon [-h] [-v] [-q] [-V] [-f] [-o] [-s] [-x] [-r] [-t]
       [--no-color] [--no-hup] [-e <ext>] [-w <watch>] [-i <ignore>]
       [-c <chdir>] [-d <delay>] [-l <lang>] [--args <args>] <input>
       [<runargs>] ...

luamon

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
      -e <ext>,          Extensions to watch, separated by commas (default: lua)
   --ext <ext>
        -w <watch>,      Directories to watch, separated by commas (default: .)
   --watch <watch>
         -i <ignore>,    Shell pattern of paths to ignore, separated by commas (default: .*)
   --ignore <ignore>
        -c <chdir>,      Change into directory before running the command
   --chdir <chdir>
        -d <delay>,      Delay between restart in milliseconds
   --delay <delay>
       -l <lang>,        Language binary to run (default if not detected: lua)
   --lang <lang>
   --args <args>         Arguments to pass to the language binary
```

## Limitations

The packages depends on POSIX and Inotify APIs so it works only on systems that supports them, such as Linux.

## License
MIT
