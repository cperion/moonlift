package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;"
  .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local D = require("back.dasm")

local T = pvm.context()
A2.Define(T)
local api = D.Define(T)

local B = T.MoonBack
local C = T.MoonCore

local function sid(t) return B.BackSigId(t) end
local function fid(t) return B.BackFuncId(t) end
local function bid(t) return B.BackBlockId(t) end
local function vid(t) return B.BackValId(t) end

local i32 = B.BackI32
local sem = B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose)
local u32 = B.BackU32

local templates = {}

function templates.addern(n)
  return B.BackProgram({
    B.CmdCreateSig(sid("s"), { i32 }, { i32 }),
    B.CmdDeclareFunc(C.VisibilityExport, fid("f"), sid("s")),
    B.CmdBeginFunc(fid("f")),
    B.CmdCreateBlock(bid("e")),
    B.CmdSwitchToBlock(bid("e")),
    B.CmdBindEntryParams(bid("e"), { vid("x") }),
    B.CmdConst(vid("c"), i32, B.BackLitInt(tostring(n))),
    B.CmdIntBinary(vid("r"), B.BackIntAdd, i32, sem, vid("x"), vid("c")),
    B.CmdReturnValue(vid("r")),
    B.CmdSealBlock(bid("e")),
    B.CmdFinishFunc(fid("f")),
    B.CmdFinalizeModule,
  })
end

function templates.mulser(n)
  return B.BackProgram({
    B.CmdCreateSig(sid("s"), { i32 }, { i32 }),
    B.CmdDeclareFunc(C.VisibilityExport, fid("f"), sid("s")),
    B.CmdBeginFunc(fid("f")),
    B.CmdCreateBlock(bid("e")),
    B.CmdSwitchToBlock(bid("e")),
    B.CmdBindEntryParams(bid("e"), { vid("x") }),
    B.CmdConst(vid("c"), i32, B.BackLitInt(tostring(n))),
    B.CmdIntBinary(vid("r"), B.BackIntMul, i32, sem, vid("x"), vid("c")),
    B.CmdReturnValue(vid("r")),
    B.CmdSealBlock(bid("e")),
    B.CmdFinishFunc(fid("f")),
    B.CmdFinalizeModule,
  })
end

function templates.poprot()
  return B.BackProgram({
    B.CmdCreateSig(sid("s"), { u32 }, { u32 }),
    B.CmdDeclareFunc(C.VisibilityExport, fid("f"), sid("s")),
    B.CmdBeginFunc(fid("f")),
    B.CmdCreateBlock(bid("e")),
    B.CmdSwitchToBlock(bid("e")),
    B.CmdBindEntryParams(bid("e"), { vid("x") }),
    B.CmdIntrinsic(vid("pc"), B.BackIntrinsicPopcount, B.BackShapeScalar(u32), { vid("x") }),
    B.CmdConst(vid("one"), u32, B.BackLitInt("1")),
    B.CmdRotate(vid("r"), B.BackRotateLeft, u32, vid("pc"), vid("one")),
    B.CmdReturnValue(vid("r")),
    B.CmdSealBlock(bid("e")),
    B.CmdFinishFunc(fid("f")),
    B.CmdFinalizeModule,
  })
end

math.randomseed(42)
for iter = 1, 100 do
  local jit = api.jit()
  for _ = 1, 10 do
    local names = {"addern", "mulser", "poprot"}
    local tname = names[math.random(3)]
    local n = math.random(1, 99)
    local prog = templates[tname](n)
    local art = jit:compile(prog)
    local fn = ffi.cast("int32_t(*)(int32_t)", art:getpointer("f"))
    local inp = math.random(0, 1000)
    local expected
    if tname == "addern" then
      expected = inp + n
    elseif tname == "mulser" then
      expected = inp * n
    elseif tname == "poprot" then
      local pc = 0
      local v = bit.band(inp, 0xFFFFFFFF)
      while v ~= 0 do pc = pc + 1; v = bit.band(v, v - 1) end
      expected = bit.lshift(pc, 1) + bit.rshift(pc, 31)
      expected = bit.band(expected, 0xFFFFFFFF)
    end
    local got = tonumber(fn(inp))
    if got ~= expected then
      error(string.format("FAIL iter=%d %s(%d)(%d) = %d expected %d", iter, tname, n, inp, got, expected))
    end
    art:free()
  end
end

print("dasm multi_compile stress: 100 iterations x 10 programs = ok")
