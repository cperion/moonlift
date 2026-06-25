-- StateOp -> Lalin stencil code generation bootstrap.
-- This is the VM/JIT integration shim used by experiments and tests. The richer
-- harness generator lives in tools/jit_harness/candidate_emit.lua; this module
-- keeps a compact StateOp API for early stencil experiments.

local M = {}

local function sanitize(name)
    name = tostring(name or "stencil"):gsub("[^%w_]", "_")
    if name:match("^%d") then name = "s_" .. name end
    return name
end

local function gen_op(op, holes)
    local kind = op.op or op.kind
    local args = op.args or {}
    if kind == "ConstInt" then
        local name = tostring(args.value or "imm")
        holes[#holes + 1] = { kind = "immediate_i64", name = name }
        return "    return 0\n"
    elseif kind == "ReadSlot" then
        local name = tostring(args.slot or "slot")
        holes[#holes + 1] = { kind = "slot", name = name }
        return "    return 0\n"
    elseif kind == "Jump" then
        holes[#holes + 1] = { kind = "branch_target", name = tostring(args.target or "target") }
        return "    return 0\n"
    end
    return "    return 0\n"
end

function M.generate_function(candidate)
    if not candidate then return nil, "candidate required" end
    local name = sanitize(candidate.name or candidate.id)
    local holes = {}
    local src = {}
    src[#src + 1] = "-- generated StateOp stencil: " .. name
    src[#src + 1] = "func " .. name .. "(): i64"
    local emitted_return = false
    for _, op in ipairs(candidate.ops or {}) do
        local chunk = gen_op(op, holes)
        src[#src + 1] = chunk:gsub("\n$", "")
        if chunk:find("return", 1, true) then emitted_return = true; break end
    end
    if not emitted_return then src[#src + 1] = "    return 0" end
    src[#src + 1] = "end"
    return { id = candidate.id, name = name, source = table.concat(src, "\n") .. "\n", holes = holes }
end

function M.generate_module(candidates)
    local generated, chunks = {}, {}
    for _, cand in ipairs(candidates or {}) do
        local fn, err = M.generate_function(cand)
        if not fn then return nil, err end
        generated[#generated + 1] = fn
        chunks[#chunks + 1] = fn.source
    end
    return { source = table.concat(chunks, "\n"), generated = generated }
end

return M
