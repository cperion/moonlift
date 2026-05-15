-- CLI policy for the standalone `mom` binary.
-- Uses MOM to compile Moonlift source.  For .mlua files, delegates to LuaJIT
-- (.mlua parsing + MOM compilation of each Moonlift island).

local ffi = require("ffi")
local mom = require("moonlift.host_mom")
local Host = require("moonlift.mlua_run")

local M = {}

local function usage(out)
    out:write([[usage:
  mom run [--call NAME] [--ret i32|void] [--arg-i32 N ...] FILE.mlua
  mom --emit-object -o OUT.o [--module-name NAME] FILE.mlua

The run path compiles the source through MOM and calls NAME (default: main).
The object path emits a relocatable object through moonlift_object_compile_binary.
]])
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then error(err or ("unable to open " .. tostring(path))) end
    local s = f:read("*a")
    f:close()
    return s
end

local function parse(argv)
    local opts = { mode = "run", call = "main", ret = "i32", args_i32 = {} }
    local i = 1
    if argv[i] == "run" then opts.mode = "run"; i = i + 1 end
    while i <= #argv do
        local a = argv[i]
        if a == "--help" or a == "-h" then
            opts.help = true
            return opts
        elseif a == "--emit-object" then
            opts.mode = "object"
        elseif a == "-o" then
            i = i + 1; opts.output = argv[i]
        elseif a == "--module-name" then
            i = i + 1; opts.module_name = argv[i]
        elseif a == "--call" then
            i = i + 1; opts.call = argv[i]
        elseif a == "--ret" then
            i = i + 1; opts.ret = argv[i]
        elseif a == "--arg-i32" then
            i = i + 1; opts.args_i32[#opts.args_i32 + 1] = tonumber(argv[i]) or error("--arg-i32 expects an integer")
        elseif a:sub(1, 1) == "-" then
            error("unknown option " .. a)
        elseif not opts.input then
            opts.input = a
        else
            error("unexpected argument " .. a)
        end
        i = i + 1
    end
    return opts
end

local function cast_i32_function(ptr, nargs)
    if nargs == 0 then return ffi.cast("int32_t (*)()", ptr) end
    if nargs == 1 then return ffi.cast("int32_t (*)(int32_t)", ptr) end
    if nargs == 2 then return ffi.cast("int32_t (*)(int32_t, int32_t)", ptr) end
    if nargs == 3 then return ffi.cast("int32_t (*)(int32_t, int32_t, int32_t)", ptr) end
    if nargs == 4 then return ffi.cast("int32_t (*)(int32_t, int32_t, int32_t, int32_t)", ptr) end
    error("mom run supports up to four i32 arguments")
end

local function cast_void_function(ptr, nargs)
    if nargs == 0 then return ffi.cast("void (*)()", ptr) end
    if nargs == 1 then return ffi.cast("void (*)(int32_t)", ptr) end
    if nargs == 2 then return ffi.cast("void (*)(int32_t, int32_t)", ptr) end
    if nargs == 3 then return ffi.cast("void (*)(int32_t, int32_t, int32_t)", ptr) end
    if nargs == 4 then return ffi.cast("void (*)(int32_t, int32_t, int32_t, int32_t)", ptr) end
    error("mom run supports up to four i32 arguments")
end

local function call_with_args(fn, args)
    if #args == 0 then return fn() end
    if #args == 1 then return fn(args[1]) end
    if #args == 2 then return fn(args[1], args[2]) end
    if #args == 3 then return fn(args[1], args[2], args[3]) end
    if #args == 4 then return fn(args[1], args[2], args[3], args[4]) end
    error("mom run supports up to four i32 arguments")
end

function M.run(argv)
    local ok, err = xpcall(function()
        argv = argv or {}
        local opts = parse(argv)
        if opts.help then usage(io.stdout); return 0 end
        if not opts.input then usage(io.stderr); return 2 end
        if opts.mode == "object" and not opts.output then error("--emit-object requires -o OUT.o") end

        local source = read_all(opts.input)
        if opts.mode == "object" then
            mom.emit_object(source, opts.output, opts.module_name or opts.input:gsub("[/\\]", "_"):gsub("%.mlua$", ""))
            io.stdout:write(opts.output, "\n")
            return 0
        end

        -- Try MOM path first (pure Moonlift .mlua).
        -- If the source contains Lua carrier code, MOM's parser will produce
        -- issues — fall back to LuaJIT + hosted_jit.
        local ok, compiled_or_err = pcall(mom, source)
        if ok then
            compiled = compiled_or_err
            ptr = compiled:get(opts.call)
        else
            -- .mlua with Lua carrier — use LuaJIT to parse, hosted_jit to compile
            local mod = Host.dofile(opts.input)
            compiled = mod:compile()
            ptr = compiled.artifact:getpointer(opts.call)
        end
        local code = 0
        if opts.ret == "void" then
            local fn = cast_void_function(ptr, #opts.args_i32)
            call_with_args(fn, opts.args_i32)
        elseif opts.ret == "i32" then
            local fn = cast_i32_function(ptr, #opts.args_i32)
            local result = tonumber(call_with_args(fn, opts.args_i32))
            io.stdout:write(tostring(result), "\n")
        else
            error("unsupported --ret " .. tostring(opts.ret))
        end
        compiled:free()
        return code
    end, debug.traceback)

    if ok then return err or 0 end
    io.stderr:write(tostring(err), "\n")
    return 1
end

return M
