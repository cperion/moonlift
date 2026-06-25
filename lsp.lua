#!/usr/bin/env luajit

package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

-- DAP server support: if --debug flag is set, create a DAP handler.
-- When the editor launches lsp.lua with --debug, it shares the same
-- STDIO channel for both LSP and DAP messages.
local dap_handler = nil
local args = {...}
for i = 1, #args do
    if args[i] == "--debug" then
        local DapServer = require("lalin.dap_server")
        -- DAP handler is created lazily; the Back schema and cmds
        -- are populated when a debug session is launched.
        dap_handler = DapServer.new({})
        break
    end
end

require("lalin.rpc_stdio_loop").run({
    dap_handler = dap_handler,
})
