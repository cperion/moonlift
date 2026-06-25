-- lua_exec_static_region_inline.lua -- inline typed LuaExec.Module static invocations.
--
-- This is a pre-LalinCFG lowering pass.  LuaExec.EmitRegion is accepted only
-- inside a LuaExec.Module with matching typed StaticRegionInvocation contracts;
-- kernel-only lowering still rejects EmitRegion.

local Schema = require("lua_compile.schema")
local pvm = require("lalin.pvm")
local T = Schema.get()
local Exec, Compile = T.LuaExec, T.LuaCompile
local ExecValidate = require("lua_compile.lua_exec_validate")
local StaticRegionModel = require("lua_compile.lua_exec_static_region_model")

local M = {}

local function cls(v) return pvm.classof(v) end
local function add(errors, msg) errors[#errors + 1] = msg end
local function name_text(name) return name and name.text or nil end
local function block_id_key(id) return StaticRegionModel.block_id_key(id) end
local function block_ref_key(ref) return StaticRegionModel.block_ref_key(ref) end
local function cont_ref_key(ref) return StaticRegionModel.cont_ref_key(ref) end
local function prefixed_name(prefix, text) return Exec.Name(prefix .. tostring(text)) end
local function prefixed_block_id(prefix, id) return Exec.BlockId(prefixed_name(prefix, block_id_key(id))) end
local function prefixed_block_ref(prefix, ref) return Exec.BlockRef(prefixed_block_id(prefix, ref.id)) end

local function select_kernel(module, kernel_name, errors)
  local kernels = module.kernels or {}
  if kernel_name ~= nil then
    local want = type(kernel_name) == "string" and kernel_name or name_text(kernel_name)
    for _, kernel in ipairs(kernels) do if kernel.id and kernel.id.text == want then return kernel end end
    add(errors, "kernel not found in module: " .. tostring(want))
    return nil
  end
  if #kernels ~= 1 then add(errors, "kernel_name required when module has " .. tostring(#kernels) .. " kernels"); return nil end
  return kernels[1]
end

local function block_map_for_region(region, prefix)
  local map = {}
  for _, block in ipairs(region.blocks or {}) do
    map[block_id_key(block.id)] = prefixed_block_id(prefix, block.id)
  end
  return map
end

local function cloned_block_ref(map, ref)
  local key = block_ref_key(ref)
  local id = key and map[key]
  if id then return Exec.BlockRef(id) end
  return nil
end

local function binding_by_cont(bindings)
  local out = {}
  for _, binding in ipairs(bindings or {}) do out[cont_ref_key(binding.continuation)] = binding end
  return out
end

local function choose_continue_args(term_args, binding_args)
  if term_args and #term_args > 0 then return term_args end
  return binding_args or {}
end

local function rewrite_terminator(term, map, invocation, emit_op, errors)
  local c = cls(term)
  if c == Exec.Jump then
    local target = cloned_block_ref(map, term.target)
    if not target then add(errors, "target jump leaves static region: " .. tostring(block_ref_key(term.target))); return nil end
    return Exec.Jump(target, term.args or {})
  elseif c == Exec.Branch then
    local t = cloned_block_ref(map, term.if_true)
    local f = cloned_block_ref(map, term.if_false)
    if not t or not f then add(errors, "branch target leaves static region"); return nil end
    return Exec.Branch(term.choice, t, f)
  elseif c == Exec.BranchArgs then
    local t = cloned_block_ref(map, term.if_true)
    local f = cloned_block_ref(map, term.if_false)
    if not t or not f then add(errors, "branch target leaves static region"); return nil end
    return Exec.BranchArgs(term.choice, t, term.true_args or {}, f, term.false_args or {})
  elseif c == Exec.Continue then
    local bindings = binding_by_cont((emit_op and emit_op.continuations) or (invocation and invocation.continuations) or {})
    local ck = cont_ref_key(term.continuation)
    local binding = bindings[ck]
    if not binding then add(errors, "unbound static continuation: " .. tostring(ck)); return nil end
    return Exec.Jump(binding.target, choose_continue_args(term.args, binding.args))
  elseif c == Exec.Unreachable or (term and term.kind == "Unreachable") then
    return Exec.Unreachable
  elseif c == Exec.Return or c == Exec.Error or c == Exec.Yield then
    add(errors, "static target Return/Error/Yield terminators are not inlineable: " .. tostring(term.kind))
    return nil
  end
  add(errors, "unsupported static target terminator: " .. tostring(term and term.kind))
  return nil
end

local function clone_target_blocks(target, invocation, emit_op, prefix, errors)
  local map = block_map_for_region(target, prefix)
  local out = {}
  for _, block in ipairs(target.blocks or {}) do
    for _, op in ipairs(block.ops or {}) do
      if cls(op) == Exec.EmitRegion then add(errors, "nested EmitRegion is not supported in static target") end
    end
    local term = rewrite_terminator(block.terminator, map, invocation, emit_op, errors)
    if not term then return nil end
    out[#out + 1] = Exec.Block(prefixed_block_id(prefix, block.id), block.params or {}, block.ops or {}, term)
  end
  return out
end

local function target_entry_ref(target, prefix)
  return Exec.BlockRef(prefixed_block_id(prefix, target.entry))
end

local function inline_emit_block(block, emit_index, target, invocation, ordinal, errors)
  if #(target.params or {}) > 0 then
    add(errors, "static target region params are not supported by this inliner milestone")
    return nil
  end
  local emit_op = block.ops[emit_index]
  if #(emit_op.args or {}) > 0 then
    add(errors, "EmitRegion args require target region params, which are not supported by this inliner milestone")
    return nil
  end
  local prefix = "__static_" .. tostring(target.id.text) .. "_" .. tostring(ordinal) .. "__"
  local cloned = clone_target_blocks(target, invocation, emit_op, prefix, errors)
  if not cloned then return nil end
  local ops = {}
  for i = 1, emit_index - 1 do ops[#ops + 1] = block.ops[i] end
  local caller = Exec.Block(block.id, block.params or {}, ops, Exec.Jump(target_entry_ref(target, prefix), emit_op.args or {}))
  return caller, cloned
end

local function inline_module_kernel_uncached(module, kernel_name)
  local errors = {}
  local ok_module, module_errors = ExecValidate.module(module)
  if not ok_module then return nil, module_errors end
  local index, index_errors = StaticRegionModel.index_module(module)
  if not index then return nil, index_errors end
  local kernel = select_kernel(module, kernel_name, errors)
  if not kernel then return nil, errors end

  local new_blocks = {}
  local ordinal = 0
  for _, block in ipairs(kernel.body.blocks or {}) do
    local emit_index, emit_op
    for i, op in ipairs(block.ops or {}) do
      if cls(op) == Exec.EmitRegion then
        if emit_index then add(errors, "multiple EmitRegion ops in one block are not supported") end
        emit_index, emit_op = i, op
      end
    end
    if not emit_index then
      new_blocks[#new_blocks + 1] = block
    else
      local shape_ok, shape_errors = StaticRegionModel.validate_emit_op_inline_shape(block, emit_index)
      if not shape_ok then for _, e in ipairs(shape_errors) do add(errors, e) end end
      local invocation, find_errors = StaticRegionModel.find_invocation_for_emit(kernel.contract, emit_op)
      if not invocation then
        for _, e in ipairs(find_errors or {}) do add(errors, e) end
      else
        local inv_ok, inv_errors = StaticRegionModel.validate_invocation_against_module(index, invocation)
        if not inv_ok then for _, e in ipairs(inv_errors) do add(errors, e) end end
        local target_name = StaticRegionModel.region_ref_key(invocation.target.region)
        local target = index.regions[target_name]
        if target then
          local target_ok, target_errors = StaticRegionModel.validate_target_region_for_inline(target, invocation, kernel.contract)
          if not target_ok then for _, e in ipairs(target_errors) do add(errors, e) end end
          if #errors == 0 then
            ordinal = ordinal + 1
            local caller, cloned = inline_emit_block(block, emit_index, target, invocation, ordinal, errors)
            if caller and cloned then
              new_blocks[#new_blocks + 1] = caller
              for _, cloned_block in ipairs(cloned) do new_blocks[#new_blocks + 1] = cloned_block end
            end
          end
        end
      end
    end
  end
  if #errors > 0 then return nil, errors end
  local body = kernel.body
  local inlined_region = Exec.Region(body.id, body.kind, body.params or {}, body.continuations or {}, body.entry, new_blocks)
  local inlined_kernel = Exec.Kernel(kernel.id, kernel.frame, inlined_region, kernel.contract)
  local ok, validate_errors = ExecValidate.kernel(inlined_kernel)
  if not ok then return nil, validate_errors end
  return inlined_kernel, nil
end

local phase = pvm.phase("spongejit_lua_exec_static_region_inline", function(module, kernel_name)
  local kernel, errors = inline_module_kernel_uncached(module, kernel_name ~= "" and kernel_name or nil)
  if not kernel then return Compile.StaticInlineReject(errors or { "static_inline_failed" }) end
  return Compile.StaticInlineOk(kernel)
end, { args_cache = "last" })

function M.inline_result(module, kernel_name)
  return pvm.one(phase(module, kernel_name or ""))
end

function M.inline_module_kernel(module, kernel_name)
  local result = M.inline_result(module, kernel_name)
  if pvm.classof(result) == Compile.StaticInlineReject then return nil, result.errors end
  if pvm.classof(result) == Compile.StaticInlineOk then return result.kernel, nil end
  return nil, { "static_inline_invalid_result" }
end

M.phase = phase
M.inline_module_kernel_uncached = inline_module_kernel_uncached

return M
