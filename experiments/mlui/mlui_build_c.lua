-- mlui_build_c.lua -- Build the MLUI C amalgam from the public file API.
--
-- .mlua files are Lua programs that produce Moonlift values.  The build
-- boundary is moon.emit_c_file, which executes the module, follows
-- moon.require dependencies, bundles the resulting values, and emits C.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;experiments/mlui/?.lua;experiments/mlui/?.mlua;" .. package.path

local moon = require("moonlift")

local M = {}

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function M.emit_c_source(opts)
    opts = opts or {}
    local emit_opts = {}
    for k, v in pairs(opts) do emit_opts[k] = v end
    emit_opts.site = emit_opts.site or "mlui C amalgam"
    return moon.emit_c_file("experiments/mlui/mlui_abi.mlua", nil, opts.name or "mlui", emit_opts)
end

function M.write_c(path, opts)
    path = path or "experiments/mlui/mlui_amalgam.c"
    local src = M.emit_c_source(opts)
    local f = assert(io.open(path, "wb"))
    f:write(src)
    f:close()
    return src, path
end

function M.compile_object(opts)
    opts = opts or {}
    local c_path = opts.c_path or "experiments/mlui/mlui_amalgam.c"
    local o_path = opts.o_path or "experiments/mlui/mlui_amalgam.o"
    local cc = opts.cc or os.getenv("CC") or "gcc"
    local cflags = opts.cflags or "-O3 -std=c99 -Iexperiments/mlui"
    local cmd = table.concat({
        cc, cflags, "-c", shell_quote(c_path), "-o", shell_quote(o_path)
    }, " ")
    local ok = os.execute(cmd)
    assert(ok == true or ok == 0, "C compile failed: " .. cmd)
    return o_path
end

function M.build(opts)
    opts = opts or {}
    local src, c_path = M.write_c(opts.c_path, opts)
    local o_path
    if opts.compile ~= false then
        o_path = M.compile_object({
            c_path = c_path,
            o_path = opts.o_path,
            cc = opts.cc,
            cflags = opts.cflags,
        })
    end
    return {
        c_path = c_path,
        o_path = o_path,
        bytes = #src,
    }
end

if ... == nil then
    local result = M.build({})
    io.write(string.format("MLUI C: %s (%d bytes)\n", result.c_path, result.bytes))
    if result.o_path then io.write("MLUI object: " .. result.o_path .. "\n") end
end

return M
