-- lua_compile/builders.lua -- constructor conveniences only.
--
-- These helpers are syntax sugar over ASDL constructors. They do not perform
-- semantic lowering, optimization, fallback, or backend decisions.

local Schema = require("lua_compile.schema")
local T = Schema.get()

local M = { T = T, LuaSrc = T.LuaSrc, LuaRegion = T.LuaRegion, LuaFact = T.LuaFact, LuaSem = T.LuaSem, LuaNF = T.LuaNF, LuaContract = T.LuaContract, LuaFFI = T.LuaFFI, LuaGC = T.LuaGC, LuaRT = T.LuaRT, LuaExec = T.LuaExec, MoonCFG = T.MoonCFG, Stencil = T.Stencil, LuaCompile = T.LuaCompile }

local Src, Fact, Region = T.LuaSrc, T.LuaFact, T.LuaRegion

function M.pc(n) return Src.Pc(tonumber(n) or 0) end
function M.slot(n) return Src.Slot(tonumber(n) or 0) end
function M.up(n) return Src.UpRef(tonumber(n) or 0) end
function M.k(n) return Src.KRef(tonumber(n) or 0) end
function M.imm(n) return Src.Imm(tonumber(n) or 0) end
function M.count(n) return Src.Count(tonumber(n) or 0) end
function M.offset(n) return Src.Offset(tonumber(n) or 0) end
function M.ax(n) return Src.Ax(tonumber(n) or 0) end
function M.r(slot) return Src.R(M.slot(slot)) end
function M.kr(k) return Src.K(M.k(k)) end

function M.window(ops) return Src.Window(ops or {}) end
function M.region_set(regions) return Region.RegionSet(regions or {}) end
function M.empty_evidence()
  return Fact.Evidence({}, {}, M.region_set({}))
end
function M.unit(window, evidence)
  return T.LuaCompile.Unit(window, evidence or M.empty_evidence())
end

function M.src_slot_subject(slot)
  return Fact.SrcSlot(type(slot) == "table" and slot or M.slot(slot))
end
function M.const_subject(k)
  return Fact.Const(type(k) == "table" and k or M.k(k))
end
function M.fact(subject, predicate, value_key, deps)
  return Fact.Fact(subject, predicate, value_key or "", deps or {})
end
function M.slot_fact(slot, predicate, value_key, deps)
  return M.fact(M.src_slot_subject(slot), predicate, value_key, deps)
end

return M
