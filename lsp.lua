#!/usr/bin/env luajit

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

require("moonlift.rpc_stdio_loop").run()
