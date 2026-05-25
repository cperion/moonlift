#!/usr/bin/env luajit
-- Extract evidence from all AWFY programs
-- Aggregates real bytecode patterns across entire test suite

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local analyzer = require("experiments.lua_interpreter_vm.src.jit.bytecode_analyzer")

print("=== Extract All Evidence from AWFY Programs ===\n")

-- Find all .lua files in AWFY test suite
local awfy_dir = "experiments/lua_interpreter_vm/build/awfy_puc_profile/puc_lua_profiled/testes"

local all_files = {}
for file in io.popen("find " .. awfy_dir .. " -name '*.lua' -type f 2>/dev/null"):lines() do
    table.insert(all_files, file)
end

print(string.format("Found %d Lua files in AWFY suite\n", #all_files))

-- Analyze all files
local program = analyzer.analyze_program(all_files)

print(string.format("Successfully analyzed %d files\n", #program.files))

-- Comprehensive report
analyzer.report_analysis(program)

-- Extract all evidence (single-op and sequences)
local evidence = {}

-- Single opcodes
for op, count in pairs(program.total_opcodes) do
    if count > 0 then
        table.insert(evidence, {
            key = op,
            pattern = op,
            hits = count,
            ops = {op:lower()},
            arity = 1,
            class = analyzer.classify_opcode(op),
        })
    end
end

-- Multi-op sequences
for seq, count in pairs(program.sequences) do
    if count >= 2 then
        local ops = {}
        for op in seq:gmatch("[^|]+") do
            table.insert(ops, op:lower())
        end
        table.insert(evidence, {
            key = seq,
            pattern = seq,
            hits = count,
            ops = ops,
            arity = #ops,
            class = ops[1],
        })
    end
end

-- Sort by frequency
table.sort(evidence, function(a, b) return a.hits > b.hits end)

-- Save evidence to file
local output_file = "experiments/lua_interpreter_vm/build/evidence_all_programs.lua"
local out = io.open(output_file, "w")
if out then
    out:write("-- Extracted evidence from all AWFY programs\n")
    out:write("-- Auto-generated: do not edit\n\n")
    out:write("return {\n")

    for i, ev in ipairs(evidence) do
        out:write(string.format('  {\n'))
        out:write(string.format('    key = %q,\n', ev.key))
        out:write(string.format('    pattern = %q,\n', ev.pattern))
        out:write(string.format('    hits = %d,\n', ev.hits))
        out:write(string.format('    arity = %d,\n', ev.arity))
        out:write(string.format('    class = %q,\n', ev.class))
        out:write(string.format('    ops = {%s},\n', table.concat(
            (function() local t = {} for _, op in ipairs(ev.ops) do table.insert(t, string.format("%q", op)) end return t end)(),
            ", ")))
        out:write('  },\n')
        if i >= 100 then  -- limit to top 100 for file size
            out:write('  -- ... more evidence truncated ...\n')
            break
        end
    end

    out:write("}\n")
    out:close()
    print(string.format("\nEvidence saved to %s", output_file))
else
    print("Error: could not write evidence file")
end

-- Summary statistics
print("\n=== Evidence Summary ===")
print(string.format("Total unique patterns: %d", #evidence))
print("Top 20 patterns:")

for i = 1, math.min(20, #evidence) do
    local ev = evidence[i]
    print(string.format("  %2d. %s (arity=%d, hits=%d)", i, ev.pattern, ev.arity, ev.hits))
end
