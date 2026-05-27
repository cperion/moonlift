-- loader.lua
-- Convert existing bytecode/window profiles into SponJIT shadow workloads.
-- This is intentionally approximate: aggregate bytecode profiles do not contain
-- full dynamic facts, so this loader creates sensitivity workloads from real
-- opcode windows plus configurable fact assumptions.

local Util = require("src.util")

local M = {}

local function split_ops(key)
    local ops = {}
    for op in tostring(key or ""):gmatch("[^|]+") do ops[#ops + 1] = op end
    return ops
end

local function fact_profile_level(mode)
    if mode == "none" or mode == "pessimistic" then return 0 end
    if mode == "conservative" then return 1 end
    if mode == "optimistic" then return 3 end
    return 2 -- balanced
end

function M.infer_observed(op, prev_op, next_op, mode)
    local level = fact_profile_level(mode)
    local f = {}
    local function add(x) f[#f + 1] = x end
    if level == 0 then return f end

    if op == "ADD" or op == "SUB" or op == "MUL" then
        add("lhs_i64"); add("rhs_i64")
        if prev_op == "GETTABLE" then add("lhs_from_prev") end
    elseif op == "ADDI" then
        add("lhs_i64")
    elseif op == "LT" or op == "LE" or op == "EQ" or op == "EQK" then
        add("lhs_i64"); add("rhs_i64")
    elseif op == "EQI" or op == "LTI" or op == "LEI" or op == "GTI" or op == "GEI" then
        add("lhs_i64")
    elseif op == "RETURN1" then
        if prev_op == "ADD" or prev_op == "SUB" or prev_op == "MUL" or prev_op == "GETTABLE" then add("returns_prev") end
    elseif op == "JMP" then
        if prev_op == "TEST" or prev_op == "LT" or prev_op == "LE" or prev_op == "EQ" or prev_op == "EQK" then add("branch_consumes_prev") end
        add("loop_backedge")
    elseif op == "TEST" then
        add("truthy_stable")
    elseif op == "GETTABLE" or op == "GETI" then
        add("table")
        if level >= 2 then add("key_i64"); add("array_hit"); add("metatable_absent") end
        if level >= 3 then add("result_i64") end
    elseif op == "GETFIELD" or op == "GETTABUP" or op == "SELF" then
        add("table"); add("key_const")
        if level >= 2 then add("shape_known"); add("metatable_absent") end
        if (next_op == "CALL" or next_op == "TAILCALL") and level >= 2 then add("result_known_call") end
    elseif op == "SETTABLE" then
        add("table")
        if level >= 2 then add("key_i64"); add("metatable_absent"); add("barrier_clean") end
    elseif op == "SETFIELD" then
        add("table"); add("key_const")
        if level >= 2 then add("shape_known"); add("metatable_absent"); add("barrier_clean") end
    elseif op == "CALL" or op == "TAILCALL" then
        if level >= 2 then add("known_call_target") end
        if prev_op == "GETFIELD" or prev_op == "GETTABUP" or prev_op == "SELF" then add("callee_from_prev") end
    elseif op == "FORLOOP" or op == "FORPREP" then
        if level >= 1 then add("loop_i64") end
    end
    return f
end

function M.events_from_ops(ops, count, config)
    config = config or {}
    local events = {}
    for i, op in ipairs(ops or {}) do
        events[#events + 1] = {
            op = op,
            freq = count or 1,
            observed = M.infer_observed(op, ops[i - 1], ops[i + 1], config.fact_mode),
        }
    end
    return events
end

local function op_of_event(e) return type(e) == "table" and (e.op or e.name) or tostring(e) end

local function enrich_events(events, count, config)
    local out = {}
    for i, ev in ipairs(events or {}) do
        local e = {}
        if type(ev) == "table" then for k, v in pairs(ev) do e[k] = v end else e.op = tostring(ev) end
        e.op = op_of_event(e)
        e.freq = e.freq or count or 1
        e.observed = e.observed or M.infer_observed(e.op, op_of_event(events[i - 1]), op_of_event(events[i + 1]), config and config.fact_mode)
        out[#out + 1] = e
    end
    return out
end

local function sorted_entries(map, max_len)
    local xs = {}
    for key, count in pairs(map or {}) do
        local ops, events, n, c
        if type(count) == "table" then
            events = count.events
            ops = {}
            for _, e in ipairs(events or {}) do ops[#ops + 1] = op_of_event(e) end
            n = #ops
            c = tonumber(count.count) or 0
        else
            ops = split_ops(key)
            n = #ops
            c = tonumber(count) or 0
        end
        if n > 0 and (not max_len or n <= max_len) then
            xs[#xs + 1] = { key = key, ops = ops, events = events, count = c }
        end
    end
    table.sort(xs, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return #a.ops > #b.ops
    end)
    return xs
end

function M.workloads_from_profile(profile, config)
    config = config or {}
    local max_regions = tonumber(config.max_regions or 20) or 20
    local max_len = tonumber(config.max_len or config.max_window or 8) or 8
    local min_len = tonumber(config.min_len or 2) or 2
    local entries = {}

    for _, e in ipairs(sorted_entries(profile and profile.static_operand_windows, max_len)) do
        if #e.ops >= min_len then entries[#entries + 1] = e end
    end
    for _, e in ipairs(sorted_entries(profile and profile.motif_counts, max_len)) do
        if #e.ops >= min_len then entries[#entries + 1] = e end
    end
    for _, e in ipairs(sorted_entries((profile and (profile.window_counts or profile.static_window_counts or profile.dynamic_window_counts)), max_len)) do
        if #e.ops >= min_len then entries[#entries + 1] = e end
    end

    local seen, out = {}, {}
    for _, e in ipairs(entries) do
        if #out >= max_regions then break end
        if not seen[e.key] then
            seen[e.key] = true
            out[#out + 1] = {
                name = "profile_region_" .. tostring(#out + 1),
                description = string.format("profile window count=%s key=%s", tostring(e.count), e.key),
                source_key = e.key,
                profile_count = e.count,
                events = e.events and enrich_events(e.events, e.count, config) or M.events_from_ops(e.ops, e.count, config),
            }
        end
    end
    return out
end

function M.load_profile(path)
    return assert(Util.read_json(path))
end

function M.load_awfy_profile(root)
    local awfy = require("src.awfy")
    local profile_root = awfy.find_puc_profile_root(root or ".")
    local profile, err = awfy.load_puc_static_profile(profile_root)
    if not profile then error(err or "could not load AWFY profile") end
    return profile
end

function M.scan_lua_files(root, config)
    config = config or {}
    root = root or "."
    local max_files = tonumber(config.max_files or 200) or 200
    local include = config.include
    local exclude = config.exclude
    local files = {}
    local cmd = "find " .. Util.shell_quote(root) .. " -type f -name '*.lua' | sort"
    local p = io.popen(cmd, "r")
    if not p then return files end
    for line in p:lines() do
        local ok = true
        if include and not line:find(include, 1, true) then ok = false end
        if exclude and line:find(exclude, 1, true) then ok = false end
        if ok then
            files[#files + 1] = { path = line }
            if #files >= max_files then break end
        end
    end
    p:close()
    return files
end

function M.profile_lua_root(root, config)
    config = config or {}
    local puc = require("src.puc_bytecode")
    local files = M.scan_lua_files(root, config)
    return puc.profile_files(files, config), files
end

function M.workloads_from_trace_rows(rows, config)
    config = config or {}
    local max_regions = tonumber(config.max_regions or 20) or 20
    local max_len = tonumber(config.max_len or 8) or 8
    local out, cur = {}, {}
    local last_seq = nil
    for _, r in ipairs(rows or {}) do
        if last_seq and r.seq and r.seq ~= last_seq + 1 then cur = {} end
        cur[#cur + 1] = r.name or r.op
        if #cur >= max_len then
            out[#out + 1] = {
                name = "trace_region_" .. tostring(#out + 1),
                description = "dynamic trace slice",
                events = M.events_from_ops(cur, 1, config),
            }
            cur = {}
            if #out >= max_regions then break end
        end
        last_seq = r.seq
    end
    return out
end

return M
