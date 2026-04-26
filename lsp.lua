#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

require("moonlift.lsp_server").new():run_stdio()
