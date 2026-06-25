-- lua_compile/validate.lua -- shared cross-layer invariants.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local LuaFFIValidate = require("lua_compile.lua_ffi_validate")
local LuaGCValidate = require("lua_compile.lua_gc_validate")
local LuaRTValidate = require("lua_compile.lua_rt_validate")
local LuaExecValidate = require("lua_compile.lua_exec_validate")

local M = {}

local FORBIDDEN_PHYSICAL = { gpr0 = true, rax = true, rcx = true, rdx = true, rdi = true, rsi = true, rsp = true, rbp = true, x64 = true }

local function add(errors, msg) errors[#errors + 1] = msg end
local function walk(v, fn, seen)
  if type(v) ~= "table" then fn(v); return end
  seen = seen or {}
  if seen[v] then return end
  seen[v] = true
  fn(v)
  local cls = pvm.classof(v)
  if cls and rawget(cls, "__fields") then
    for _, f in ipairs(cls.__fields) do walk(v[f.name], fn, seen) end
  elseif not cls then
    for _, x in pairs(v) do walk(x, fn, seen) end
  end
end

function M.no_physical_residency(node)
  local errors = {}
  walk(node, function(v)
    if type(v) == "string" and FORBIDDEN_PHYSICAL[v] then add(errors, "physical residency leaked into semantic product: " .. v) end
  end)
  return #errors == 0, errors
end

function M.lua_src_window(window)
  local errors = {}
  if pvm.classof(window) ~= T.LuaSrc.Window then add(errors, "expected LuaSrc.Window") end
  local ops = (window and window.ops) or {}
  local needs_jmp = { EQ = true, LT = true, LE = true, EQK = true, EQI = true, LTI = true, LEI = true, GTI = true, GEI = true, TEST = true, TESTSET = true }
  for i, op in ipairs(ops) do
    if not T.LuaSrc.Op.members[pvm.classof(op)] then add(errors, "window op " .. i .. " is not LuaSrc.Op") end
    if needs_jmp[op.kind] and not (ops[i + 1] and ops[i + 1].kind == "JMP") then add(errors, op.kind .. " at window op " .. i .. " must preserve following JMP companion") end
    if op.kind == "LOADKX" and not op.has_extraarg then add(errors, "LOADKX at window op " .. i .. " must preserve following EXTRAARG Ax") end
    if (op.kind == "SETLIST" or op.kind == "NEWTABLE") and op.uses_extraarg and not (ops[i + 1] and ops[i + 1].kind == "EXTRAARG") then add(errors, op.kind .. " at window op " .. i .. " must preserve following EXTRAARG companion") end
  end
  return #errors == 0, errors
end

function M.lua_fact_evidence(evidence)
  local errors = {}
  if pvm.classof(evidence) ~= T.LuaFact.Evidence then add(errors, "expected LuaFact.Evidence") end
  return #errors == 0, errors
end

function M.compile_contract(contract)
  return require("lua_compile.compile_contract_validate").validate(contract)
end

function M.compile_diagnostic(diagnostic)
  local errors = {}
  if pvm.classof(diagnostic) ~= T.LuaCompile.Diagnostic then add(errors, "expected LuaCompile.Diagnostic") end
  return #errors == 0, errors
end

function M.lua_ffi_ctype(ctype)
  return LuaFFIValidate.ctype(ctype)
end

function M.lua_ffi_record_layout(layout)
  return LuaFFIValidate.record_layout(layout)
end

function M.lua_ffi_symbol(symbol)
  return LuaFFIValidate.symbol(symbol)
end

function M.lua_ffi_cdata(cdata)
  return LuaFFIValidate.cdata(cdata)
end

function M.lua_ffi_registry(registry)
  return LuaFFIValidate.registry(registry)
end

function M.lua_gc_state(state)
  return LuaGCValidate.gc_state(state)
end

function M.lua_gc_header(header)
  return LuaGCValidate.header(header)
end

function M.lua_gc_barrier_kind(barrier)
  return LuaGCValidate.barrier_kind(barrier)
end

function M.lua_gc_root_set(root_set)
  return LuaGCValidate.root_set(root_set)
end

function M.lua_gc_fact(fact)
  return LuaGCValidate.gc_fact(fact)
end

function M.lua_rt_tvalue(value)
  return LuaRTValidate.tvalue(value)
end

function M.lua_rt_frame(frame)
  return LuaRTValidate.frame(frame)
end

function M.lua_exec_region(region)
  return LuaExecValidate.region(region)
end

function M.lua_exec_kernel(kernel)
  return LuaExecValidate.kernel(kernel)
end

function M.lua_exec_module(module)
  return LuaExecValidate.module(module)
end

function M.lalin_cfg_kernel(kernel)
  local errors = {}
  if pvm.classof(kernel) ~= T.LalinCFG.Kernel then add(errors, "expected LalinCFG.Kernel") end
  return #errors == 0, errors
end

function M.stencil_module(module)
  local errors = {}
  if pvm.classof(module) ~= T.Stencil.StencilModule then add(errors, "expected Stencil.StencilModule") end
  return #errors == 0, errors
end

function M.stencil_template(template)
  local errors = {}
  if pvm.classof(template) ~= T.Stencil.StencilTemplate then add(errors, "expected Stencil.StencilTemplate") end
  return #errors == 0, errors
end

function M.stencil_materialized_image(image)
  local errors = {}
  if pvm.classof(image) ~= T.Stencil.MaterializedImage then add(errors, "expected Stencil.MaterializedImage") end
  return #errors == 0, errors
end

function M.stencil_materialized_bundle(bundle)
  local errors = {}
  if pvm.classof(bundle) ~= T.Stencil.MaterializedBundle then add(errors, "expected Stencil.MaterializedBundle") end
  return #errors == 0, errors
end

return M
