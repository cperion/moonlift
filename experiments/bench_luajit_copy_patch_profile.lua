-- EXPERIMENTAL PERFORMANCE PROFILE ONLY.
--
-- This is not production backend code and not the final copy-patch artifact
-- implementation. It reuses the completed supported lowering path as a profiling
-- surrogate for the future copy-patch backend while separating selection from
-- realization:
--
--   MoonCode loop fixture
--     -> luajit_lower stencil selection
--     -> selected StencilArtifact
--     -> CRealizer      current development path: compile C now
--     -> BankRealizer   fast JIT path: resolve from prebuilt bank, no C compile
--     -> luajit_emit callable LuaJIT module
--
-- The final embedded backend will extend BankRealizer by copying/patching bank
-- entry bytes into a self-contained Lua source artifact. Selection remains the
-- same; only realization changes.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Measure = require("moonlift.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Stencil = T.MoonStencil
local Value = T.MoonValue

local Lower = require("moonlift.luajit_lower")(T)
local Emit = require("moonlift.luajit_emit")(T)
local StencilC = require("moonlift.stencil_c")(T)
local StencilBank = require("moonlift.stencil_bank")(T)

local origin = Code.CodeOriginGenerated("bench_luajit_copy_patch_profile")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function ptr(ty) return Code.CodeTyDataPtr(ty) end
local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end
local function now() return Measure.now() end

local function build_store_module(kind)
  local name = "profile_" .. kind
  local dst = param(name .. "_dst", ptr(i32))
  local lhs = param(name .. "_lhs", ptr(i32))
  local rhs = param(name .. "_rhs", ptr(i32))
  local n = param(name .. "_n", i32)
  local zero = Code.CodeValueId("v:" .. name .. ":zero")
  local one = Code.CodeValueId("v:" .. name .. ":one")
  local i = Code.CodeValueId("v:" .. name .. ":i")
  local cond = Code.CodeValueId("v:" .. name .. ":cond")
  local next_i = Code.CodeValueId("v:" .. name .. ":next_i")
  local a = Code.CodeValueId("v:" .. name .. ":a")
  local b = Code.CodeValueId("v:" .. name .. ":b")
  local out = Code.CodeValueId("v:" .. name .. ":out")
  local entry_id = Code.CodeBlockId("block:" .. name .. ":entry")
  local header_id = Code.CodeBlockId("block:" .. name .. ":header")
  local body_id = Code.CodeBlockId("block:" .. name .. ":body")
  local exit_id = Code.CodeBlockId("block:" .. name .. ":exit")
  local sig_id = Code.CodeSigId("sig:" .. name)
  local func_id = Code.CodeFuncId("fn:" .. name)
  local entry = Code.CodeBlock(entry_id, "entry", {}, {
    inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
  }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero })), origin)
  local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin) }, {
    inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
  }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)
  local body_insts, params, sig_params = {}, nil, nil
  if kind == "map" then
    params = { dst, lhs, n }
    sig_params = { ptr(i32), ptr(i32), i32 }
    body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(a, place(lhs.value, i), read_i32))
    body_insts[#body_insts + 1] = inst(name .. ":neg", Code.CodeInstUnary(out, Core.UnaryNeg, i32, a))
  elseif kind == "zip_map" then
    params = { dst, lhs, rhs, n }
    sig_params = { ptr(i32), ptr(i32), ptr(i32), i32 }
    body_insts[#body_insts + 1] = inst(name .. ":load_lhs", Code.CodeInstLoad(a, place(lhs.value, i), read_i32))
    body_insts[#body_insts + 1] = inst(name .. ":load_rhs", Code.CodeInstLoad(b, place(rhs.value, i), read_i32))
    body_insts[#body_insts + 1] = inst(name .. ":add", Code.CodeInstBinary(out, Core.BinAdd, i32, sem, a, b))
  else
    error("unknown store fixture " .. tostring(kind), 2)
  end
  body_insts[#body_insts + 1] = inst(name .. ":store", Code.CodeInstStore(place(dst.value, i), out, write_i32))
  body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))
  local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(name .. ":body", Code.CodeTermJump(header_id, { next_i })), origin)
  local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term(name .. ":exit", Code.CodeTermReturn({})), origin)
  local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
  local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, sig_params, {}) }, {}, {}, {}, {}, { func }, origin)
  local facts = {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(lhs.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(dst.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(lhs.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, lhs.value), origin),
  }
  if kind == "zip_map" then
    facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(rhs.value, n.value), origin)
    facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(rhs.value), origin)
    facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, rhs.value), origin)
    facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(lhs.value, rhs.value), origin)
  end
  return module, Code.CodeContractFactSet(module.id, facts), name
end

local function build_reduce_module()
  local name = "profile_reduce"
  local xs = param(name .. "_xs", ptr(i32))
  local n = param(name .. "_n", i32)
  local zero = Code.CodeValueId("v:" .. name .. ":zero")
  local one = Code.CodeValueId("v:" .. name .. ":one")
  local i = Code.CodeValueId("v:" .. name .. ":i")
  local acc = Code.CodeValueId("v:" .. name .. ":acc")
  local cond = Code.CodeValueId("v:" .. name .. ":cond")
  local item = Code.CodeValueId("v:" .. name .. ":item")
  local next_i = Code.CodeValueId("v:" .. name .. ":next_i")
  local next_acc = Code.CodeValueId("v:" .. name .. ":next_acc")
  local out = Code.CodeValueId("v:" .. name .. ":out")
  local entry_id = Code.CodeBlockId("block:" .. name .. ":entry")
  local header_id = Code.CodeBlockId("block:" .. name .. ":header")
  local body_id = Code.CodeBlockId("block:" .. name .. ":body")
  local exit_id = Code.CodeBlockId("block:" .. name .. ":exit")
  local sig_id = Code.CodeSigId("sig:" .. name)
  local func_id = Code.CodeFuncId("fn:" .. name)
  local entry = Code.CodeBlock(entry_id, "entry", {}, {
    inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
  }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero, zero })), origin)
  local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(acc, "acc", i32, origin) }, {
    inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
  }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
  local body = Code.CodeBlock(body_id, "body", {}, {
    inst(name .. ":load", Code.CodeInstLoad(item, place(xs.value, i), read_i32)),
    inst(name .. ":reduce", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
    inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
  }, term(name .. ":body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
  local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ out })), origin)
  local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, { xs, n }, {}, entry_id, { entry, header, body, exit }, origin)
  local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, { ptr(i32), i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
  local facts = {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(xs.value), origin),
  }
  return module, Code.CodeContractFactSet(module.id, facts), name
end

local function artifact_for(vocab, op, reduction, plan, info)
  if vocab == Stencil.StencilMap then return StencilC.map_array_artifact(op, info) end
  if vocab == Stencil.StencilZipMap then return StencilC.zip_map_array_artifact(op, info) end
  if vocab == Stencil.StencilReduce then return StencilC.reduce_array_artifact(reduction, plan, info) end
  error("unsupported selected stencil vocab " .. tostring(vocab), 3)
end

local function select_fixture(kind)
  local module, contracts, name
  if kind == "reduce" then module, contracts, name = build_reduce_module() else module, contracts, name = build_store_module(kind) end
  local artifacts, rejects = {}, {}
  local t0 = now()
  local lj_module = Lower.lower_module(module, {
    contracts = contracts,
    collect_rejects = rejects,
    stencil_store_artifact_for = kind ~= "reduce" and function(func, vocab, op, plan, info)
      local artifact = artifact_for(vocab, op, nil, plan, info)
      artifacts[#artifacts + 1] = artifact
      return artifact
    end or nil,
    stencil_reduce_artifact_for = kind == "reduce" and function(func, vocab, op, reduction, plan, info)
      local artifact = artifact_for(vocab, op, reduction, plan, info)
      artifacts[#artifacts + 1] = artifact
      return artifact
    end or nil,
  })
  local t1 = now()
  assert(#rejects == 0, kind .. " lowering rejected: " .. tostring(rejects[1] and rejects[1].reason))
  assert(#artifacts == 1, kind .. " expected one selected stencil artifact")
  return { kind = kind, name = name, lj_module = lj_module, artifacts = artifacts, lower_time = t1 - t0 }
end

local function realize_with_c(selected)
  local t0 = now()
  local build, build_err, csrc = StencilC.compile_artifacts(selected.artifacts, { stem = "bench_luajit_copy_patch_profile_c_" .. selected.kind })
  local t1 = now()
  assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
  local compiled, err, src = Emit.compile_module(selected.lj_module, {
    chunk_name = "bench_luajit_copy_patch_profile_c_" .. selected.kind,
    stencil_symbols = build.symbols,
  })
  local t2 = now()
  assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
  return { fn = compiled[selected.name], realize = t1 - t0, emit = t2 - t1, total = selected.lower_time + (t2 - t0), mode = "c" }
end

local function build_bank(selected)
  local t0 = now()
  local bank, err, source = StencilBank.build_bank(selected.artifacts, { stem = "bench_luajit_copy_patch_profile_bank_" .. selected.kind })
  local t1 = now()
  assert(bank ~= nil, tostring(err) .. "\n" .. tostring(source))
  return bank, t1 - t0
end

local function build_binary_bank(selected)
  local t0 = now()
  local bank, err, source = StencilBank.build_binary_bank(selected.artifacts, { stem = "bench_luajit_copy_patch_profile_bin_" .. selected.kind })
  local t1 = now()
  assert(bank ~= nil, tostring(err) .. "\n" .. tostring(source))
  return bank, t1 - t0
end

local function realize_with_bank(selected, bank)
  local t0 = now()
  local realized, err = StencilBank.realize_artifacts(selected.artifacts, { bank = bank })
  local t1 = now()
  assert(realized ~= nil, tostring(err))
  local compiled, emit_err, src = Emit.compile_module(selected.lj_module, {
    chunk_name = "bench_luajit_copy_patch_profile_bank_" .. selected.kind,
    stencil_symbols = realized.symbols,
  })
  local t2 = now()
  assert(compiled ~= nil, tostring(emit_err) .. "\n" .. tostring(src))
  return { fn = compiled[selected.name], realize = t1 - t0, emit = t2 - t1, total = selected.lower_time + (t2 - t0), mode = "bank" }
end

local function realize_with_binary_bank(selected, bank)
  local t0 = now()
  local realized, err = StencilBank.realize_binary_artifacts(selected.artifacts, { bank = bank })
  local t1 = now()
  assert(realized ~= nil, tostring(err))
  local compiled, emit_err, src = Emit.compile_module(selected.lj_module, {
    chunk_name = "bench_luajit_copy_patch_profile_bin_" .. selected.kind,
    stencil_symbols = realized.symbols,
  })
  local t2 = now()
  assert(compiled ~= nil, tostring(emit_err) .. "\n" .. tostring(src))
  return { fn = compiled[selected.name], realize = t1 - t0, emit = t2 - t1, total = selected.lower_time + (t2 - t0), mode = "binary" }
end

local function checksum(xs, n)
  local s = 0
  for i = 0, n - 1 do s = s + xs[i] end
  return s
end

local function init_arrays(n)
  local dst = ffi.new("int32_t[?]", n)
  local lhs = ffi.new("int32_t[?]", n)
  local rhs = ffi.new("int32_t[?]", n)
  for i = 0, n - 1 do lhs[i] = i % 1024; rhs[i] = (i * 3) % 2048; dst[i] = 0 end
  return dst, lhs, rhs
end

local n = tonumber(arg[1]) or 300000
local rounds = tonumber(arg[2]) or 12
local samples = tonumber(arg[3]) or 3
local chunk = tonumber(arg[4]) or 4096
local kinds = { "map", "zip_map", "reduce" }
local dst, lhs, rhs = init_arrays(n)

local function lua_case(kind)
  if kind == "map" then return function() for i = 0, n - 1 do dst[i] = -lhs[i] end; return checksum(dst, n) end end
  if kind == "zip_map" then return function() for i = 0, n - 1 do dst[i] = lhs[i] + rhs[i] end; return checksum(dst, n) end end
  if kind == "reduce" then return function() local acc = 0; for i = 0, n - 1 do acc = acc + lhs[i] end; return acc end end
end

local function whole_case(kind, fn)
  if kind == "map" then return function() fn(dst, lhs, n); return checksum(dst, n) end end
  if kind == "zip_map" then return function() fn(dst, lhs, rhs, n); return checksum(dst, n) end end
  if kind == "reduce" then return function() return fn(lhs, n) end end
end

local function chunk_case(kind, fn)
  if kind == "map" then return function() local off = 0; while off < n do local c = n - off; if c > chunk then c = chunk end; fn(dst + off, lhs + off, c); off = off + c end; return checksum(dst, n) end end
  if kind == "zip_map" then return function() local off = 0; while off < n do local c = n - off; if c > chunk then c = chunk end; fn(dst + off, lhs + off, rhs + off, c); off = off + c end; return checksum(dst, n) end end
  if kind == "reduce" then return function() local off, acc = 0, 0; while off < n do local c = n - off; if c > chunk then c = chunk end; acc = acc + fn(lhs + off, c); off = off + c end; return acc end end
end

local function coroutine_chunk_case(kind, fn)
  return function()
    local co = coroutine.create(function(limit, batch) local off = 0; while off < limit do local c = limit - off; if c > batch then c = batch end; coroutine.yield(off, c); off = off + c end end)
    local acc = 0
    while true do
      local ok, off, c = coroutine.resume(co, n, chunk)
      if not ok then error(off) end
      if off == nil then break end
      if kind == "map" then fn(dst + off, lhs + off, c)
      elseif kind == "zip_map" then fn(dst + off, lhs + off, rhs + off, c)
      elseif kind == "reduce" then acc = acc + fn(lhs + off, c) end
    end
    if kind == "reduce" then return acc end
    return checksum(dst, n)
  end
end

print("experimental stencil realization profile")
print("n", n, "rounds", rounds, "samples", samples, "chunk", chunk)
for _, kind in ipairs(kinds) do
  local selected = select_fixture(kind)
  local c = realize_with_c(selected)
  local bank, bank_build_time = build_bank(selected)
  local banked = realize_with_bank(selected, bank)
  local binary_bank, binary_build_time = build_binary_bank(selected)
  local binary = realize_with_binary_bank(selected, binary_bank)
  local vocab = tostring(selected.artifacts[1].instance.descriptor.vocab)
  print(string.format("%-8s vocab=%-24s lower=%7.3fms c_realize=%7.3fms c_emit=%6.3fms c_total=%7.3fms bank_build=%7.3fms bank_realize=%7.3fms bank_emit=%6.3fms bank_total=%7.3fms bin_build=%7.3fms bin_realize=%7.3fms bin_emit=%6.3fms bin_total=%7.3fms",
    kind, vocab,
    selected.lower_time * 1000,
    c.realize * 1000,
    c.emit * 1000,
    c.total * 1000,
    bank_build_time * 1000,
    banked.realize * 1000,
    banked.emit * 1000,
    banked.total * 1000,
    binary_build_time * 1000,
    binary.realize * 1000,
    binary.emit * 1000,
    binary.total * 1000
  ))
  local cases = {
    { name = kind .. ":lua_loop", fn = lua_case(kind) },
    { name = kind .. ":c_whole", fn = whole_case(kind, c.fn) },
    { name = kind .. ":bank_whole", fn = whole_case(kind, banked.fn) },
    { name = kind .. ":binary_whole", fn = whole_case(kind, binary.fn) },
    { name = kind .. ":binary_gps_chunks", fn = chunk_case(kind, binary.fn) },
    { name = kind .. ":binary_coroutine_chunks", fn = coroutine_chunk_case(kind, binary.fn) },
  }
  local results = Measure.measure(cases, { samples = samples, rounds = rounds, warmup = 2, jit_opts = { "hotloop=3", "hotexit=2" } })
  for i = 1, #results do print(Measure.format_result(results[i])) end
end
