#!/usr/bin/env lua

--[[
The MIT License (MIT)

Copyright (c) 2020 Eduardo Bart (https://github.com/edubart)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

--[[
Luamon is a utility that will monitor for any changes
in your sources and automatically restart it.
Best used for live development. It uses the inotify API.
]]

local plpath = require 'pl.path'
local plfile = require 'pl.file'
local pldir = require 'pl.dir'
local plutil = require 'pl.utils'
local compat = require 'pl.compat'
local stringx = require 'pl.stringx'
local tablex = require 'pl.tablex'
local signal = require 'posix.signal'
local unistd = require 'posix.unistd'
local wait = require 'posix.sys.wait'
local time = require 'posix.time'
local termio = require 'posix.termio'
local errno = require 'posix.errno'
local inotify = require 'inotify'
local argparse = require 'argparse'
local lfs = require 'lfs'
local colors = require 'term.colors'
local term = require 'term'
local unpack = table.unpack or unpack

local VERSION = 'luamon 0.5.3'

local config = {
  watch = {'.'},
  ignore = {'.*'},
  langs = {
    lua = {lang = 'lua', ext = {'lua'}},
    python = {lang = 'python', ext = {'py'}, ignore = {'.*', '*__pycache__*'}},
    ruby = {lang = 'ruby', ext = {'rb'}},
    node = {lang = 'node', ext = {'js'}},
    c = {lang = 'tcc -run', ext = {'c', 'h'}},
    cpp = {lang = 'g++ -o /tmp/a.out <input> && /tmp/a.out <args>', ext = {'cpp', 'h'}},
    swift = {lang = 'swift', ext = {'swift'}},
    zig = {lang = 'zig run', ext = {'zig'}},
    nim = {lang = 'nim c -r', ext = {'nim'}},
    shell = {lang = 'sh', ext = {'sh'}},
    nelua = {lang = 'nelua', ext = {'nelua', 'lua'}, ignore = {'.*', '*nelua_cache*'}},
  }
}

local wachedpaths = {}
local pathbywd = {}
local notifyhandle
local notifyrunterm
local runcmd
local runpid
local stdin_state = termio.tcgetattr(unistd.STDIN_FILENO)
local stdout_state = termio.tcgetattr(unistd.STDOUT_FILENO)
local stderr_state = termio.tcgetattr(unistd.STDERR_FILENO)
local stdin_tcpgrp = unistd.tcgetpgrp(unistd.STDIN_FILENO)
local run_finish
local lastrun = 0

local watch_events = {
  inotify.IN_CLOSE_WRITE,
  inotify.IN_MODIFY,
  inotify.IN_CREATE,
  inotify.IN_DELETE,
  inotify.IN_DELETE_SELF,
  inotify.IN_MOVE_SELF,
  inotify.IN_MOVE
}

local function colorprintf(color, format, ...)
  local message
  if select('#', ...) > 0 then
    message = string.format(format, ...)
  else
    message = format
  end
  if not config.no_color then
    io.stderr:write(tostring(color))
  end
  io.stderr:write(message)
  if not config.no_color then
    io.stderr:write(tostring(colors.reset))
  end
  io.stderr:write('\n')
  io.stderr:flush()
end

local function build_runcmd()
  local argscmd = ''
  local args = config.args
  if args and #args > 0 then
    for i,arg in ipairs(args) do
      args[i] = plutil.quote_arg(arg)
    end
    argscmd = table.concat(args, ' ')
  end

  local cmd
  if config.exec then
    cmd = config.input
  else
    if config.lang:match('<input>') then
      cmd = config.lang:gsub('<input>', config.input)
      if cmd:match('<args>') then
        cmd = cmd:gsub('<args>', argscmd)
        argscmd = ''
      end
    else
      cmd = config.lang .. ' ' .. config.input
    end
  end

  runcmd = cmd
  if #argscmd > 0 then
    runcmd = runcmd .. ' ' .. argscmd
  end
end

local function split_args_action(opts, name, value)
  opts[name] = stringx.split(value, ',')
end

local function millis()
  local tmspec = assert(time.clock_gettime(time.CLOCK_MONOTONIC))
  return tmspec.tv_sec * 1000 + tmspec.tv_nsec / 1000000
end

local function sleep_until(endmillis)
  repeat
    local ramaining = math.max(endmillis - millis(), 0)
    local tmspec = {
      tv_sec = math.floor(ramaining / 1000),
      tv_nsec = math.floor(ramaining % 1000) * 1000000
    }
    local sleepret = time.nanosleep(tmspec)
  until sleepret == 0 or ramaining == 0
end

local function loadrc(rcfilename)
  if not plpath.exists(rcfilename) then
    return
  end
  local rcfunc, err = compat.load(plfile.read(rcfilename), '@.luamonrc', "t", config)
  local ok
  if rcfunc then
    ok, err = pcall(rcfunc)
  end
  if not ok then
    error(string.format('failed to load luamonrc:\n%s', err))
  end
end

local function parse_args()
  local argparser = argparse("luamon", VERSION)
  argparser:flag('-v --version',    "Print current luamon version and exit"):action(function()
    print(VERSION)
    os.exit(0)
  end)

  argparser:flag('-q --quiet',      "Be quiet, don't print any message")
  argparser:flag('-V --verbose',    "Show details on what is causing restart")
  argparser:flag('-f --fail-exit',  "Exit when the running command fails")
  argparser:flag('-o --only-input', "Watch only the input file for changes")
  argparser:flag('-s --skip-first', "Skip first run (wait for changes before running)")
  argparser:flag('-x --exec',       "Execute a command instead of running a script")
  argparser:flag('-r --restart',    "Automatically restart upon exit (run forever)")
  argparser:flag('-t --term-clear', "Clear terminal before each run")
  argparser:flag('--no-color',      "Don't colorize output")
  argparser:flag('--no-hup',        "Don't stop when terminal closes (SIGHUP signal)")
  argparser:option('-e --ext',
    "Extensions to watch, separated by commas (auto detected by default)")
    :action(split_args_action)
  argparser:option('-w --watch', "Directories to watch, separated by commas (default: .)")
    :action(split_args_action)
  argparser:option('-i --ignore',
    "Shell pattern of paths to ignore, separated by commas (default: .*)")
    :action(split_args_action)
  argparser:option('-c --chdir',    "Change into directory before running the command")
  argparser:option('-d --delay',    "Delay between restart (in milliseconds)")
  argparser:option('-k --kill-delay', "Delay to kill application after trying to close (in milliseconds)", 20)
  argparser:option('-l --lang',     "Language runner to run (auto detected by default)")
  argparser:argument("input",       "Input script to run")
  argparser:argument("args",        "Script arguments"):args("*")
  local options = argparser:parse()

  -- read personal user config
  loadrc(plpath.expanduser('~/.luamonrc'))
  loadrc('.luamonrc')

  -- read detected language default config
  if not config.lang and not config.exec then
    for lang,langconfig in pairs(config.langs) do
      if options.lang == lang or
         options.lang == langconfig.lang or
         options.input:match('%.' .. langconfig.ext[1] .. '$') then
        tablex.update(config, langconfig)
        break
      end
    end
  end

  -- read parsed config
  tablex.update(config, options)

  if not config.lang and not config.exec then
    colorprintf(colors.red, "[luamon] could not detect language to run (missing -l?)")
    os.exit(1)
  end

  if not config.ext then
    colorprintf(colors.red, "[luamon] could not detect file extension to watch (missing -e?)")
    os.exit(1)
  end

  if config.chdir then
    config.chdir = plpath.abspath(config.chdir)
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

local function restore_terminal()
  -- fix any mess with the terminal outputs (when killing REPLs)
  termio.tcsetattr(unistd.STDIN_FILENO, termio.TCSANOW, stdin_state)
  termio.tcsetattr(unistd.STDOUT_FILENO, termio.TCSANOW, stdout_state)
  termio.tcsetattr(unistd.STDERR_FILENO, termio.TCSANOW, stderr_state)
  -- bring the parent process to the foreground
  unistd.tcsetpgrp(unistd.STDIN_FILENO, stdin_tcpgrp)
end

local function kill_wait(pid)
  -- kill child if running
  local wpid, reason, status = wait.wait(-pid, wait.WNOHANG)
  if reason == 'running' then
    -- try to terminate children process gracefully
    signal.kill(-pid, signal.SIGINT)

    -- give some time to process the interrupt signal
    sleep_until(millis() + config.kill_delay)

    -- kill child process group
    signal.kill(-pid, signal.SIGKILL)

    -- wait child process group
    repeat
      wpid, reason, status = wait.wait(-pid)
      if not wpid then
        assert(status == errno.EINTR, reason)
      else
        assert(wpid == pid)
      end
    until wpid
  end

  restore_terminal()
  return reason, status
end

local function exit(code)
  terminate_inotify()
  run_finish()
  os.exit(code)
end

local function exiterror(message, ...)
  colorprintf(colors.red, "[luamon] " .. message, ...)
  exit(-1)
end

local function parent_handle_signal()
  exit(-1)
end

local function parent_handle_child_signal()
  restore_terminal()
  notifyrunterm = true
end

local function setup_signal_handler(child)
  if not child then
    signal.signal(signal.SIGTTOU, parent_handle_child_signal)
    signal.signal(signal.SIGCHLD, parent_handle_child_signal)
    signal.signal(signal.SIGINT, parent_handle_signal)
    signal.signal(signal.SIGTERM, parent_handle_signal)
    if not config.no_hup then
      signal.signal(signal.SIGHUP, parent_handle_signal)
    end
  else
    signal.signal(signal.SIGTTOU, signal.SIG_DFL)
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    if not config.no_hup then
      signal.signal(signal.SIGHUP, signal.SIG_DFL)
    end
  end
end

local function is_ignored(name)
  if name == '.' or name == '..' then return true end
  for _,patt in ipairs(config.ignore) do
    if pldir.fnmatch(name, patt) then
      return true
    end
  end
  return false
end

local function addwatch(path)
  if config.verbose then
    colorprintf(colors.yellow, '[luamon] added watch to %s', path)
  end
  if not plpath.exists(path) then
    exiterror("[luamon] path '%s' does not exists for watching", path)
  end
  local wd = assert(notifyhandle:addwatch(path, unpack(watch_events)))
  pathbywd[wd] = path
  wachedpaths[path] = true
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
  if config.only_input then
    if config.exec then
      exiterror("option --only-input cannot be used with --exec option")
    end
    if #config.watch ~= 1 or config.watch[1] ~= '.' then
      exiterror("option --only-input cannot be used with --watch option")
    end
    local path = plpath.abspath(config.input)
    assert(plpath.exists(path), "input file not found")
    if not config.quiet then
      colorprintf(colors.yellow, '[luamon] watching "%s"', path)
    end
    watch(path)
    return
  end

  for _,dir in ipairs(config.watch) do
    local path = plpath.abspath(dir)
    if not config.quiet then
      colorprintf(colors.yellow, '[luamon] watching "%s"', path)
    end
    watch(path)
  end
end

local function forkexecute(cmd)
  io.stdout:flush()
  io.stderr:flush()
  local pid = assert(unistd.fork())
  if pid == 0 then -- child
    setup_signal_handler(true) --remove singal handlers from child
    notifyhandle:close() -- close unused fd in child
    local _, status = plutil.execute(cmd)
    unistd._exit(status) -- exit child without unitializing
  else -- parent
    assert(unistd.setpid('p', pid, pid)) -- new process group for child
    assert(unistd.tcsetpgrp(unistd.STDIN_FILENO, pid)) -- bring child to the foreground
  end
  return pid
end

local function run()
  if config.chdir then
    plpath.chdir(config.chdir)
  end
  if not config.quiet then
    colorprintf(colors.yellow, '[luamon] starting `%s`', runcmd)
  end
  if config.term_clear then
    term.clear()
    term.cursor.jump(1, 1)
  end
  runpid = forkexecute(runcmd)
end

function run_finish()
  if not runpid then return false end
  local reason, status = kill_wait(runpid)
  runpid = nil
  if reason == 'exited' then
    if status ~= 0 then
      if config.fail_exit then
        if not config.quiet then
          colorprintf(colors.red, '[luamon] exited with code %d', status)
        end
        terminate_inotify()
        exit(status)
      elseif not config.quiet then
        colorprintf(colors.red, '[luamon] exited with code %d', status)
        return config.restart
      end
    elseif not config.quiet then
      colorprintf(colors.green, '[luamon] clean exit')
      return config.restart
    end
  elseif reason == 'killed' then
    colorprintf(colors.magenta, '[luamon] killed')
    return config.restart
  end
end

local function is_watched_extension(path)
  local filename = plpath.basename(path)
  local fileext = plpath.extension(path)
  for _,ext in ipairs(config.ext) do
    if filename == ext or fileext == '.'..ext then
      return true
    end
  end
  return false
end

local function check_if_should_restart(path)
  if config.only_input then return true end
  if millis() - lastrun < 200 then return false end -- change is too recent, ignore
  if not path or is_ignored(plpath.basename(path)) then return false end
  if plpath.isdir(path) then
    if not wachedpaths[path] then
      addwatch(path)
    end
    for name in lfs.dir(path) do
      if is_watched_extension(name) then
        return true
      end
    end
  end
  return is_watched_extension(path)
end

local function wait_restart()
  local changemillis
  repeat
    local restart = false
    local events, reason, errcode = notifyhandle:read()
    if events then
      for _,ev in ipairs(events) do
        local dirpath, name = pathbywd[ev.wd], ev.name
        if dirpath and name then
          local path = plpath.join(pathbywd[ev.wd], ev.name)
          if check_if_should_restart(path) then
            changemillis = millis()
            if config.verbose then
              colorprintf(colors.yellow, '[luamon] %s changed', path)
            end
            run_finish()
            restart = true
          end
        end
      end
    elseif errcode == errno.EINTR then -- signal interrupted
      if notifyrunterm and run_finish() then
        restart = true
      end
    else
      error(reason)
    end
  until restart
  return changemillis
end

local function watch_and_restart()
  if not config.skip_first then
    run()
    lastrun = millis()
  else
    colorprintf(colors.yellow, '[luamon] waiting for changes...')
  end
  while true do
    local changemillis = wait_restart()
    if changemillis then
      -- give some time to finish writing files
      sleep_until(changemillis + 20)
    end
    if config.delay then
      -- give some time between application startups
      sleep_until(lastrun + config.delay)
    end

    run()
    lastrun = millis()
  end
end

local function main()
  parse_args()
  build_runcmd()
  setup_signal_handler()
  init_inotify()
  setup_watch_dirs()
  watch_and_restart()
end

do
  local ok, err = xpcall(main, debug.traceback)
  if not ok then
    colorprintf(colors.red, 'FATAL ERROR: %s', err)
    exit(-1)
  end
end
