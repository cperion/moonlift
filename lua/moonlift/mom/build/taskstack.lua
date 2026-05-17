-- MOM Task Stack — autonomous project management for AI porting agents.
--
-- Usage:
--   ./scripts/mom-task status           # show pending/completed with next task
--   ./scripts/mom-task progress         # progress bars for sections + lowering
--   ./scripts/mom-task list             # full details on all 18 sections
--   ./scripts/mom-task show <id|n>      # details on one section
--   ./scripts/mom-task done <id|n>      # mark section complete (verified)
--   ./scripts/mom-task reset <id|n>     # unmark section
--   ./scripts/mom-task verify           # check all files/exports exist
--   ./scripts/mom-task next             # show next recommended task
--   ./scripts/mom-task json             # machine-readable JSON status
--
-- State: lua/moonlift/mom/build/.taskstack_state.lua (git-tracked)
-- The port_map is the authoritative source; this file only tracks completion.
--
-- Auto-verification: when marking done, checks that expected source files
-- exist and expected exports are present. Prevents marking a section if its
-- dependencies are not met.

local PortMap = require("moonlift.mom.build.port_map")
local STATE_FILE = "lua/moonlift/mom/build/.taskstack_state.lua"

-- ── Section dependency graph (order-based from port_map) ──────────────

local DEPENDENCIES = {
  ["runtime-build-assembly"] = {},
  ["schema-tags"] = { "runtime-build-assembly" },
  ["document-lexer-parser-tree"] = { "schema-tags" },
  ["open-expansion"] = { "document-lexer-parser-tree" },
  ["typecheck"] = { "document-lexer-parser-tree" },
  ["layout-resolution"] = { "typecheck" },
  ["backend-ops-abi"] = { "schema-tags" },
  ["backend-command-api"] = { "backend-ops-abi" },
  ["backend-env-ids-symbols"] = { "schema-tags" },
  ["backend-expression-lowering"] = { "backend-command-api", "backend-env-ids-symbols" },
  ["backend-address-view-store-lowering"] = { "layout-resolution", "backend-command-api", "backend-env-ids-symbols" },
  ["backend-statement-lowering"] = { "backend-expression-lowering", "backend-address-view-store-lowering" },
  ["backend-control-lowering"] = { "backend-expression-lowering", "backend-statement-lowering" },
  ["backend-function-module-lowering"] = { "backend-expression-lowering", "backend-statement-lowering", "backend-control-lowering" },
  ["backend-validation"] = { "backend-command-api" },
  ["wire-backend-boundary"] = { "backend-command-api" },
  ["driver-source-to-wire-pipeline"] = { "document-lexer-parser-tree", "typecheck", "layout-resolution", "backend-function-module-lowering", "backend-validation", "wire-backend-boundary" },
  ["vectorization"] = { "backend-expression-lowering", "backend-statement-lowering" },
  ["product-api-cli"] = { "driver-source-to-wire-pipeline", "vectorization" },
  -- Lowering step deps for the sub-project
  ["step1"] = { "backend-env-ids-symbols" },
  ["step2"] = { "backend-command-api", "step1" },
  ["step3"] = { "step2" },
  ["step4"] = { "step3" },
  ["step5"] = { "step3", "step4" },
  ["step6"] = { "layout-resolution", "step3" },
  ["step7"] = { "step4", "step6" },
  ["step8"] = { "step7" },
  ["step9"] = { "step7" },
  ["step10"] = { "step9" },
}

-- ── Expected file/exports for auto-verification ────────────────────────

local VERIFICATION = {
  ["runtime-build-assembly"] = {
    files = { "lua/moonlift/mom/runtime/builders.mlua", "lua/moonlift/mom/runtime/sets.mlua", "lua/moonlift/mom/build/assemble.lua", "lua/moonlift/mom/build/manifest.lua", "lua/moonlift/mom/build/tags_gen.lua" },
    exports = { "mr_cmd_buffer_push", "mr_i32_builder_push", "mr_i32_map_put", "mr_fresh_value", "mr_fresh_block" },
  },
  ["schema-tags"] = {
    files = { "lua/moonlift/mom/schema/MoonCore.mlua", "lua/moonlift/mom/schema/MoonBack.mlua", "lua/moonlift/mom/tags/mom_tags.lua", "lua/moonlift/mom/back/back_tags.lua" },
    exports = {},
    test_files = { "tests/test_mom_groundwork.lua" },
  },
  ["document-lexer-parser-tree"] = {
    files = { "lua/moonlift/mom/parser/document_scan.mlua", "lua/moonlift/mom/parser/native_lexer.mlua", "lua/moonlift/mom/parser/native_core.mlua", "lua/moonlift/mom/parser/native_tree.mlua" },
    exports = { "mom_lex_into", "mom_parse_native_core", "mom_materialize_tree" },
  },
  ["typecheck"] = {
    files = { "lua/moonlift/mom/typecheck/type_check.mlua", "lua/moonlift/mom/typecheck/type_control.mlua" },
    exports = { "mt_type_expr", "mt_type_stmt", "mt_type_module" },
  },
  ["layout-resolution"] = {
    files = { "lua/moonlift/mom/layout/layout_env.mlua", "lua/moonlift/mom/layout/layout_field.mlua", "lua/moonlift/mom/layout/layout_resolve.mlua" },
    exports = {},
  },
  ["backend-ops-abi"] = {
    files = { "lua/moonlift/mom/back/ops.mlua", "lua/moonlift/mom/back/back_abi.mlua" },
    exports = { "mb_is_float_scalar", "mb_is_signed", "mb_core_scalar_to_back", "mb_lower_unary_op", "mb_binary_op_code", "mb_lower_compare_op", "mb_semantic_cast_op" },
  },
  ["backend-command-api"] = {
    files = { "lua/moonlift/mom/back/cmd.mlua" },
    exports = { "mb_cmd_const", "mb_cmd_int_binary", "mb_cmd_float_binary", "mb_cmd_compare", "mb_cmd_cast", "mb_cmd_select", "mb_cmd_call", "mb_cmd_create_block", "mb_cmd_br_if", "mb_cmd_jump", "mb_cmd_return_void", "mb_cmd_return_value", "mb_cmd_create_sig", "mb_cmd_declare_func" },
  },
  ["backend-env-ids-symbols"] = {
    files = { "lua/moonlift/mom/back/env.mlua", "lua/moonlift/mom/back/ids.mlua" },
    exports = { "mb_env_reset", "mb_env_bind_scalar", "mb_env_bind_view", "mb_env_lookup_into", "mb_fresh_value", "mb_fresh_block", "mb_ids_reset_func" },
  },
  ["backend-expression-lowering"] = {
    files = { "lua/moonlift/mom/back/expr_lower.mlua" },
    exports = { "mb_lower_expr", "mb_lower_lit", "mb_lower_binary_expr", "mb_lower_compare_expr", "mb_lower_cast_expr", "mb_lower_select_expr" },
    test_files = { "tests/test_mom_run_2plus2.lua" },
  },
  ["backend-address-view-store-lowering"] = {
    files = {},
    exports = {},
  },
  ["backend-statement-lowering"] = {
    files = { "lua/moonlift/mom/back/stmt_lower.mlua" },
    exports = { "mb_lower_stmt", "mb_lower_return_value", "mb_lower_let_stmt", "mb_lower_if_stmt" },
  },
  ["backend-control-lowering"] = {
    files = { "lua/moonlift/mom/back/control.mlua" },
    exports = { "mb_validate_control" },
  },
  ["backend-function-module-lowering"] = {
    files = { "lua/moonlift/mom/driver/compile_module.mlua" },
    exports = { "mc_lower_module" },
  },
  ["backend-validation"] = {
    files = { "lua/moonlift/mom/back/validate.mlua" },
    exports = { "mb_validate" },
  },
  ["wire-backend-boundary"] = {
    files = { "lua/moonlift/mom/driver/wire.mlua", "lua/moonlift/mom/driver/lower_wire.mlua", "lua/moonlift/mom/driver/backend_ffi.mlua" },
    exports = { "mom_lower_cmd_tape_to_wire" },
  },
  ["driver-source-to-wire-pipeline"] = {
    files = { "lua/moonlift/mom/driver/compile_source.mlua", "lua/moonlift/mom/driver/compile_module.mlua" },
    exports = { "mom_driver_compile_source_to_wire", "mc_lower_module" },
  },
  ["product-api-cli"] = {
    files = { "lua/moonlift/mom/driver/native_entry.mlua", "lua/moonlift/mom/driver/lua_api.mlua" },
    exports = { "mom_compile_source_to_wire_internal" },
  },
  ["vectorization"] = {
    files = { "lua/moonlift/mom/vec/vec_facts.mlua", "lua/moonlift/mom/vec/vec_decide.mlua", "lua/moonlift/mom/vec/vec_plan.mlua", "lua/moonlift/mom/vec/vec_lower.mlua" },
    exports = { "mv_extract_vec_facts", "mv_decide" },
  },
  ["product-api-cli"] = {
    files = { "lua/moonlift/mom/driver/native_entry.mlua", "lua/moonlift/mom/driver/lua_api.mlua" },
    exports = { "mom_compile_source_to_wire_internal" },
  },
}

-- ── Lowering step descriptions ────────────────────────────────────────

local LOWERING_STEPS = {
  "MomBackLowerCtx struct — typed lowering context (not yet created)",
  "mb_emit_* append helpers — in cmd.mlua (not yet created)",
  "Replace expr_lower.mlua — lit, ref, unary, binary, compare, cast, select, logic",
  "Replace stmt_lower.mlua — let, expr, scalar/void return, stmt list",
  "Function/module lowering — move from compile_module.mlua to back/func.mlua",
  "Address/view/store module — back/address.mlua (new)",
  "If/switch phi statements — proper branching with LocalCell analysis",
  "Control region lowering — back/control_lower.mlua (new)",
  "Memory/atomic/globals/view return — expand command families",
  "Vector integration — connect vec/*.mlua to lowering",
}

-- ── State ─────────────────────────────────────────────────────────────

local state = {}

local function load_state()
  local f = io.open(STATE_FILE, "r")
  if f then
    local content = f:read("*a")
    f:close()
    -- loadstring returns a function; we need to execute it to get the table
    local chunk = loadstring(content)
    if chunk then
      local ok, result = pcall(chunk)
      if ok and type(result) == "table" then
        state = result
        return
      end
    end
  end
  state = { done = {} }
end

local function save_state()
  local f = io.open(STATE_FILE, "w")
  if not f then
    io.stderr:write("error: cannot write " .. STATE_FILE .. "\n")
    return
  end
  f:write("-- Auto-generated task stack state.\n")
  f:write("return {\n")
  f:write("  done = {\n")
  local ids = {}
  for id, _ in pairs(state.done) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    f:write(string.format("    [%q] = true,\n", id))
  end
  f:write("  },\n")
  f:write("}\n")
  f:close()
end

local function is_done(id)
  return state.done[id] == true
end

local function mark_done(id)
  state.done[id] = true
  save_state()
end

local function mark_undone(id)
  state.done[id] = nil
  save_state()
end

-- ── File/existence verification helpers ───────────────────────────────

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local function file_contains_export(path, name)
  local f = io.open(path, "r")
  if not f then return false end
  local content = f:read("*a")
  f:close()
  -- Check for "M.xxx = xxx" or "M.export.xxx = xxx" patterns
  -- Split into lines for precise matching
  for line in content:gmatch("([^\n]+)") do
    if line:match("^M%." .. name .. "%s*=") then return true end
    if line:match("^M%.export%." .. name .. "%s*=") then return true end
  end
  return false
end

local function verify_section(id)
  local v = VERIFICATION[id]
  if not v then return { ok = true, issues = {} } end
  local issues = {}
  -- Check required files exist
  for _, path in ipairs(v.files or {}) do
    if not file_exists(path) then
      issues[#issues + 1] = "MISSING FILE: " .. path
    end
  end
  -- Check expected exports exist in corresponding files
  for _, name in ipairs(v.exports or {}) do
    local found = false
    for _, path in ipairs(v.files or {}) do
      if file_contains_export(path, name) then
        found = true
        break
      end
    end
    if not found then
      issues[#issues + 1] = "MISSING EXPORT: " .. name
    end
  end
  return { ok = #issues == 0, issues = issues }
end

local function check_dependencies_satisfied(id)
  local deps = DEPENDENCIES[id]
  if not deps then return { ok = true, missing = {} } end
  local missing = {}
  for _, dep in ipairs(deps) do
    if not is_done(dep) then
      missing[#missing + 1] = dep
    end
  end
  return { ok = #missing == 0, missing = missing }
end

-- ── Display helpers ───────────────────────────────────────────────────

local function concat_list(items)
  if not items or #items == 0 then return "-" end
  local parts = {}
  for _, v in ipairs(items) do parts[#parts + 1] = v end
  return table.concat(parts, ", ")
end

local function find_next_task()
  -- Find the first section in order that is not done and has deps satisfied
  for _, s in ipairs(PortMap.sections) do
    if not is_done(s.id) then
      local deps = check_dependencies_satisfied(s.id)
      if deps.ok then
        return s
      end
    end
  end
  return nil
end

-- ── Commands ───────────────────────────────────────────────────────────

local function cmd_progress()
  load_state()
  local total = #PortMap.sections
  local done_count = 0
  local total_steps = #LOWERING_STEPS
  local done_steps = 0
  for _, s in ipairs(PortMap.sections) do
    if is_done(s.id) then done_count = done_count + 1 end
  end
  for i = 1, total_steps do
    if is_done("step" .. i) then done_steps = done_steps + 1 end
  end
  local pct = total > 0 and math.floor(done_count / total * 100) or 0
  local step_pct = total_steps > 0 and math.floor(done_steps / total_steps * 100) or 0
  local bar_w = 30

  local function bar(p)
    local filled = math.floor(bar_w * p / 100)
    return string.rep("█", filled) .. string.rep("░", bar_w - filled)
  end

  print("╔══════════════════════════════════════╗")
  print("║        MOM PORT PROGRESS             ║")
  print("╠══════════════════════════════════════╣")
  print(string.format("║ Sections:  %s %3d%% ║", bar(pct), pct))
  print(string.format("║            %d/%d complete           ║", done_count, total))
  print(string.format("║ Lowering:  %s %3d%% ║", bar(step_pct), step_pct))
  print(string.format("║            %d/%d steps complete     ║", done_steps, total_steps))
  print("╚══════════════════════════════════════╝")
  print("")
  -- Show next task
  local next = find_next_task()
  if next then
    print(string.format("→ Next task: %s (%s)", next.id, next.status or ""))
  else
    print("→ All tasks complete!")
  end
  print("")
end

local function cmd_status()
  load_state()
  local total = #PortMap.sections
  local done_count = 0
  for _, s in ipairs(PortMap.sections) do
    if is_done(s.id) then done_count = done_count + 1 end
  end
  print(string.format("Sections: %d/%d done", done_count, total))
  print("")

  for _, s in ipairs(PortMap.sections) do
    local mark = is_done(s.id) and "✓" or " "
    local deps = check_dependencies_satisfied(s.id)
    local dep_mark = deps.ok and "" or " (blocked: " .. concat_list(deps.missing) .. ")"
    print(string.format("  [%s] %2d. %s%s", mark, s.order, s.id, dep_mark))
  end

  print("")
  print("── Lowering steps ──")
  for i, desc in ipairs(LOWERING_STEPS) do
    local mark = is_done("step" .. i) and "✓" or " "
    local deps = check_dependencies_satisfied("step" .. i)
    local dep_mark = deps.ok and "" or " (blocked)"
    print(string.format("  [%s] Step %d: %s%s", mark, i, desc, dep_mark))
  end

  print("")
  local next = find_next_task()
  if next then
    print(string.format("→ Next: %s", next.id))
  end
end

local function cmd_list()
  load_state()
  for _, s in ipairs(PortMap.sections) do
    local mark = is_done(s.id) and "✓" or " "
    local status = s.status or "pending"
    print(string.format("[%s] %2d. %s", mark, s.order, s.id))
    print(string.format("     Status: %s", status))
    local files = concat_list(s.manifest)
    print(string.format("     Files:  %s", files))
    if s.responsibilities then
      for _, r in ipairs(s.responsibilities) do
        print(string.format("     • %s", r))
      end
    end
    if s.hosted_oracles then
      print(string.format("     Oracle: %s", concat_list(s.hosted_oracles)))
    end
    print("")
  end

  print("── Lowering steps ──")
  for i, desc in ipairs(LOWERING_STEPS) do
    local mark = is_done("step" .. i) and "✓" or " "
    print(string.format("  [%s] Step %d: %s", mark, i, desc))
  end
end

local function cmd_show(id)
  load_state()
  -- Find by id or numeric index
  local section = nil
  for _, s in ipairs(PortMap.sections) do
    if s.id == id or tostring(s.order) == id then
      section = s
      break
    end
  end
  if not section then
    print(string.format("Unknown section: %q", id))
    return
  end

  local mark = is_done(section.id) and "✓" or " "
  print(string.format("[%s] %2d. %s", mark, section.order, section.id))
  print(string.format("   Status: %s", section.status or "pending"))
  print(string.format("   Files:  %s", concat_list(section.manifest)))
  print(string.format("   Oracle: %s", concat_list(section.hosted_oracles)))
  print("")
  if section.responsibilities then
    print("   Responsibilities:")
    for _, r in ipairs(section.responsibilities) do
      print(string.format("     • %s", r))
    end
  end
  if section.native_targets then
    print(string.format("   Native targets: %s", concat_list(section.native_targets)))
  end
  if section.tests then
    print(string.format("   Tests: %s", concat_list(section.tests)))
  end
  if section.required_append_helpers then
    print("   Required cmd helpers:")
    for _, h in ipairs(section.required_append_helpers) do
      print(string.format("     • %s", h))
    end
  end
  if section.entrypoints then
    print("   Entry points:")
    for _, ep in ipairs(section.entrypoints) do
      print(string.format("     • %s: %s", ep.name, ep.signature or ""))
    end
  end
  -- Dependencies
  local deps = DEPENDENCIES[section.id]
  if deps and #deps > 0 then
    print(string.format("   Depends on: %s", concat_list(deps)))
  end
  -- Verification
  local v = verify_section(section.id)
  if not v.ok then
    print("   Verification issues:")
    for _, issue in ipairs(v.issues) do
      print(string.format("     ! %s", issue))
    end
  else
    print("   Verification: OK")
  end
end

local function cmd_done(task_id)
  load_state()
  -- Check section ids
  for _, s in ipairs(PortMap.sections) do
    if s.id == task_id or tostring(s.order) == task_id then
      if is_done(s.id) then
        print(string.format("Section %q already done.", s.id))
        return
      end
      -- Verify dependencies
      local deps = check_dependencies_satisfied(s.id)
      if not deps.ok then
        print(string.format("ERROR: dependencies not satisfied: %s", concat_list(deps.missing)))
        print("Complete those sections first.")
        return
      end
      -- Auto-verify
      local v = verify_section(s.id)
      if not v.ok then
        print(string.format("WARNING: auto-verification found issues:"))
        for _, issue in ipairs(v.issues) do
          print(string.format("  ! %s", issue))
        end
        print("Marking done anyway. Fix warnings ASAP.")
      end
      mark_done(s.id)
      print(string.format("✓ Marked %q as done.", s.id))
      -- Show next task
      local next = find_next_task()
      if next then
        print(string.format("→ Next: %s", next.id))
      end
      return
    end
  end
  -- Check lowering steps
  local n = tonumber(task_id:match("^step(%d+)$"))
  if n and n >= 1 and n <= #LOWERING_STEPS then
    local key = "step" .. n
    if is_done(key) then
      print(string.format("Step %d already done.", n))
      return
    end
    local deps = check_dependencies_satisfied(key)
    if not deps.ok then
      print(string.format("ERROR: step %d dependencies not satisfied: %s", n, concat_list(deps.missing)))
      return
    end
    mark_done(key)
    print(string.format("✓ Marked lowering step %d as done.", n))
    local next = find_next_task()
    if next then
      print(string.format("→ Next: %s", next.id))
    end
    return
  end
  print(string.format("Unknown task: %q", task_id))
end

local function cmd_reset(task_id)
  load_state()
  for _, s in ipairs(PortMap.sections) do
    if s.id == task_id or tostring(s.order) == task_id then
      mark_undone(s.id)
      print(string.format("○ Reset %q to pending.", s.id))
      return
    end
  end
  local n = tonumber(task_id:match("^step(%d+)$"))
  if n and n >= 1 and n <= #LOWERING_STEPS then
    mark_undone("step" .. n)
    print(string.format("○ Reset lowering step %d to pending.", n))
    return
  end
  print(string.format("Unknown task: %q", task_id))
end

local function cmd_verify()
  load_state()
  local all_ok = true
  for _, s in ipairs(PortMap.sections) do
    local v = verify_section(s.id)
    if not v.ok then
      print(string.format("✗ %s:", s.id))
      for _, issue in ipairs(v.issues) do
        print(string.format("    %s", issue))
      end
      all_ok = false
    end
  end
  if all_ok then
    print("✓ All sections verified.")
  end
end

local function cmd_next()
  load_state()
  local next = find_next_task()
  if next then
    print(string.format("Next task: %s (%s)", next.id, next.status or ""))
    -- Show detailed info
    cmd_show(next.id)
  else
    print("All tasks complete!")
  end
end


local function cmd_json()
  load_state()
  local result = {
    sections = {},
    lowering_steps = {},
    meta = {
      total_sections = #PortMap.sections,
      done_sections = 0,
      total_steps = #LOWERING_STEPS,
      done_steps = 0,
    }
  }
  for _, s in ipairs(PortMap.sections) do
    local done = is_done(s.id)
    if done then result.meta.done_sections = result.meta.done_sections + 1 end
    table.insert(result.sections, {
      id = s.id,
      order = s.order,
      status = s.status,
      done = done,
      files = s.manifest,
    })
  end
  for i, desc in ipairs(LOWERING_STEPS) do
    local done = is_done("step" .. i)
    if done then result.meta.done_steps = result.meta.done_steps + 1 end
    table.insert(result.lowering_steps, {
      step = i,
      description = desc,
      done = done,
    })
  end
  local next = find_next_task()
  if next then result.next_task = next.id end
  print("{")
  print('  "meta": {')
  print(string.format('    "total_sections": %d,', result.meta.total_sections))
  print(string.format('    "done_sections": %d,', result.meta.done_sections))
  print(string.format('    "total_steps": %d,', result.meta.total_steps))
  print(string.format('    "done_steps": %d', result.meta.done_steps))
  print('  },')
  if result.next_task then
    print(string.format('  "next_task": %q,', result.next_task))
  end
  print('  "sections": [')
  for i, s in ipairs(result.sections) do
    local comma = i < #result.sections and "," or ""
    print(string.format('    {"id": %q, "order": %d, "done": %s}%s', s.id, s.order, tostring(s.done), comma))
  end
  print('  ],')
  print('  "lowering_steps": [')
  for i, s in ipairs(result.lowering_steps) do
    local comma = i < #result.lowering_steps and "," or ""
    print(string.format('    {"step": %d, "done": %s}%s', s.step, tostring(s.done), comma))
  end
  print('  ]')
  print("}")
end

-- ── Main CLI ───────────────────────────────────────────────────────────

local cmd = arg and arg[1]
if cmd == "status" then
  cmd_status()
elseif cmd == "done" then
  if not arg[2] then print("Usage: ./scripts/mom-task done <section_id|index|stepN>"); return end
  cmd_done(arg[2])
elseif cmd == "reset" then
  if not arg[2] then print("Usage: ./scripts/mom-task reset <section_id|index|stepN>"); return end
  cmd_reset(arg[2])
elseif cmd == "progress" then
  cmd_progress()
elseif cmd == "show" then
  if not arg[2] then print("Usage: ./scripts/mom-task show <section_id|index>"); return end
  cmd_show(arg[2])
elseif cmd == "verify" then
  cmd_verify()
elseif cmd == "next" then
  cmd_next()
elseif cmd == "json" then
  cmd_json()
elseif cmd == "list" or cmd == nil then
  cmd_list()
else
  print("Usage: ./scripts/mom-task [status|done <id>|reset <id>|progress|show <id>|verify|next|json|list]")
end
