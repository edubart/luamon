#!/usr/bin/env lua

local inotify = require 'inotify'
local plpath = require 'pl.path'
local pldir = require 'pl.dir'
local plutil = require 'pl.utils'
local signal = require 'posix.signal'
local posix = require 'posix'
local unistd = require 'posix.unistd'
local wait = require 'posix.sys.wait'.wait
local poll = require 'posix.poll'.poll
local argparse = require 'argparse'
local lfs = require 'lfs'
local colors = require 'term.colors'
local stringx = require 'pl.stringx'
local termio = require 'posix.termio'
local unpack = table.unpack or unpack

local VESION = 'luamon 0.2.1'
local options = {}
local wachedpaths = {}
local fds = {}
local notifyhandle
local runcmd
local runpid
local stdin_state = termio.tcgetattr(unistd.STDIN_FILENO)
local stdout_state = termio.tcgetattr(unistd.STDOUT_FILENO)
local stderr_state = termio.tcgetattr(unistd.STDERR_FILENO)

local watch_events = {
  inotify.IN_CLOSE_WRITE,
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
  if not options.no_color then
    io.stderr:write(tostring(color))
  end
  io.stderr:write(message)
  if not options.no_color then
    io.stderr:write(tostring(colors.reset))
  end
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
  if args and #args > 0 then
    for i,arg in ipairs(args) do
      args[i] = plutil.quote_arg(arg)
    end
    cmd = cmd .. ' ' .. table.concat(args, ' ')
  end
  runcmd = cmd
end

local function split_args_action(opts, name, value)
  opts[name] = stringx.split(value, ',')
end

local function parse_args()
  local argparser = argparse("luamon", VESION)
  argparser:flag('-v --version',    "Print current luamon version and exit"):action(function()
    print(VESION)
    os.exit(0)
  end)
  argparser:flag('-q --quiet',      "Be quiet, luamon don't print any message")
  argparser:flag('-V --verbose',    "Show details on what is causing restart")
  argparser:flag('-f --fail-exit',  "Exit when the running command fails")
  argparser:flag('-s --skip-first', "Skip first run (wait for changes before running)")
  argparser:flag('-x --exec',       "Execute a command instead of running lua script")
  argparser:flag('-r --restart',    "Automatically restart upon exit (run forever)")
  argparser:flag('--no-color',      "Don't colorize output")
  argparser:flag('--no-hup',        "Don't stop when terminal closes (SIGHUP signal)")
  argparser:option('-e --ext',
    "Extensions to watch, separated by commas", "lua")
    :action(split_args_action)
  argparser:option('-w --watch',
    "Files/directories to watch, separated by commas", '.')
    :action(split_args_action)
  argparser:option('-i --ignore',
    "Shell pattern of paths to ignore, separated by commas", ".*")
    :action(split_args_action)
  argparser:option('-l --lua',      "Lua binary to run (or any other binary)", "lua")
  argparser:option('-c --chdir',    "Change into directory before running the command")
  argparser:option('-d --delay',    "Delay between restart in seconds")
  argparser:argument("input",       "Input lua script to run")
  argparser:argument("runargs", "Script arguments"):args("*")
  options = argparser:parse()
  if options.chdir then
    options.chdir = plpath.abspath(options.chdir)
  end
end

local function init_inotify()
  notifyhandle = inotify.init()
  fds[notifyhandle:getfd()] = {events={IN=true}, inotify=true}
end

local function terminate_inotify()
  if notifyhandle then
    notifyhandle:close()
  end
  notifyhandle = nil
end

local function fix_terminal()
  termio.tcsetattr(unistd.STDIN_FILENO, termio.TCSANOW, stdin_state)
  termio.tcsetattr(unistd.STDOUT_FILENO, termio.TCSANOW, stdout_state)
  termio.tcsetattr(unistd.STDERR_FILENO, termio.TCSANOW, stderr_state)
end

local function killpid(pid)
  if not pid then return true end
  local status = signal.kill(-pid, signal.SIGKILL) -- kill process group
  return status == 0
end

local function exit(code)
  terminate_inotify()
  if runpid then
    killpid(runpid)
    wait(runpid)
    fix_terminal()
  end
  os.exit(code)
end

local function parent_handle_signal()
  exit(-1)
end

local function setup_signal_handler(child)
  if not child then
    signal.signal(signal.SIGINT, parent_handle_signal)
    signal.signal(signal.SIGTERM, parent_handle_signal)
    if not options.no_hup then
      signal.signal(signal.SIGHUP, parent_handle_signal)
    end
  else
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    if not options.no_hup then
      signal.signal(signal.SIGHUP, signal.SIG_DFL)
    end
  end
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
    colorprintf(colors.yellow, '[luamon] added watch to %s', path)
  end
  if not plpath.exists(path) then
    colorprintf(colors.red, "[luamon] path '%s' does not exists for watching", path)
    exit(-1)
  end
  assert(notifyhandle:addwatch(path, unpack(watch_events)))
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
  for _,dir in ipairs(options.watch) do
    local path = plpath.abspath(dir)
    if not options.quiet then
      colorprintf(colors.yellow, '[luamon] watching "%s"', path)
    end
    watch(path)
  end
end

local function forkexecute(cmd)
  local rpipe, wpipe = assert(unistd.pipe())
  local pid = assert(unistd.fork())
  if pid == 0 then -- child
    setup_signal_handler(true)
    assert(unistd.setpid('s')) -- new process group
    notifyhandle:close()
    unistd.close(rpipe)
    local _, status = plutil.execute(cmd)
    unistd._exit(status)
  else -- parent
    unistd.close(wpipe)
    fds[rpipe] = {pid = pid, events={}}
  end
  return pid
end

local function run()
  if options.chdir then
    plpath.chdir(options.chdir)
  end
  if not options.quiet then
    colorprintf(colors.yellow, '[luamon] starting `%s`', runcmd)
  end

  runpid = forkexecute(runcmd)
end

local function run_finish(pid, reason, status)
  assert(pid == runpid, 'finished child pid is not the running pid')
  runpid = nil
  fix_terminal()
  if reason == 'exited' then
    if status ~= 0 then
      if options.fail_exit then
        if not options.quiet then
          colorprintf(colors.red, '[luamon] exited with code %d', status)
        end
        terminate_inotify()
        exit(status)
      elseif not options.quiet then
        colorprintf(colors.red, '[luamon] exited with code %d', status)
        return options.restart
      end
    elseif not options.quiet then
      colorprintf(colors.green, '[luamon] clean exit')
      return options.restart
    end
  else
    colorprintf(colors.magenta, '[luamon] killed')
    return true
  end
end

local function is_watched_extesion(path)
  for _,ext in ipairs(options.ext) do
    if stringx.endswith(path, '.' .. ext) then
      return true
    end
  end
end

local function check_if_should_restart(path)
  if not path or is_ignored(path) then return false end
  if plpath.isdir(path) then
    if not wachedpaths[path] then
      addwatch(path)
    end
    for name in lfs.dir(path) do
      if is_watched_extesion(name) then
        return true
      end
    end
  end
  return is_watched_extesion(path)
end

local function check_changes()
  local changed = false
  local events = notifyhandle:read()
  for _,ev in ipairs(events) do
    local name = ev.name
    if check_if_should_restart(name) then
      if options.verbose then
        colorprintf(colors.yellow, '[luamon] %s changed', ev.name)
      end
      changed = true
    end
  end
  if changed and runpid then
    return not killpid(runpid)
  end
  return changed
end

local function pollfds()
  local dorun = false
  assert(poll(fds), 'poll failed')
  for fd, fdt in pairs(fds) do
    if fdt.revents.IN and fdt.inotify then
      if check_changes() then
        dorun = true
      end
    end
    if fdt.revents.HUP and not fdt.inotify then
      local pid, reason, status = assert(wait(fdt.pid))
      assert(pid == fdt.pid, 'got HUP from unexected fd')
      unistd.close(fd)
      fds[fd] = nil
      if run_finish(pid, reason, status) then
        dorun = true
      end
    end
  end
  return dorun
end

local function watch_and_restart()
  if not options.skip_first then
    run()
  else
    colorprintf(colors.yellow, '[luamon] waiting for changes...')
  end
  while true do
    if pollfds() then
      assert(runpid == nil, 'trying to run while a child is already running')
      if options.delay then
        posix.sleep(options.delay)
      end
      run()
    end
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
