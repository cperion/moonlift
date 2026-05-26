-- puc_bytecode.lua
-- Static PUC Lua bytecode operand/liveness-ish fact extraction.

local M = {}
local util = require("tools.jit_harness.util")
local FactSchema = require("tools.jit_harness.fact_schema")

local function find_lua_root(repo_root, awfy_root)
    local candidates = {
        awfy_root,
        repo_root and (repo_root .. "/.vendor/Lua"),
        ".vendor/Lua",
    }
    for _, p in ipairs(candidates) do
        if p and util.path_exists(p .. "/liblua.a") and util.path_exists(p .. "/lopcodes.h") then
            return p
        end
    end
    return nil
end

local function build_tool(config, name, source_file)
    config = config or {}
    local repo_root = util.abspath(config.repo_root or util.find_repo_root(".") or ".")
    local lua_root = util.abspath(find_lua_root(repo_root, config.lua_root or config.awfy_root) or (repo_root .. "/.vendor/Lua"))
    local out = config[name .. "_path"] or config.tool_path or (repo_root .. "/experiments/lua_interpreter_vm/build/tools/" .. name)
    if util.path_exists(out) then return out end
    util.mkdir_p(util.dirname(out))
    local src = repo_root .. "/experiments/lua_interpreter_vm/tools/jit_harness/" .. source_file
    local cmd = string.format("cc -I%s %s %s -lm -ldl -o %s",
        util.shell_quote(lua_root), util.shell_quote(src), util.shell_quote(lua_root .. "/liblua.a"), util.shell_quote(out))
    local ok, text = util.run_capture(cmd)
    if not ok then return nil, text end
    return out
end

function M.ensure_dump_tool(config)
    return build_tool(config, "puc_proto_dump", "puc_proto_dump.c")
end

function M.ensure_trace_tool(config)
    return build_tool(config, "puc_trace_operands", "puc_trace_operands.c")
end

local function read_dump(path)
    local rows = {}
    local text = util.read_file(path)
    if not text then return rows end
    local header = true
    for line in text:gmatch("[^\n]+") do
        if header then header = false else
            local c = {}
            for col in (line .. "\t"):gmatch("([^\t]*)\t") do c[#c+1] = col end
            if #c >= 13 then
                rows[#rows+1] = {
                    proto = c[1], depth = tonumber(c[2]), pc = tonumber(c[3]), opcode = tonumber(c[4]), name = c[5],
                    a = tonumber(c[6]), b = tonumber(c[7]), c = tonumber(c[8]), k = tonumber(c[9]),
                    bx = tonumber(c[10]), sbx = tonumber(c[11]), ax = tonumber(c[12]), word = tonumber(c[13]),
                }
            end
        end
    end
    return rows
end

function M.dump_file(path, config)
    local tool, err = M.ensure_dump_tool(config)
    if not tool then return nil, err end
    local cmd = util.shell_quote(tool) .. " " .. util.shell_quote(path)
    local ok, out = util.run_capture(cmd)
    if not ok then return nil, out end
    local tmp = os.tmpname()
    util.write_file(tmp, out)
    local rows = read_dump(tmp)
    os.remove(tmp)
    return rows
end

local function op_key(a, b)
    return a.name .. "|" .. b.name
end

local function fact_key_for_rewrite(kind, ops)
    if kind == "move_move_forward" then
        return "MOVE:move_def;MOVE:move_uses_previous_def"
    elseif kind == "move_move_empty" then
        return "MOVE:redundant_move;MOVE:redundant_move"
    elseif kind == "load_move_final_dst" then
        return ops[1] .. ":load_def;MOVE:move_uses_previous_def"
    elseif kind == "op_move_final_dst" then
        return ops[1] .. ":i64;MOVE:move_uses_previous_def"
    elseif kind == "op_return1" then
        return ops[1] .. ":i64;RETURN1:returns_previous_def"
    end
end

local pure_arith = { ADD=true, SUB=true, MUL=true, ADDI=true }
local pure_load = { LOADI=true, LOADF=true, LOADK=true }

local function classify_pair(a, b)
    local ops = { a.name, b.name }
    if a.name == "MOVE" and b.name == "MOVE" then
        if a.a == a.b and b.a == b.b then return "move_move_empty", ops end
        if a.a == b.b then return "move_move_forward", ops end
    end
    if pure_load[a.name] and b.name == "MOVE" and a.a == b.b then
        return "load_move_final_dst", ops
    end
    if pure_arith[a.name] and b.name == "MOVE" and a.a == b.b then
        return "op_move_final_dst", ops
    end
    if pure_arith[a.name] and b.name == "RETURN1" and a.a == b.a then
        return "op_return1", ops
    end
    return nil, ops
end

local function parse_rows_text(text)
    local rows = {}
    if not text then return rows end
    local header = true
    for line in text:gmatch("[^\n]+") do
        if header then header = false else
            local c = {}
            for col in (line .. "\t"):gmatch("([^\t]*)\t") do c[#c+1] = col end
            if #c >= 13 then
                rows[#rows+1] = {
                    seq = tonumber(c[1]), proto = c[2], pc = tonumber(c[3]), opcode = tonumber(c[4]), name = c[5],
                    a = tonumber(c[6]), b = tonumber(c[7]), c = tonumber(c[8]), k = tonumber(c[9]),
                    bx = tonumber(c[10]), sbx = tonumber(c[11]), ax = tonumber(c[12]), word = tonumber(c[13]),
                }
            end
        end
    end
    return rows
end

function M.trace_file(path, output_path, config)
    config = config or {}
    local tool, err = M.ensure_trace_tool(config)
    if not tool then return nil, err end
    local limit = tonumber(config.trace_limit or 100000) or 100000
    if output_path then util.mkdir_p(util.dirname(output_path)) end
    local parts = { util.shell_quote(tool), util.shell_quote(path), tostring(limit) }
    if output_path then parts[#parts + 1] = util.shell_quote(output_path) end
    local cmd = table.concat(parts, " ")
    if config.timeout_seconds then
        cmd = "timeout " .. tostring(tonumber(config.timeout_seconds) or 5) .. "s " .. cmd
    end
    if output_path == nil then
        local ok, out = util.run_capture(cmd)
        local rows = parse_rows_text(out)
        if #rows > 0 then return rows, out end
        if not ok then return nil, out end
        return rows, out
    end
    local ok, out = util.run_capture(cmd)
    if util.path_exists(output_path) then
        local rows = parse_rows_text(util.read_file(output_path))
        if #rows > 0 then return rows, out end
    end
    if not ok then return nil, out end
    return {}, out
end

local function accumulate_rewrite_facts_from_rows(rows, result, use_dynamic)
    for i = 1, #rows - 1 do
        local a, b = rows[i], rows[i + 1]
        if a.proto == b.proto and a.pc + 1 == b.pc then
            local key = op_key(a, b)
            if use_dynamic then
                result.dynamic_window_counts[key] = (result.dynamic_window_counts[key] or 0) + 1
            else
                result.static_window_counts[key] = (result.static_window_counts[key] or 0) + 1
            end
            local rkind, ops = classify_pair(a, b)
            if rkind then
                local fk = fact_key_for_rewrite(rkind, ops)
                local full = key .. " @ " .. fk
                local target = use_dynamic and result.rewrite_fact_counts or result.rewrite_fact_static_counts
                target[full] = (target[full] or 0) + 1
                result.operand_shape_counts[full] = (result.operand_shape_counts[full] or 0) + 1
            end
        end
    end
end

function M.profile_dynamic_files(files, config)
    config = config or {}
    local result = {
        files = 0,
        instructions = 0,
        dynamic_window_counts = {},
        operand_shape_counts = {},
        rewrite_fact_counts = {},
        rejects = {},
        trace_dir = config.trace_dir,
    }
    if config.trace_dir then util.mkdir_p(config.trace_dir) end
    local processed = 0
    local include = config.include
    print(string.format("[puc-dyn] tracing operands for up to %d/%d files", tonumber(config.max_files or #(files or {})), #(files or {})))
    for idx, file in ipairs(files or {}) do
        if config.max_files and processed >= config.max_files then break end
        local path = file.path or file
        if include and not tostring(path):find(include, 1, true) then
            -- skip
        else
            print(string.format("[puc-dyn] %d/%d %s", idx, #(files or {}), tostring(path)))
            local out = config.trace_dir and (config.trace_dir .. "/" .. util.basename(path):gsub("%.lua$", "") .. ".trace_operands.tsv") or nil
            local rows, err = M.trace_file(path, out, config)
            if not rows then
                print("[puc-dyn] reject: " .. tostring(err):sub(1, 160))
                result.rejects[#result.rejects+1] = { path = path, error = err }
            else
                processed = processed + 1
                result.files = result.files + 1
                result.instructions = result.instructions + #rows
                print(string.format("[puc-dyn] traced %d instructions", #rows))
                accumulate_rewrite_facts_from_rows(rows, result, true)
            end
        end
    end
    return result
end

function M.profile_files(files, config, dynamic_profile)
    config = config or {}
    local result = {
        files = 0,
        protos = 0,
        instructions = 0,
        static_window_counts = {},
        operand_shape_counts = {},
        rewrite_fact_counts = {},
        rewrite_fact_static_counts = {},
        rejects = {},
    }

    print(string.format("[puc-static] dumping operands for %d files", #(files or {})))
    for idx, file in ipairs(files or {}) do
        local fpath = file.path or file
        if idx == 1 or idx % 5 == 0 or idx == #(files or {}) then
            print(string.format("[puc-static] %d/%d %s", idx, #(files or {}), tostring(fpath)))
        end
        local rows, err = M.dump_file(fpath, config)
        if not rows then
            print("[puc-static] reject: " .. tostring(err):sub(1, 160))
            result.rejects[#result.rejects+1] = { path = fpath, error = err }
        else
            result.files = result.files + 1
            result.instructions = result.instructions + #rows
            local by_proto = {}
            for _, ins in ipairs(rows) do
                by_proto[ins.proto] = by_proto[ins.proto] or {}
                table.insert(by_proto[ins.proto], ins)
            end
            for _, proto_rows in pairs(by_proto) do
                result.protos = result.protos + 1
                table.sort(proto_rows, function(a, b) return a.pc < b.pc end)
                for i = 1, #proto_rows - 1 do
                    local a, b = proto_rows[i], proto_rows[i+1]
                    if a.pc + 1 == b.pc then
                        local key = op_key(a, b)
                        result.static_window_counts[key] = (result.static_window_counts[key] or 0) + 1
                        local rkind, ops = classify_pair(a, b)
                        if rkind then
                            local fk = fact_key_for_rewrite(rkind, ops)
                            local full = key .. " @ " .. fk
                            result.rewrite_fact_static_counts[full] = (result.rewrite_fact_static_counts[full] or 0) + 1
                            result.operand_shape_counts[full] = (result.operand_shape_counts[full] or 0) + 1
                        end
                    end
                end
            end
        end
    end

    -- Convert static observed operand facts into dynamic estimates when an
    -- aggregate dynamic profile is available.
    for full, static_count in pairs(result.rewrite_fact_static_counts) do
        local pattern = full:match("^(.-) @ ") or full
        local static_total = result.static_window_counts[pattern] or static_count
        local dyn_total = dynamic_profile and dynamic_profile.window_counts and dynamic_profile.window_counts[pattern] or static_total
        local estimate = math.floor((dyn_total * static_count / math.max(1, static_total)) + 0.5)
        result.rewrite_fact_counts[full] = estimate
    end

    return result
end

return M
