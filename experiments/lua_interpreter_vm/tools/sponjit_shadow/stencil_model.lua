-- stencil_model.lua — Stencil vocabulary, lowering, and artifact template generation
-- for the SponJIT foundry. This is the bridge from SSA optimized node lists to
-- copy-and-patch templates. The "asm" is abstract for now; real bytes come
-- from C/GCC stencils (see stencils/ directory).
--
--   SSA node list   →   stencil cover   →   artifact template
--   (optimized)          (this module)       (bytes + holes + contract)

local Util = require("tools.jit_harness.util")
local SSA = require("tools.sponjit_shadow.foundry_ssa")

local M = {}

-- ── stencil vocabulary ──────────────────────────────────────────────────
-- Each stencil: name, covers which SSA node(s), abstract cost (cycles),
-- byte size, hole kinds, residency class, effect class.

local STENCILS = {}

local function def(name, t)
    t.name = name
    STENCILS[name] = t
    STENCILS[#STENCILS + 1] = t
end

-- Guards (checked facts → exit on mismatch)
def("guard_i64",             { covers={"guard_i64"},              kind="guard",  size=8,  cost=3 })
def("guard_table",           { covers={"guard_table"},            kind="guard",  size=8,  cost=3 })
def("guard_shape",           { covers={"guard_shape"},            kind="guard",  size=12, cost=4 })
def("guard_metatable_absent",{ covers={"guard_metatable_absent"}, kind="guard",  size=8,  cost=3 })
def("guard_call_target",     { covers={"guard_call_target"},      kind="guard",  size=8,  cost=3 })
def("guard_array_hit",       { covers={"guard_array_hit"},        kind="guard",  size=8,  cost=3 })
def("guard_bounds",          { covers={"guard_bounds"},           kind="guard",  size=12, cost=4 })

-- Slots (frame-local value movement)
def("load_slot",             { covers={"load_slot"},  kind="pure",       size=4,  cost=1, residency={out="any"} })
def("store_slot",            { covers={"store_slot"}, kind="frame_write",size=4,  cost=1 })
def("move_value",            { covers={"move_value"},kind="pure",       size=4,  cost=1, residency={["in"]="in"} })

-- Constants
def("load_const",            { covers={"load_const"},            kind="pure",  size=12, cost=2, holes={"const_idx"}, residency={out="any"} })
def("const_i64",             { covers={"const_i64"},             kind="pure",  size=12, cost=2, holes={"const_i64"},  residency={out="gpr0"} })
def("const_nil",             { covers={"const_nil"},             kind="pure",  size=4,  cost=1, residency={out="any"} })
def("const_bool",            { covers={"const_bool"},            kind="pure",  size=4,  cost=1, residency={out="any"} })
def("const_f64",             { covers={"const_f64"},             kind="pure",  size=16, cost=4, holes={"const_f64"},  residency={out="xmm0"} })

-- Box/unbox (tag <-> native value)
def("box_i64",               { covers={"box_i64"},   kind="pure",  size=8,  cost=3, residency={["in"]="gpr0", out="any"} })
def("unbox_i64",             { covers={"unbox_i64"}, kind="pure",  size=8,  cost=3, residency={["in"]="any", out="gpr0"} })
def("box_f64",               { covers={"box_f64"},   kind="pure",  size=12, cost=4, residency={["in"]="xmm0", out="any"} })
def("unbox_f64",             { covers={"unbox_f64"}, kind="pure",  size=12, cost=4, residency={["in"]="any", out="xmm0"} })

-- Arithmetic (native i64, residency gpr0→gpr0)
def("add_i64",               { covers={"add_i64","sub_i64","mul_i64"}, kind="pure", size=4,  cost=1, residency={in1="gpr0", in2="gpr0", out="gpr0"}, fused=true })
def("cmp_i64",               { covers={"cmp_i64","truthy_test"}, kind="pure", size=4,  cost=1, residency={in1="gpr0", in2="gpr0", out="flags"}, fused=true })
def("add_f64",               { covers={"add_f64","sub_f64","mul_f64","cmp_f64"}, kind="pure", size=8,  cost=3, residency={in1="xmm0", in2="xmm0", out="xmm0"}, fused=true })

-- Table field access (keyed by shape + constant field key)
def("table_field_load",      { covers={"table_field_load"},  kind="pure",       size=8,  cost=3, holes={"field_offset"}, residency={["in"]="any", out="any"} })
def("table_field_store",     { covers={"table_field_store"}, kind="heap_write",  size=8,  cost=3, holes={"field_offset"} })
def("table_array_load",      { covers={"table_array_load"},  kind="pure",       size=12, cost=4, holes={"array_base","index_scale"} })
def("table_array_store",     { covers={"table_array_store"}, kind="heap_write",  size=12, cost=4, holes={"array_base","index_scale"} })
def("table_global_load",     { covers={"table_global_load"},  kind="pure",      size=16, cost=6, holes={"global_name","shape_id"} })
def("table_global_store",    { covers={"table_global_store"}, kind="heap_write", size=16, cost=6, holes={"global_name","shape_id"} })

-- Call / return
def("call_boundary",         { covers={"call_boundary","call_boundary_known"}, kind="call", size=20, cost=18, holes={"call_target","nargs","nresults"}, residency={["in"]="any", out="any"} })
def("tailcall_boundary",     { covers={"tailcall_boundary"}, kind="call",       size=20, cost=18, holes={"call_target","nargs"} })
def("return0",               { covers={"return0"},            kind="return",     size=4,  cost=2 })
def("return1",               { covers={"return1"},            kind="return",     size=4,  cost=2, residency={["in"]="any"} })
def("returnN",               { covers={"returnN"},            kind="return",     size=16, cost=6, holes={"nresults"} })

-- Other
def("barrier_check",         { covers={"barrier_check"},      kind="gc_barrier", size=12, cost=5, holes={"barrier_color"} })
def("residual_boundary",     { covers={"residual_boundary"},  kind="residual",   size=8,  cost=30 })
def("jump",                  { covers={"jump"},               kind="branch",     size=8,  cost=3, holes={"target_pc"} })
def("branch",                { covers={"branch"},             kind="branch",     size=12, cost=4, holes={"target_pc"} })  -- conditional: reads flags

-- ── Fused stencils (cover multiple SSA nodes with one stencil) ──────────
-- These are discovered by the foundry and added to the vocabulary.

def("unbox_add_i64_box", {
    covers = {"unbox_i64","add_i64","box_i64"},
    kind = "pure",
    size = 12, cost = 4,
    residency = { ["in"] = "any", out = "any" },
    fuse_of = {"unbox_i64","add_i64","box_i64"},
})

def("table_field_load_return1", {
    covers = {"table_field_load","return1"},
    kind = "return",
    size = 10, cost = 4,
    holes = {"field_offset"},
    fuse_of = {"table_field_load","return1"},
})

def("table_field_load_add_i64_store", {
    covers = {"table_field_load","unbox_i64","add_i64","box_i64","table_field_store"},
    kind = "heap_write",
    size = 16, cost = 5,
    holes = {"field_offset"},
    fuse_of = {"table_field_load","unbox_i64","add_i64","box_i64","table_field_store"},
})

-- ── Load real stencil sizes from GCC-compiled library ──────────────────

local REAL_SIZES = nil

function M.load_real_library(json_path)
    local ok, data = pcall(function() return Util.read_json(json_path) end)
    if ok and data and data.stencils then
        REAL_SIZES = {}
        for name, s in pairs(data.stencils) do
            REAL_SIZES[name] = { size = s.size, holes = s.holes, cost = s.cost }
        end
        for _, s in ipairs(STENCILS) do
            local r = REAL_SIZES[s.name]
            if r then
                s.real_size = r.size
                s.real_cost = r.cost
                s.real_holes = r.holes
            end
        end
        return true
    end
    return false
end

function M.using_real_sizes()
    return REAL_SIZES ~= nil
end

-- ── hole representation ─────────────────────────────────────────────────
-- hole = { name, offset_in_template, size_in_bytes, kind, value_at_foundry_time? }

-- ── lowering: SSA node list → stencil cover ──────────────────────────────

local COVERS = {}
for _, s in ipairs(STENCILS) do
    for _, c in ipairs(s.covers or {}) do COVERS[c] = COVERS[c] or {}; COVERS[c][#COVERS[c]+1] = s end
end

local function find_cover(node_op)
    local cands = COVERS[node_op]
    if not cands or #cands == 0 then return nil end
    -- Prefer fused stencils when possible; they cover more nodes and are cheaper.
    table.sort(cands, function(a, b) return (a.fuse_of and #a.fuse_of or 1) > (b.fuse_of and #b.fuse_of or 1) end)
    return cands[1]
end

local function fuse_match(nodes, i, fuse_of)
    if not fuse_of then return false end
    if i + #fuse_of - 1 > #nodes then return false end
    for j, fop in ipairs(fuse_of) do
        if nodes[i + j - 1].op ~= fop then return false end
    end
    return true
end

function M.lower(ssa_result)
    local nodes = ssa_result.graph.nodes
    local active = {}
    for _, n in ipairs(nodes) do if not n.removed then active[#active + 1] = n end end

    local cover = {}
    local i = 1
    local hole_idx = 0
    while i <= #active do
        local n = active[i]
        local best = find_cover(n.op)
        if not best then
            return nil, "no stencil for SSA node " .. tostring(n.op)
        end

        -- Try fused stencils
        if best.fuse_of and fuse_match(active, i, best.fuse_of) then
            cover[#cover + 1] = { stencil = best, nodes = {}, holes = {} }
            for j = 1, #best.fuse_of do
                cover[#cover].nodes[j] = active[i + j - 1]
            end
            if best.holes then
                for _, h in ipairs(best.holes) do
                    hole_idx = hole_idx + 1
                    cover[#cover].holes[#cover[#cover].holes + 1] = {
                        name = h, idx = hole_idx, kind = "runtime_hole",
                        desc = h,
                    }
                end
            end
            i = i + #best.fuse_of
        else
            cover[#cover + 1] = { stencil = best, nodes = { n }, holes = {} }
            if best.holes then
                for _, h in ipairs(best.holes) do
                    hole_idx = hole_idx + 1
                    cover[#cover].holes[#cover[#cover].holes + 1] = {
                        name = h, idx = hole_idx, kind = "runtime_hole",
                        desc = h,
                    }
                end
            end
            i = i + 1
        end
    end

    -- Compute template metrics with real sizes if available
    local total_size, total_cost, guard_count, exit_count = 0, 0, 0, 0
    for _, c in ipairs(cover) do
        local sz = c.stencil.real_size or c.stencil.size or 0
        local cy = c.stencil.real_cost or c.stencil.cost or 0
        total_size = total_size + sz
        total_cost = total_cost + cy
        if c.stencil.kind == "guard" then
            guard_count = guard_count + 1
            exit_count = exit_count + 1
        end
    end

    local template = {
        cover = cover,
        total_size = total_size,
        total_cost = total_cost,
        estimated_cycles = total_cost,
        guard_count = guard_count,
        exit_count = exit_count,
        node_count = #active,
        stencil_count = #cover,
        hole_count = hole_idx,
        ssa_stats = ssa_result.stats,
    }
    return template, nil
end

-- ── artifact template generation ─────────────────────────────────────────

function M.lower_active_ops(active_ops)
    -- Build a minimal mock ssa_result for lowering
    local mock = {
        graph = { nodes = {} },
        normal_form = active_ops,
        active_ops = active_ops,
        stats = { guards = 0 },
    }
    for _, op in ipairs(active_ops or {}) do
        mock.graph.nodes[#mock.graph.nodes + 1] = { op = op, removed = false }
    end
    return M.lower(mock)
end

function M.lower_active_ops(active_ops)
    local mock = {
        graph = { nodes = {} },
        normal_form = active_ops,
        active_ops = active_ops,
        stats = { guards = 0 },
    }
    for _, op in ipairs(active_ops or {}) do
        mock.graph.nodes[#mock.graph.nodes + 1] = { op = op, removed = false }
    end
    return M.lower(mock)
end

function M.template_from_active_ops(active_ops, normal_form)
    local mock = {
        graph = { nodes = {} },
        normal_form = normal_form or active_ops,
        active_ops = active_ops,
        stats = { guards = 0 },
        checked_facts = {},
        deps = {},
        projection = { exit_obligations = 0 },
    }
    for _, op in ipairs(active_ops or {}) do
        if op:match("^guard_") then mock.stats.guards = mock.stats.guards + 1 end
        if op == "residual_boundary" then mock.projection.exit_obligations = mock.projection.exit_obligations + 1 end
        mock.graph.nodes[#mock.graph.nodes + 1] = { op = op, removed = false }
    end
    return M.template_from_ssa(mock)
end

function M.template_from_ssa(ssa_result)
    if not tmpl then return nil, err end

    tmpl.normal_form = ssa_result.normal_form
    tmpl.normal_form_hash = ssa_result.normal_form_hash
    tmpl.checked_facts = ssa_result.checked_facts
    tmpl.deps = ssa_result.deps
    tmpl.projection_obligations = ssa_result.projection

    -- Score: cycles saved vs interpreter.
    -- Each SSA active node corresponds to ~1 interpreter-level operation (dispatch ~30cy).
    local interpreter_cost = tmpl.node_count * 30
    tmpl.cycles_saved = math.max(0, interpreter_cost - tmpl.estimated_cycles)
    tmpl.cycles_saved_per_byte = tmpl.cycles_saved / math.max(tmpl.total_size, 1)

    return tmpl, nil
end

-- ── artifact byte generation (stub for real copy-and-patch) ──────────────

function M.emit_bytes(tmpl)
    -- Stub: in the real foundry, this would concatenate GCC-compiled stencil
    -- .o sections and apply relocations for static holes. For now, emit a
    -- descriptive placeholder.
    local parts = {}
    parts[#parts + 1] = string.format("; artifact %s  size=%d cost=%d guards=%d holes=%d",
        table.concat(tmpl.normal_form or {}, "_"), tmpl.total_size, tmpl.estimated_cycles,
        tmpl.guard_count, tmpl.hole_count)
    parts[#parts + 1] = "; stencils:"
    for i, c in ipairs(tmpl.cover or {}) do
        parts[#parts + 1] = string.format(";   %d. %s (%d bytes) covers=%s holes=%s",
            i, c.stencil.name, c.stencil.size, table.concat(c.stencil.covers or {}, ","),
            table.concat((c.stencil.holes or {}), ","))
    end
    return table.concat(parts, "\n")
end

-- ── catalog ──────────────────────────────────────────────────────────────

function M.stencil_names()
    local out = {}
    for _, s in ipairs(STENCILS) do out[#out + 1] = s.name end
    return out
end

function M.stencil_count() return #STENCILS end

return M
