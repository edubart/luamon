package = "luamon"
version = "0.4.4-1"
source = {
  url = "git://github.com/edubart/luamon.git",
  tag = "v0.4.4"
}
description = {
  summary = "Watch source changes and automatically restart (for live development)",
  detailed = [[Luamon is a utility that will monitor for any changes
in your sources and automatically restart it.
Best used for live development. It uses the inotify API.
  ]],
  homepage = "https://github.com/edubart/luamon",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  'luaposix >= 34.0.4',
  'luafilesystem >= 1.7.0',
  'argparse >= 0.6.0',
  'inotify >= 0.5.0',
  'lua-term >= 0.7'
}
build = {
  type = "builtin",
  modules = {},
  install = {
    bin = {
      ['luamon'] = 'luamon.lua'
    }
  }
}
