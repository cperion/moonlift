-- lua_src_from_puc_decode.lua -- PUC instruction table -> LuaSrc.Op.

local B = require("lua_compile.builders")
local Src = B.LuaSrc

local M = {}

local function pc(ev) return B.pc(ev.pc or ev.source or 0) end
local function slot(x) return B.slot(x or 0) end
local function imm(x) return B.imm(x or 0) end
local function kref(x) return B.k(x or 0) end
local function count(x) return B.count(x or 0) end
local function signed_b(ev) return ev.sb ~= nil and ev.sb or ((ev.b ~= nil) and (ev.b - 127) or 0) end
local function signed_c(ev) return ev.sc ~= nil and ev.sc or ((ev.c ~= nil) and (ev.c - 127) or 0) end
local function signed_j(ev) return ev.sj ~= nil and ev.sj or ev.sbx or ev.offset or 0 end
local function offset(ev) return B.offset(ev.bx or ev.sbx or ev.offset or 0) end
local function jump_offset(ev) return B.offset(signed_j(ev)) end
local function bool_c(x) return x ~= nil and tonumber(x) ~= 0 and x ~= false end
local function kflag(ev) return ev and ev.k ~= nil and tonumber(ev.k) ~= 0 and ev.k ~= false end
local function has_field(ev, name) return ev and ev[name] ~= nil end
local function explicit_extraarg(ev)
  if not ev then return nil end
  local v = ev.extraarg
  if v == nil then v = ev.extra_arg end
  if v == nil then v = ev.extraarg_ax end
  if v == nil then v = ev.extra_ax end
  if v == nil then v = ev.extension end
  return v
end
local function following_ax(ev)
  local v = explicit_extraarg(ev)
  if v == nil and ev then v = ev.ax end
  if v == nil and ev then v = ev.extraax end
  return v
end
local function has_following_ax(ev)
  return following_ax(ev) ~= nil
end
local function immediate_is_float(ev)
  if not ev then return false end
  if ev.isfloat ~= nil then return bool_c(ev.isfloat) end
  if ev.rhs_is_float ~= nil then return bool_c(ev.rhs_is_float) end
  if ev.float ~= nil then return bool_c(ev.float) end
  if ev.c ~= nil then return bool_c(ev.c) end
  return false
end
local function bx_value(ev)
  if not ev then return 0 end
  if ev.bx ~= nil then return ev.bx end
  if ev.name_index ~= nil then return ev.name_index end
  if ev.nameidx ~= nil then return ev.nameidx end
  return 0
end
local function rk_from_kflag(ev, field)
  local v = ev[field]
  if kflag(ev) and field == "c" then return Src.K(kref(v)) end
  return Src.R(slot(v))
end

local BIN = { ADD=Src.Add, SUB=Src.Sub, MUL=Src.Mul, MOD=Src.Mod, POW=Src.Pow, DIV=Src.Div, IDIV=Src.IDiv, BAND=Src.BAnd, BOR=Src.BOr, BXOR=Src.BXor, SHL=Src.Shl, SHR=Src.Shr }
local BIN_BY_TM = { [6]=Src.Add, [7]=Src.Sub, [8]=Src.Mul, [9]=Src.Mod, [10]=Src.Pow, [11]=Src.Div, [12]=Src.IDiv, [13]=Src.BAnd, [14]=Src.BOr, [15]=Src.BXor, [16]=Src.Shl, [17]=Src.Shr }
local function binop(e)
  local v = e.binop or e.arith or e.mm or e.event or e.op_kind
  if type(v) == "string" then return BIN[v:upper()] or BIN[v] or Src.Add end
  return BIN_BY_TM[tonumber(v or e.c or e.b)] or Src.Add
end

local DECODER = {}
DECODER.MOVE = function(e) return Src.MOVE(pc(e), slot(e.a), slot(e.b)) end
DECODER.LOADI = function(e) return Src.LOADI(pc(e), slot(e.a), imm(e.sbx or e.b or e.value or 0)) end
DECODER.LOADF = function(e) return Src.LOADF(pc(e), slot(e.a), imm(e.sbx or e.b or e.value or 0)) end
DECODER.LOADK = function(e) return Src.LOADK(pc(e), slot(e.a), kref(e.bx or e.b)) end
DECODER.LOADKX = function(e) return Src.LOADKX(pc(e), slot(e.a), has_following_ax(e), B.ax(following_ax(e) or 0)) end
DECODER.LOADFALSE = function(e) return Src.LOADFALSE(pc(e), slot(e.a)) end
DECODER.LFALSESKIP = function(e) return Src.LFALSESKIP(pc(e), slot(e.a)) end
DECODER.LOADTRUE = function(e) return Src.LOADTRUE(pc(e), slot(e.a)) end
DECODER.LOADNIL = function(e) return Src.LOADNIL(pc(e), slot(e.a), count(e.b or e.count or 1)) end
DECODER.ADDI = function(e) return Src.ADDI(pc(e), slot(e.a), slot(e.b), imm(signed_c(e))) end
for _, op in ipairs({"ADDK","SUBK","MULK","MODK","POWK","DIVK","IDIVK","BANDK","BORK","BXORK"}) do
  DECODER[op] = function(e) return Src[op](pc(e), slot(e.a), slot(e.b), kref(e.c)) end
end
DECODER.SHLI = function(e) return Src.SHLI(pc(e), slot(e.a), imm(signed_c(e)), slot(e.b)) end
DECODER.SHRI = function(e) return Src.SHRI(pc(e), slot(e.a), slot(e.b), imm(signed_c(e))) end
for _, op in ipairs({"ADD","SUB","MUL","MOD","POW","DIV","IDIV","BAND","BOR","BXOR","SHL","SHR"}) do
  DECODER[op] = function(e) return Src[op](pc(e), slot(e.a), slot(e.b), slot(e.c)) end
end
DECODER.MMBIN = function(e) return Src.MMBIN(pc(e), slot(e.a or e.lhs), slot(e.b or e.rhs), binop(e)) end
DECODER.MMBINI = function(e) return Src.MMBINI(pc(e), slot(e.a or e.lhs), imm(signed_b(e)), binop(e), kflag(e)) end
DECODER.MMBINK = function(e) return Src.MMBINK(pc(e), slot(e.a or e.lhs), kref(e.b or e.rhs), binop(e), kflag(e)) end
DECODER.UNM = function(e) return Src.UNM(pc(e), slot(e.a), slot(e.b)) end
DECODER.BNOT = function(e) return Src.BNOT(pc(e), slot(e.a), slot(e.b)) end
DECODER.NOT = function(e) return Src.NOT(pc(e), slot(e.a), slot(e.b)) end
DECODER.LEN = function(e) return Src.LEN(pc(e), slot(e.a), slot(e.b)) end
DECODER.CONCAT = function(e) return Src.CONCAT(pc(e), slot(e.a), slot(e.b), slot(e.c)) end
DECODER.CLOSE = function(e) return Src.CLOSE(pc(e), slot(e.a)) end
DECODER.TBC = function(e) return Src.TBC(pc(e), slot(e.a)) end
DECODER.JMP = function(e) return Src.JMP(pc(e), jump_offset(e)) end
for _, op in ipairs({"EQ","LT","LE"}) do DECODER[op] = function(e) return Src[op](pc(e), slot(e.a), slot(e.b), bool_c(e.k or e.c)) end end
DECODER.EQK = function(e) return Src.EQK(pc(e), slot(e.a), kref(e.b), bool_c(e.k or e.c)) end
for _, op in ipairs({"EQI","LTI","LEI","GTI","GEI"}) do DECODER[op] = function(e) return Src[op](pc(e), slot(e.a), imm(signed_b(e)), kflag(e), immediate_is_float(e)) end end
DECODER.TEST = function(e) return Src.TEST(pc(e), slot(e.a), bool_c(e.k or e.c)) end
DECODER.TESTSET = function(e) return Src.TESTSET(pc(e), slot(e.a), slot(e.b), bool_c(e.k or e.c)) end
DECODER.CALL = function(e) return Src.CALL(pc(e), slot(e.a), count(e.b), count(e.c)) end
DECODER.TAILCALL = function(e) return Src.TAILCALL(pc(e), slot(e.a), count(e.b), count(e.c), kflag(e)) end
DECODER.RETURN = function(e) return Src.RETURN(pc(e), slot(e.a), count(e.b), count(e.c), kflag(e)) end
DECODER.RETURN0 = function(e) return Src.RETURN0(pc(e)) end
DECODER.RETURN1 = function(e) return Src.RETURN1(pc(e), slot(e.a)) end
for _, op in ipairs({"FORLOOP","FORPREP","TFORPREP","TFORLOOP"}) do DECODER[op] = function(e) return Src[op](pc(e), slot(e.a), offset(e)) end end
DECODER.TFORCALL = function(e) return Src.TFORCALL(pc(e), slot(e.a), count(e.c or e.nresults)) end
DECODER.GETUPVAL = function(e) return Src.GETUPVAL(pc(e), slot(e.a), B.up(e.b)) end
DECODER.SETUPVAL = function(e) return Src.SETUPVAL(pc(e), slot(e.a), B.up(e.b)) end
DECODER.GETTABUP = function(e) return Src.GETTABUP(pc(e), slot(e.a), B.up(e.b), kref(e.c)) end
DECODER.GETTABLE = function(e) return Src.GETTABLE(pc(e), slot(e.a), slot(e.b), slot(e.c)) end
DECODER.GETI = function(e) return Src.GETI(pc(e), slot(e.a), slot(e.b), imm(e.c)) end
DECODER.GETFIELD = function(e) return Src.GETFIELD(pc(e), slot(e.a), slot(e.b), kref(e.c)) end
DECODER.SETTABUP = function(e) return Src.SETTABUP(pc(e), B.up(e.a), kref(e.b), rk_from_kflag(e, "c")) end
DECODER.SETTABLE = function(e) return Src.SETTABLE(pc(e), slot(e.a), slot(e.b), rk_from_kflag(e, "c")) end
DECODER.SETI = function(e) return Src.SETI(pc(e), slot(e.a), imm(e.b), rk_from_kflag(e, "c")) end
DECODER.SETFIELD = function(e) return Src.SETFIELD(pc(e), slot(e.a), kref(e.b), rk_from_kflag(e, "c")) end
DECODER.SELF = function(e) return Src.SELF(pc(e), slot(e.a), slot(e.b), kref(e.c)) end
DECODER.NEWTABLE = function(e) return Src.NEWTABLE(pc(e), slot(e.a), count(e.vb or e.b), count(e.vc or e.c), kflag(e), B.ax(following_ax(e) or 0)) end
DECODER.SETLIST = function(e) return Src.SETLIST(pc(e), slot(e.a), count(e.vb or e.b), count(e.vc or e.c), kflag(e), B.ax(explicit_extraarg(e) or 0)) end
DECODER.CLOSURE = function(e) return Src.CLOSURE(pc(e), slot(e.a), kref(e.bx or e.b)) end
DECODER.VARARG = function(e) return Src.VARARG(pc(e), slot(e.a), slot(e.b), count(has_field(e, "c") and e.c or e.nresults), kflag(e)) end
DECODER.GETVARG = function(e) return Src.GETVARG(pc(e), slot(e.a), slot(e.b), slot(e.c)) end
DECODER.ERRNNIL = function(e) return Src.ERRNNIL(pc(e), slot(e.a), B.ax(bx_value(e))) end
DECODER.VARARGPREP = function(e) return Src.VARARGPREP(pc(e), count(e.a or e.b or 0)) end
DECODER.EXTRAARG = function(e) return Src.EXTRAARG(pc(e), B.ax(e.ax or e.bx or 0)) end

function M.decode(ev)
  local op = ev and (ev.op or ev.name or ev.opcode_name)
  local f = DECODER[op]
  if f then return f(ev) end
  return Src.UnsupportedOpcode(pc(ev or {}), tostring(op or "<unknown>"))
end

M.DECODER = DECODER
return M
