#!/usr/bin/env lua

local inotify = require 'inotify'
local plpath = require 'pl.path'
local signal = require 'posix.signal'
local argparse = require 'argparse'
local unpack = table.unpack or unpack

local VESION = 'luamon 0.1'

local function handle_signal(signum)
  io.stderr:write(string.format("terminate with signal %d\n", signum))
  os.exit(-1)
end

local function eprintf(format, ...)
  local message
  if select('#', ...) > 0 then
    message = string.format(format, ...)
  else
    message = format
  end
  io.stderr:write(message)
  io.stderr:write('\n')
  io.stderr:flush()
end

signal.signal(signal.SIGINT, handle_signal)

local argparser = argparse("luamon", VESION)
argparser:flag('-v --version',    "Print current luamon version"):action(function()
  print(VESION)
  os.exit(0)
end)
argparser:flag('-q --quiet',      "Be quiet, luamon don't any message")
argparser:flag('-V --verbose',    "Show details on what is causing restart")
argparser:flag('-t --exit',       "Exit when the running command fails")
argparser:flag('-s --skip-first   "Skip first run (wait for changes before running)"')
argparser:option('-e --ext',      "Extensions to watch", "lua"):args('+')
argparser:option('-w --watch',    "Files/directories to watch", '.'):args('+')
argparser:option('-i --ignore',   "Files/directories to ignore"):args('+')
argparser:option('-x --exec',     "Command to execute instead of running lua script")
argparser:option('-c --chdir',    "Change into directory before running the command")
argparser:option('-d --delay',    "Delay between restart")
argparser:argument("input",       "Input lua script to run")
argparser:argument("runargs"):args("*")
local options = argparser:parse()

--dump(options)

local watch_events = {
  inotify.IN_MODIFY,
  inotify.IN_CLOSE_WRITE,
  inotify.IN_CREATE,
  inotify.IN_DELETE,
  inotify.IN_DELETE_SELF,
  inotify.IN_MODIFY,
  inotify.IN_MOVE_SELF,
  inotify.IN_MOVE,
  inotify.IN_ONLYDIR,
}

local notifyhandle = inotify.init()

for _,dir in ipairs(options.watch) do
  local path = plpath.abspath(dir)
  if not options.quiet then
    eprintf('Watching "%s"', path)
  end
  notifyhandle:addwatch(dir, unpack(watch_events))
end

local events = notifyhandle:read()
for _,ev in ipairs(events) do
  if options.verbose then
    eprintf('%s changed', ev.name)
  end
  if not options.quiet then
    eprintf('Restarting...')
  end
end

notifyhandle:close()
