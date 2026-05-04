package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local OpenExpand = require("moonlift.open_expand")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")

local T = moon.T
local Tr = T.MoonTree
local O = T.MoonOpen
local OF = OpenFacts.Define(T)
local OV = OpenValidate.Define(T)
local OE = OpenExpand.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local BV = BackValidate.Define(T)

local M = moon.module("RegionDemo")
M:export_func("sum_to", { moon.param("n", moon.i32) }, moon.i32, function(fn)
    local n = fn:param("n")
    fn:return_region(moon.i32, function(r)
        r:entry("loop", {
            moon.entry_param("i", moon.i32, moon.int(0)),
            moon.entry_param("acc", moon.i32, moon.int(0)),
        }, function(loop)
            loop:if_(loop.i:ge(n), function(t)
                t:yield_(loop.acc)
            end)
            loop:jump(loop.block, { i = loop.i + 1, acc = loop.acc + loop.i })
        end)
    end)
end)

local abs_frag = moon.region_frag("abs_route", { moon.param("x", moon.i32) }, {
    out = moon.cont({ moon.param("v", moon.i32) }),
}, function(r)
    r:entry("start", {}, function(start)
        start:if_(r.x:lt(0), function(t)
            t:jump(r.out, { v = -r.x })
        end, function(e)
            e:jump(r.out, { v = r.x })
        end)
    end)
end)

M:export_func("abs_frag", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    local x = fn:param("x")
    fn:return_region(moon.i32, function(r)
        local done = r:block("done", { moon.param("v", moon.i32) }, function(done_block)
            done_block:yield_(done_block:param("v"))
        end)
        r:entry("start", {}, function(start)
            start:emit(abs_frag, { x }, { out = done })
        end)
    end)
end)

local abs_forward_frag = moon.region_frag("abs_forward", { moon.param("x", moon.i32) }, {
    out = moon.cont({ moon.param("v", moon.i32) }),
}, function(r)
    r:entry("start", {}, function(start)
        start:emit(abs_frag, { r.x }, { out = r.out })
    end)
end)

M:export_func("abs_forward_frag", { moon.param("x", moon.i32) }, moon.i32, function(fn)
    local x = fn:param("x")
    fn:return_region(moon.i32, function(r)
        local done = r:block("done", { moon.param("v", moon.i32) }, function(done_block)
            done_block:yield_(done_block.v)
        end)
        r:entry("start", {}, function(start)
            start:emit(abs_forward_frag, { x }, { out = done })
        end)
    end)
end)

M:export_func("dispatch_abs", { moon.param("mode", moon.i32), moon.param("x", moon.i32) }, moon.i32, function(fn)
    local mode = fn:param("mode")
    local x = fn:param("x")
    fn:return_region(moon.i32, function(r)
        local done = r:block("done", { moon.param("v", moon.i32) }, function(done_block)
            done_block:yield_(done_block.v)
        end)
        r:entry("start", {}, function(start)
            start:switch_(mode, {
                {
                    key = 0,
                    body = function(arm)
                        arm:emit(abs_forward_frag, { x }, { out = done })
                    end,
                },
            }, function(default)
                default:yield_(moon.int(-99))
            end)
        end)
    end)
end)

assert(pvm.classof(abs_forward_frag.frag.entry.body[1].cont_fills[1].target) == O.ContTargetSlot)
local module = M:to_asdl()
assert(pvm.classof(module.items[1].func.body[1].value) == Tr.ExprControl)
assert(pvm.classof(module.items[2].func.body[1].value) == Tr.ExprControl)
assert(pvm.classof(module.items[4].func.body[1].value.region.entry.body[1]) == Tr.StmtSwitch)

local expanded = OE.module(module)
local open_report = OV.validate(OF.facts_of_module(expanded))
assert(#open_report.issues == 0, tostring(open_report.issues[1]))
local checked = TC.check_module(expanded)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local program = Lower.module(checked.module)
local report = BV.validate(program)
assert(#report.issues == 0, tostring(report.issues[1]))

print("moonlift host region values ok")
