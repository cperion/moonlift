#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Collect = require("lua_compile.lua_src_window_collect")
local Decode = require("lua_compile.lua_src_from_puc_decode")
local Validate = require("lua_compile.lua_src_validate")
local Slots = require("lua_compile.lua_src_slot_alias")
local Schema = require("lua_compile.schema")

local w = Collect.collect({ { op="LOADI", pc=1, a=1, b=42 }, { op="ADDI", pc=2, a=2, b=1, c=3 }, { op="NOPE", pc=3 } })
assert(#w.ops == 3)
assert(w.ops[1].kind == "LOADI")
assert(w.ops[2].kind == "ADDI")
assert(w.ops[3].kind == "UnsupportedOpcode")
local ok, errs = Validate.validate(w)
assert(ok, table.concat(errs, "\n"))
local inv = Slots.inventory(w)
assert(#inv == 2 and inv[1].id == 1 and inv[2].id == 2)
local function real_op_names()
  local T = Schema.get()
  local names = {}
  for cls in pairs(T.LuaSrc.Op.members) do
    local kind = cls.kind
    if kind and kind ~= "UnsupportedOpcode" then names[#names + 1] = kind end
  end
  table.sort(names)
  return names
end

local function sample_event(name)
  return { op=name, name=name, pc=1, a=1, b=2, c=3, k=false, bx=1, sbx=1, ax=1, binop="ADD" }
end

local names = real_op_names()
assert(#names == 85, "ASDL real LuaSrc.Op coverage count must be 85, got " .. tostring(#names))
local decode_count = 0
for _, name in ipairs(names) do
  assert(Decode.DECODER[name], "missing explicit decoder for " .. name)
  local op = Decode.decode(sample_event(name))
  assert(op.kind == name, "decoder for " .. name .. " produced " .. tostring(op.kind))
  decode_count = decode_count + 1
end
assert(decode_count == 85)

local addi_neg = Decode.decode({ op="ADDI", pc=1, a=1, b=1, c=126 })
assert(addi_neg.rhs.value == -1, "ADDI must decode signed sC, not raw C")
local addi_dumped = Decode.decode({ op="ADDI", pc=1, a=1, b=1, c=126, sc=-1 })
assert(addi_dumped.rhs.value == -1, "ADDI must prefer dumped signed sc")
local shli = Decode.decode({ op="SHLI", pc=1, a=1, b=2, c=124 })
assert(shli.lhs.value == -3 and shli.rhs.id == 2, "SHLI must decode sC << R[B]")
local eqi = Decode.decode({ op="EQI", pc=1, a=1, b=126, k=true, c=1 })
assert(eqi.rhs.value == -1, "EQI must decode signed sB")
assert(eqi.polarity == true and eqi.rhs_is_float == true, "EQI must preserve k polarity and C/isfloat origin separately")
local gei_dumped = Decode.decode({ op="GEI", pc=1, a=1, sb=-9, k=false, isfloat=true })
assert(gei_dumped.rhs.value == -9 and gei_dumped.polarity == false and gei_dumped.rhs_is_float == true, "immediate comparisons must preserve dumped signed sB and explicit isfloat")
local jmp = Decode.decode({ op="JMP", pc=1, sj=-4, bx=999 })
assert(jmp.offset.value == -4, "JMP must decode signed sJ when present")
local settable_r = Decode.decode({ op="SETTABLE", pc=1, a=1, b=2, c=3, k=0 })
assert(settable_r.value.kind == "R" and settable_r.value.slot.id == 3, "numeric k=0 must not be treated as RK constant")
local settable_k = Decode.decode({ op="SETTABLE", pc=1, a=1, b=2, c=3, k=1 })
assert(settable_k.value.kind == "K" and settable_k.value.k.id == 3, "numeric k=1 must be treated as RK constant")
local nt = Decode.decode({ op="NEWTABLE", pc=1, a=1, b=63, c=255, vb=2, vc=9 })
assert(nt.array_hint.value == 2 and nt.hash_hint.value == 9, "ivABC opcodes must prefer vB/vC when dumped")
assert(nt.uses_extraarg == false and nt.extraarg.value == 0, "NEWTABLE without k must not invent EXTRAARG extension")
local nt_from_window = Collect.collect({ { op="NEWTABLE", pc=1, a=1, vb=2, vc=9, k=1 }, { op="EXTRAARG", pc=2, ax=55 } })
assert(nt_from_window.ops[1].uses_extraarg == true and nt_from_window.ops[1].extraarg.value == 55, "NEWTABLE must preserve following EXTRAARG Ax when k is set")
local loadkx_from_window = Collect.collect({ { op="LOADKX", pc=1, a=4 }, { op="EXTRAARG", pc=2, ax=99 } })
assert(loadkx_from_window.ops[1].has_extraarg == true and loadkx_from_window.ops[1].extraarg.value == 99, "LOADKX must preserve following EXTRAARG Ax structurally")
local loadkx_ok, loadkx_errs = Validate.validate(loadkx_from_window)
assert(loadkx_ok, table.concat(loadkx_errs, "\n"))
local cmp_pair = Collect.collect({ { op="EQI", pc=1, a=1, sb=0, k=true, c=0 }, { op="JMP", pc=2, sj=1 }, { op="RETURN0", pc=3 }, { op="RETURN0", pc=4 } })
local cmp_ok, cmp_errs = Validate.validate(cmp_pair)
assert(cmp_ok, table.concat(cmp_errs, "\n"))

local mmbini = Decode.decode({ op="MMBINI", pc=8, a=2, b=130, c=7, k=1 })
assert(mmbini.lhs.id == 2 and mmbini.rhs.value == 3 and mmbini.op.kind == "Sub" and mmbini.operands_flipped == true, "MMBINI must preserve signed B, C metamethod event, and k operand-flip flag")
local mmbink = Decode.decode({ op="MMBINK", pc=8, a=2, b=5, c=8, k=1 })
assert(mmbink.rhs.id == 5 and mmbink.op.kind == "Mul" and mmbink.operands_flipped == true, "MMBINK must preserve B constant ref, C metamethod event, and k operand-flip flag")

local tail = Decode.decode({ op="TAILCALL", pc=9, a=4, b=0, c=7, k=1 })
assert(tail.base.id == 4 and tail.nargs.value == 0 and tail.hidden_vararg_count.value == 7 and tail.close_upvalues == true, "TAILCALL must preserve A/B/C/k and name C as hidden-vararg correction")
local tail_no_close = Decode.decode({ op="TAILCALL", pc=9, a=4, b=3, c=0, k=0 })
assert(tail_no_close.hidden_vararg_count.value == 0 and tail_no_close.close_upvalues == false, "TAILCALL numeric k=0 must not close upvalues")

local vararg = Decode.decode({ op="VARARG", pc=9, a=1, b=6, c=0, k=1 })
assert(vararg.a.id == 1 and vararg.vararg_table.id == 6 and vararg.wanted.value == 0 and vararg.uses_vararg_table == true, "VARARG must preserve A/B/C/k including open C==0 and table mode")
local vararg_fixed = Decode.decode({ op="VARARG", pc=9, a=1, b=0, c=3, k=0 })
assert(vararg_fixed.wanted.value == 3 and vararg_fixed.uses_vararg_table == false, "VARARG fixed wanted count and numeric k=0 must be preserved")

local ret = Decode.decode({ op="RETURN", pc=10, a=4, b=0, c=7, k=1 })
assert(ret.base.id == 4 and ret.nresults.value == 0, "RETURN must preserve A/B operands")
assert(ret.c.value == 7 and ret.close_upvalues == true, "RETURN must preserve C and k/close-upvalues")
local ret_no_close = Decode.decode({ op="RETURN", pc=10, a=4, b=2, c=0, k=0 })
assert(ret_no_close.c.value == 0 and ret_no_close.close_upvalues == false, "RETURN numeric k=0 must not close upvalues")

local setlist = Decode.decode({ op="SETLIST", pc=11, a=2, vb=5, vc=9, k=1, extraarg=12 })
assert(setlist.table.id == 2 and setlist.narray.value == 5 and setlist.start.value == 9, "SETLIST must preserve table/count/start")
assert(setlist.uses_extraarg == true and setlist.extraarg.value == 12, "SETLIST must preserve explicit EXTRAARG extension")
local setlist_from_window = Collect.collect({ { op="SETLIST", pc=11, a=2, vb=5, vc=9, k=1 }, { op="EXTRAARG", pc=12, ax=34 } })
assert(setlist_from_window.ops[1].uses_extraarg == true and setlist_from_window.ops[1].extraarg.value == 34, "SETLIST must preserve following EXTRAARG Ax when present in event window")
assert(setlist_from_window.ops[2].kind == "EXTRAARG" and setlist_from_window.ops[2].ax.value == 34, "EXTRAARG op remains explicitly decoded")
local setlist_no_extra = Decode.decode({ op="SETLIST", pc=11, a=2, b=5, c=9, k=0 })
assert(setlist_no_extra.uses_extraarg == false and setlist_no_extra.extraarg.value == 0, "SETLIST numeric k=0 must not use EXTRAARG")

local errnnil = Decode.decode({ op="ERRNNIL", pc=12, a=3, bx=77 })
assert(errnnil.a.id == 3 and errnnil.name_index.value == 77, "ERRNNIL must preserve Bx/name index")
local errnnil_named = Decode.decode({ op="ERRNNIL", pc=12, a=3, name_index=88 })
assert(errnnil_named.name_index.value == 88, "ERRNNIL decoder must accept named name_index event field")

print("ok - SpongeJIT LuaCompile LuaSrc (decode coverage " .. decode_count .. "/85)")
