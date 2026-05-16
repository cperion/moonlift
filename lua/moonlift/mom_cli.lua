-- CLI policy for the standalone `mom` binary.

local moon = require("moonlift")
local ffi = require("ffi")

local M = {}

local function usage(out)
    out:write([[usage:
  mom status
  mom run [--call NAME] [--ret i32|void] [--arg-i32 N ...] FILE
  mom --emit-object -o OUT.o [--module-name NAME] FILE

The run path compiles FILE and calls NAME (default: main).
The object path emits a relocatable object through the same BackProgram lowering.
]])
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then error("unable to open " .. tostring(path) .. ": " .. tostring(err), 2) end
    local s = f:read("*a")
    f:close()
    return s
end

local function parse(argv)
    local opts = { mode = "run", call = "main", ret = "i32", args_i32 = {} }
    local i = 1
    if argv[i] == "status" then opts.mode = "status"; return opts end
    if argv[i] == "run" then opts.mode = "run"; i = i + 1 end
    while i <= #argv do
        local a = argv[i]
        if a == "--help" or a == "-h" then opts.help = true; return opts
        elseif a == "--emit-object" then opts.mode = "object"
        elseif a == "-o" then i = i + 1; opts.output = argv[i]
        elseif a == "--module-name" then i = i + 1; opts.module_name = argv[i]
        elseif a == "--call" then i = i + 1; opts.call = argv[i]
        elseif a == "--ret" then i = i + 1; opts.ret = argv[i]
        elseif a == "--arg-i32" then i = i + 1; opts.args_i32[#opts.args_i32 + 1] = tonumber(argv[i]) or error("--arg-i32 expects an integer")
        elseif a:sub(1, 1) == "-" then error("unknown option " .. a)
        elseif not opts.input then opts.input = a
        else error("unexpected argument " .. a) end
        i = i + 1
    end
    return opts
end

local function cast_i32(ptr, nargs)
    if nargs == 0 then return ffi.cast("int32_t (*)()", ptr) end
    if nargs == 1 then return ffi.cast("int32_t (*)(int32_t)", ptr) end
    if nargs == 2 then return ffi.cast("int32_t (*)(int32_t,int32_t)", ptr) end
    if nargs == 3 then return ffi.cast("int32_t (*)(int32_t,int32_t,int32_t)", ptr) end
    if nargs == 4 then return ffi.cast("int32_t (*)(int32_t,int32_t,int32_t,int32_t)", ptr) end
    error("mom run supports up to four i32 arguments")
end

local function cast_void(ptr, nargs)
    if nargs == 0 then return ffi.cast("void (*)()", ptr) end
    if nargs == 1 then return ffi.cast("void (*)(int32_t)", ptr) end
    if nargs == 2 then return ffi.cast("void (*)(int32_t,int32_t)", ptr) end
    if nargs == 3 then return ffi.cast("void (*)(int32_t,int32_t,int32_t)", ptr) end
    if nargs == 4 then return ffi.cast("void (*)(int32_t,int32_t,int32_t,int32_t)", ptr) end
    error("mom run supports up to four i32 arguments")
end

local function call(fn, args)
    if #args == 0 then return fn() end
    if #args == 1 then return fn(args[1]) end
    if #args == 2 then return fn(args[1], args[2]) end
    if #args == 3 then return fn(args[1], args[2], args[3]) end
    if #args == 4 then return fn(args[1], args[2], args[3], args[4]) end
    error("mom run supports up to four i32 arguments")
end

function M.run(argv)
    local ok, result = xpcall(function()
        argv = argv or {}
        local opts = parse(argv)
        if opts.help then usage(io.stdout); return 0 end
        if opts.mode == "status" then
            local status = moon.host_mom.status()
            io.stdout:write("mom pipeline: ", tostring(status.pipeline), "\n")
            return status.ready and 0 or 1
        end
        if not opts.input then usage(io.stderr); return 2 end
        if opts.mode == "object" and not opts.output then error("--emit-object requires -o OUT.o") end
        local source = read_all(opts.input)
        if opts.mode == "object" then
            moon.host_mom.emit_object(source, opts.output, opts.module_name or opts.input:gsub("[/\\]", "_"):gsub("%.mlua$", ""))
            io.stdout:write(opts.output, "\n")
            return 0
        end
        local compiled = moon.host_mom.native_loadstring(source, opts.input)
        local ptr = compiled:get(opts.call)
        if opts.ret == "void" then
            call(cast_void(ptr, #opts.args_i32), opts.args_i32)
        elseif opts.ret == "i32" then
            local r = call(cast_i32(ptr, #opts.args_i32), opts.args_i32)
            io.stdout:write(tostring(tonumber(r)), "\n")
        else
            error("unsupported --ret " .. tostring(opts.ret))
        end
        compiled:free()
        return 0
    end, debug.traceback)
    if ok then return result or 0 end
    io.stderr:write(tostring(result), "\n")
    return 1
end

return M
