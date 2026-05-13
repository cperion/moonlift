package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Run = require("moonlift.mlua_run")

local fn, runtime = Run.loadfile("benchmarks/bench_kernels_isolate.mlua")
local kernels = fn()

-- Get the raw program before compilation
local k = kernels.fib
local T = runtime.T
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToBack = require("moonlift.tree_to_back").Define(T)
local Validate = require("moonlift.back_validate").Define(T)
local Tr = T.MoonTree

-- Manually compile to see the BackProgram
local deps = { type_decls = {}, region_frags = {}, expr_frags = {} }
local mod = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(k.func) })
local checked = Typecheck.check_module(mod)
local resolved = Layout.module(checked.module)
local program = TreeToBack.module(resolved)

local report = Validate.validate(program)
print("validation issues:", #report.issues)
for i = 1, #report.issues do print("  ", tostring(report.issues[i])) end

-- Collect and print the cmds for the function body
local in_func = false
local body = {}
for _, cmd in ipairs(program.cmds) do
    if cmd.kind == "CmdBeginFunc" and cmd.func and tostring(cmd.func.text):match("fib") then
        in_func = true
    elseif cmd.kind == "CmdFinishFunc" then
        in_func = false
        if tostring(cmd.func.text):match("fib") then break end
    elseif in_func then
        body[#body + 1] = cmd
    end
end

print("\nfib function body commands (" .. #body .. " total):")
for i, cmd in ipairs(body) do
    local s = cmd.kind
    if cmd.dst then s = s .. " dst=" .. tostring(cmd.dst.text or cmd.dst) end
    if cmd.src then s = s .. " src=" .. tostring(cmd.src.text or cmd.src) end
    if cmd.lhs then s = s .. " lhs=" .. tostring(cmd.lhs.text or cmd.lhs) end
    if cmd.rhs then s = s .. " rhs=" .. tostring(cmd.rhs.text or cmd.rhs) end
    if cmd.block then s = s .. " block=" .. tostring(cmd.block.text or cmd.block) end
    if cmd.args then
        local args = {}
        for j, a in ipairs(cmd.args) do args[j] = tostring(a.text or a) end
        s = s .. " args=[" .. table.concat(args, ",") .. "]"
    end
    if cmd.values then
        local vals = {}
        for j, v in ipairs(cmd.values) do vals[j] = tostring(v.text or v) end
        s = s .. " values=[" .. table.concat(vals, ",") .. "]"
    end
    print(string.format("%3d: %s", i, s))
end

-- Now compile with dynasm and run
local DynASM = require("back.dasm").Define(T)
local jit = DynASM.jit()
local art = jit:compile(program)
local f = ffi.cast("int32_t (*)(int32_t)", art:getpointer(T.MoonBack.BackFuncId("fib_i32")))
for n = 0, 10 do
    print(string.format("fib(%d) = %d", n, f(n)))
end
art:free()
