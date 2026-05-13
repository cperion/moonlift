package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Mx = require("back.dasm.model")
local BuildCfg = require("back.dasm.phases.build_cfg")
local PhiLower = require("back.dasm.phases.phi_lower")
local SelectMir = require("back.dasm.phases.select_mir")
local P_collect = require("back.dasm.phases.collect_module")

-- Get the fib program
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Run = require("moonlift.mlua_run")
local fn, runtime = Run.loadfile("benchmarks/bench_kernels_isolate.mlua")
local kernels = fn()

local T = runtime.T
Mx.set_context(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToBack = require("moonlift.tree_to_back").Define(T)
local Tr = T.MoonTree

local k = kernels.fib
local mod = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(k.func) })
local checked = Typecheck.check_module(mod)
local resolved = Layout.module(checked.module)
local program = TreeToBack.module(resolved)

local collected = P_collect.run(program)
local cm = Mx.phase_module_maps(collected)
local fk = cm.fkeys[1]
local body = cm.funcs[fk].body
local sig = cm.funcs[fk].sig

print("=== BEFORE phi_lower (flat body) ===")
for i, cmd in ipairs(body) do
    local s = cmd.kind
    if cmd.dst then s = s .. " dst=" .. Mx.idkey(cmd.dst) end
    if cmd.src then s = s .. " src=" .. Mx.idkey(cmd.src) end
    if cmd.lhs then s = s .. " lhs=" .. Mx.idkey(cmd.lhs) end
    if cmd.rhs then s = s .. " rhs=" .. Mx.idkey(cmd.rhs) end
    if cmd.args then
        local a = {}
        for _, v in ipairs(cmd.args) do a[#a + 1] = Mx.idkey(v) end
        s = s .. " args=[" .. table.concat(a, ",") .. "]"
    end
    if cmd.block then s = s .. " block=" .. Mx.idkey(cmd.block) end
    print(string.format("%3d: %s", i, s))
end

local cfg = BuildCfg.run(Mx.make_phase_func(body, Mx.back_func_id(fk)), Mx.back_sig_id(sig))
local lowered_cfg = PhiLower.run(cfg)
local lowered = Mx.phase_func_cmds(SelectMir.run(lowered_cfg))

print("\n=== AFTER phi_lower (flattened) ===")
for i, cmd in ipairs(lowered) do
    local s = cmd.kind
    if cmd.dst then s = s .. " dst=" .. Mx.idkey(cmd.dst) end
    if cmd.src then s = s .. " src=" .. Mx.idkey(cmd.src) end
    if cmd.lhs then s = s .. " lhs=" .. Mx.idkey(cmd.lhs) end
    if cmd.rhs then s = s .. " rhs=" .. Mx.idkey(cmd.rhs) end
    if cmd.args then
        local a = {}
        for _, v in ipairs(cmd.args) do a[#a + 1] = Mx.idkey(v) end
        s = s .. " args=[" .. table.concat(a, ",") .. "]"
    end
    if cmd.block then s = s .. " block=" .. Mx.idkey(cmd.block) end
    print(string.format("%3d: %s", i, s))
end
