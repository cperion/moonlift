-- Program Profiler: Analyze real Lua programs to extract evidence
-- Profiles bytecode to estimate opcode frequencies and patterns

local M = {}

-- Lua bytecode opcode names (LuaJIT)
local OP_NAMES = {
    [0] = "MOVE",    [1] = "LOADI",   [2] = "LOADF",   [3] = "LOADK",
    [4] = "LOADNIL", [5] = "LOADTRUE",[6] = "LOADFALSE",[7] = "TNEW",
    [8] = "TDUP",    [9] = "GETTABLE",[10] = "GETTABUP",[11] = "GETFIELD",
    [12] = "GETREG", [13] = "SETTABLE",[14] = "SETTABUP",[15] = "SETFIELD",
    [16] = "SETREG", [17] = "SETLIST",[18] = "CALL",   [19] = "CALLMT",
    [20] = "CALLT",  [21] = "ITERC",  [22] = "ITERN",  [23] = "ISNEXT",
    [24] = "RETM",   [25] = "RET",    [26] = "RET0",   [27] = "RET1",
    [28] = "FORI",   [29] = "FORL",   [30] = "FORPREP",[31] = "ITERL",
    [32] = "ITERNEXT",[33] = "LOOP",  [34] = "ILOOP",  [35] = "JLOOP",
    [36] = "JMP",    [37] = "TEST",   [38] = "TESTSET",[39] = "TSETM",
    [40] = "ADD",    [41] = "SUB",    [42] = "MUL",    [43] = "DIV",
    [44] = "MOD",    [45] = "POW",    [46] = "NEG",    [47] = "NOT",
    [48] = "LEN",    [49] = "CONCAT", [50] = "BAND",   [51] = "BOR",
    [52] = "BXOR",   [53] = "BNOT",   [54] = "SHL",    [55] = "SHR",
    [56] = "EQ",     [57] = "LT",     [58] = "LE",     [59] = "NE",
    [60] = "GT",     [61] = "GE",     [62] = "KNIL",   [63] = "KNUM",
    [64] = "KPRI",   [65] = "KSTR",
}

-- Classify opcode by operation type
function M.classify_opcode(op_name)
    if not op_name then return "unknown" end

    local lower = op_name:lower()

    if lower:match("load") or lower:match("move") then
        return "value.load"
    elseif lower:match("get") then
        return "table.get"
    elseif lower:match("set") then
        return "table.set"
    elseif lower:match("call") or lower:match("ret") then
        return "call"
    elseif lower:match("for") or lower:match("loop") or lower:match("jmp") then
        return "control"
    elseif lower:match("add") or lower:match("sub") or lower:match("mul") or
           lower:match("div") or lower:match("mod") or lower:match("pow") then
        return "arith"
    elseif lower:match("eq") or lower:match("lt") or lower:match("le") or
           lower:match("ne") or lower:match("gt") or lower:match("ge") then
        return "compare"
    elseif lower:match("test") or lower:match("not") then
        return "branch"
    else
        return "other"
    end
end

-- Profile a single chunk (Proto) from string source
function M.profile_chunk(chunk_source)
    local stats = {
        name = "chunk",
        opcodes = {},
        opcode_counts = {},
        total_ops = 0,
        class_counts = {},
    }

    -- For now, compile and analyze bytecode structure
    -- In practice, would use debug.getinfo and bytecode inspection

    -- Simple heuristic: count opcode-like patterns in source
    local patterns = {
        load = {count = 0, pattern = "local"},
        get = {count = 0, pattern = "%["},
        set = {count = 0, pattern = " = "},
        call = {count = 0, pattern = "%("},
        control = {count = 0, pattern = "if"},
        arith = {count = 0, pattern = "%+|-|%*|/"},
        compare = {count = 0, pattern = "==|<|>|~="},
    }

    for line in chunk_source:gmatch("[^\n]+") do
        if line:match("%s*local%s+%w+") then patterns.load.count = patterns.load.count + 1 end
        if line:match("%[") then patterns.get.count = patterns.get.count + 1 end
        if line:match("%s*%w+%s*=") then patterns.set.count = patterns.set.count + 1 end
        if line:match("%(") then patterns.call.count = patterns.call.count + 1 end
        if line:match("if%s+") or line:match("while%s+") or line:match("for%s+") then
            patterns.control.count = patterns.control.count + 1
        end
        if line:match("[%+%-*/%^]") then patterns.arith.count = patterns.arith.count + 1 end
        if line:match("==") or line:match("<") or line:match(">") or line:match("~=") then
            patterns.compare.count = patterns.compare.count + 1
        end
    end

    for class, info in pairs(patterns) do
        if info.count > 0 then
            stats.class_counts[class] = info.count
            stats.total_ops = stats.total_ops + info.count
        end
    end

    return stats
end

-- Profile multiple files and aggregate
function M.profile_program(file_paths)
    local program_stats = {
        files = {},
        total_opcodes = {},
        total_count = 0,
        class_distribution = {},
    }

    for _, fpath in ipairs(file_paths) do
        local f = io.open(fpath, "r")
        if f then
            local src = f:read("*a")
            f:close()

            local chunk_stats = M.profile_chunk(src)
            chunk_stats.path = fpath
            table.insert(program_stats.files, chunk_stats)

            for class, count in pairs(chunk_stats.class_counts) do
                program_stats.total_opcodes[class] = (program_stats.total_opcodes[class] or 0) + count
                program_stats.total_count = program_stats.total_count + count
            end
        end
    end

    -- Compute class distribution
    for class, count in pairs(program_stats.total_opcodes) do
        program_stats.class_distribution[class] = count / math.max(1, program_stats.total_count)
    end

    return program_stats
end

-- Estimate opcode motifs from program structure
function M.extract_motifs(stats)
    local motifs = {}

    -- Common patterns based on class distribution
    if stats.class_distribution.load and stats.class_distribution.load > 0.1 then
        table.insert(motifs, {
            pattern = "load.imm",
            frequency = stats.total_opcodes.load or 0,
            ops = {"load"},
            ops_count = 1,
        })
    end

    if stats.class_distribution.get and stats.class_distribution.get > 0.1 then
        table.insert(motifs, {
            pattern = "table.get",
            frequency = stats.total_opcodes.get or 0,
            ops = {"get"},
            ops_count = 1,
        })
    end

    if stats.class_distribution.arith and stats.class_distribution.arith > 0.1 then
        table.insert(motifs, {
            pattern = "arith.add",
            frequency = stats.total_opcodes.arith or 0,
            ops = {"add"},
            ops_count = 1,
        })
    end

    if stats.class_distribution.control and stats.class_distribution.control > 0.1 then
        table.insert(motifs, {
            pattern = "branch",
            frequency = stats.total_opcodes.control or 0,
            ops = {"branch"},
            ops_count = 1,
        })
    end

    if stats.class_distribution.call and stats.class_distribution.call > 0.1 then
        table.insert(motifs, {
            pattern = "call",
            frequency = stats.total_opcodes.call or 0,
            ops = {"call"},
            ops_count = 1,
        })
    end

    -- Multi-op patterns (common in real programs)
    if stats.class_distribution.load and stats.class_distribution.arith then
        table.insert(motifs, {
            pattern = "load.add",
            frequency = math.min(stats.total_opcodes.load or 0, stats.total_opcodes.arith or 0),
            ops = {"load", "add"},
            ops_count = 2,
        })
    end

    if stats.class_distribution.get and stats.class_distribution.arith then
        table.insert(motifs, {
            pattern = "get.add",
            frequency = math.min(stats.total_opcodes.get or 0, stats.total_opcodes.arith or 0),
            ops = {"get", "add"},
            ops_count = 2,
        })
    end

    return motifs
end

-- Report profiling results
function M.report_profile(program_stats, motifs)
    print("\n=== Program Profile ===")
    print(string.format("Files analyzed: %d", #program_stats.files))
    print(string.format("Total operations (estimated): %d", program_stats.total_count))

    print("\nOperation class distribution:")
    local sorted = {}
    for class, count in pairs(program_stats.total_opcodes) do
        local pct = (count / math.max(1, program_stats.total_count)) * 100
        table.insert(sorted, {class = class, count = count, pct = pct})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    for i, item in ipairs(sorted) do
        print(string.format("  %d. %s: %d (%.1f%%)", i, item.class, item.count, item.pct))
    end

    if motifs and #motifs > 0 then
        print("\nIdentified motifs:")
        local sorted_motifs = {}
        for _, m in ipairs(motifs) do
            table.insert(sorted_motifs, m)
        end
        table.sort(sorted_motifs, function(a, b) return a.frequency > b.frequency end)

        for i = 1, math.min(10, #sorted_motifs) do
            local m = sorted_motifs[i]
            print(string.format("  %d. %s (ops=%d, freq=%d)",
                i, m.pattern, m.ops_count, m.frequency))
        end
    end
end

return M
