#!/usr/bin/env luajit
-- Smoke test for the StencilCtx copy/patch materializer.

local root = "experiments/lua_interpreter_vm/spongejit"
package.path = root .. "/runtime/?.lua;" .. root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local ffi = require("ffi")
local M = require("materialize")

local lib = M.load_library(root .. "/build/stencil_library.json")

local function assert_eq(a, b, msg)
    if a ~= b then error((msg or "assert_eq failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

local ctx = ffi.new("struct StencilCtxMini")
ctx.frame = nil
ctx.current = 0xffffffffffffffffULL
ctx.acc = 0

local nil_inst = M.materialize(lib, { "const_nil" })
nil_inst.fn_ctx(ctx)
assert_eq(ctx.current, 0ULL, "const_nil")
M.free(nil_inst)

ctx.current = M.tagged_i64(5)
ctx.acc = 0
local math_inst = M.materialize(lib, { "unbox_i64", "add_i64", "box_i64" })
math_inst.fn_ctx(ctx)
assert_eq(ctx.current, M.tagged_i64(10), "unbox+add+box")
M.free(math_inst)

print("ok - SponJIT materializer executes copied StencilCtx code")
