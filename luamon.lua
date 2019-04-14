#!/usr/bin/env lua

local inotify = require 'inotify'
local plpath = require 'pl.path'
local pldir = require 'pl.dir'
local plutil = require 'pl.utils'
local signal = require 'posix.signal'
local posix = require 'posix'
local argparse = require 'argparse'
local lfs = require 'lfs'
local unpack = table.unpack or unpack

local VESION = 'luamon 0.1'
local options = {}
local notifyhandle
local runcmd

local watch_events = {
  inotify.IN_CLOSE_WRITE,
  inotify.IN_CREATE,
  inotify.IN_DELETE,
  inotify.IN_DELETE_SELF,
  inotify.IN_MOVE_SELF,
  inotify.IN_MOVE
}

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

local function build_runcmd()
  local cmd
  if options.exec then
    cmd = options.input
  else
    cmd = string.format('%s %s', options.lua, options.input)
  end

  local args = options.runargs
  if args then
    for i,arg in ipairs(args) do
      args[i] = plutil.quote_arg(arg)
    end
    cmd = cmd .. ' ' .. table.concat(args, ' ')
  end
  runcmd = cmd
end

local function parse_args()
  local argparser = argparse("luamon", VESION)
  argparser:flag('-v --version',    "Print current luamon version"):action(function()
    print(VESION)
    os.exit(0)
  end)
  argparser:flag('-q --quiet',      "Be quiet, luamon don't any message")
  argparser:flag('-V --verbose',    "Show details on what is causing restart")
  argparser:flag('-f --fail-exit',  "Exit when the running command fails")
  argparser:flag('-s --skip-first   "Skip first run (wait for changes before running)"')
  argparser:flag('-x --exec',       "Execute a command instead of running lua script")
  argparser:option('-e --ext',      "Extensions to watch", "lua"):args('+')
  argparser:option('-w --watch',    "Files/directories to watch", '.'):args('+')
  argparser:option('-i --ignore',   "Files/directories to ignore", ".*"):args('+')
  argparser:option('-l --lua',      "Lua binary", "lua")
  argparser:option('-c --chdir',    "Change into directory before running the command")
  argparser:option('-d --delay',    "Delay between restart in seconds")
  argparser:argument("input",       "Input lua script to run")
  argparser:argument("runargs"):args("*")
  options = argparser:parse()
  if options.chdir then
    options.chdir = plpath.abspath(options.chdir)
  end
end

local function init_inotify()
  notifyhandle = inotify.init()
end

local function terminate_inotify()
  if notifyhandle then
    notifyhandle:close()
  end
  notifyhandle = nil
end

local function handle_signal(signum)
  terminate_inotify()
  io.stderr:write(string.format("terminated with signal %d\n", signum))
  os.exit(-1)
end

local function setup_signal_handler()
  signal.signal(signal.SIGINT, handle_signal)
  signal.signal(signal.SIGTERM, handle_signal)
end

local function is_ignored(name)
  if name == '.' or name == '..' then return true end
  for _,patt in ipairs(options.ignore) do
    if pldir.fnmatch(name, patt) then
      return true
    end
  end
  return false
end

local function addwatch(path)
  if options.verbose then
    eprintf('Adding watch to %s', path)
  end
  notifyhandle:addwatch(path, unpack(watch_events))
end

local function watch(path)
  addwatch(path)
  if plpath.isdir(path) then
    for name in lfs.dir(path) do
      if not is_ignored(name) then
        local subpath = plpath.join(path, name)
        if plpath.isdir(subpath) then
          watch(subpath)
        end
      end
    end
  end
end

local function setup_watch_dirs()
  for _,dir in ipairs(options.watch) do
    local path = plpath.abspath(dir)
    if not options.quiet then
      eprintf('Watching "%s"', path)
    end
    watch(path)
  end
end

local function run()
  if options.chdir then
    plpath.chdir(options.chdir)
  end
  if not options.quiet then
    eprintf('Running...')
  end
  if options.verbose then
    eprintf(runcmd)
  end

  local ok, status = plutil.execute(runcmd)
  if not ok then
    terminate_inotify()
    error(ok, status)
  elseif status ~= 0 and options.fail_exit then
    if not options.quiet then
      eprintf('Exited with code %d', status)
    end
    terminate_inotify()
    os.exit(status)
  end
end

local function wait_changes()
  if not options.quiet then
    eprintf('Ended, waiting for changes...')
  end
  repeat
    local found = false
    local events = notifyhandle:read()
    for _,ev in ipairs(events) do
      local name = ev.name
      if not is_ignored(name) then
        if options.verbose then
          eprintf('%s changed', ev.name)
        end
        found = true
      end
    end
  until found
  if options.delay then
    posix.sleep(options.delay)
  end
end

local function watch_and_restart()
  if not options.skip_first then
    run()
  end
  while true do
    wait_changes()
    run()
  end
end

do
  parse_args()
  build_runcmd()
  setup_signal_handler()
  init_inotify()
  setup_watch_dirs()
  watch_and_restart()
  terminate_inotify()
end
