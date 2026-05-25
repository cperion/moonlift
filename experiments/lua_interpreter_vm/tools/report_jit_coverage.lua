package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local coverage = require("experiments.lua_interpreter_vm.src.jit.coverage")

local profile_dir = arg[1] or "experiments/lua_interpreter_vm/build/awfy_puc_profile"
local hist_path = profile_dir .. "/aggregate_opcode_hist.tsv"
local pairs_path = profile_dir .. "/aggregate_pairs.tsv"
local out_path = arg[2] or (profile_dir .. "/JIT_COVERAGE_REPORT.md")

local function write_all(path, s)
    local f = assert(io.open(path, "wb"), path)
    f:write(s)
    f:close()
end

local function fmt_pct(x) return string.format("%.2f%%", x) end
local function fmt_n(x) return string.format("%d", x or 0) end

local a = coverage.analyze(hist_path, pairs_path)
local lines = {}

lines[#lines + 1] = "# JIT Coverage Report"
lines[#lines + 1] = ""
lines[#lines + 1] = "Dynamic coverage over the AWFY/PUC Lua opcode profile."
lines[#lines + 1] = ""
lines[#lines + 1] = "This answers the speed question's missing half: native blocks are fast when entered, but coverage determines how often real code can stay there."
lines[#lines + 1] = ""

lines[#lines + 1] = "## Opcode coverage sets"
lines[#lines + 1] = ""
lines[#lines + 1] = "| set | covered ops | dynamic count | coverage | pair-both coverage |"
lines[#lines + 1] = "|---|---:|---:|---:|---:|"
for _, name in ipairs(coverage.set_order) do
    local s = a.sets[name]
    local nops = 0
    for _ in pairs(coverage.sets[name]) do nops = nops + 1 end
    local pair = a.pair_sets[name]
    lines[#lines + 1] = string.format("| `%s` | %d | %s / %s | %s | %s |", name, nops, fmt_n(s.covered), fmt_n(s.total), fmt_pct(s.percent), fmt_pct(pair.both_percent))
end
lines[#lines + 1] = ""

lines[#lines + 1] = "## What current baseline covers"
lines[#lines + 1] = ""
lines[#lines + 1] = "Current executable baseline planner support:"
lines[#lines + 1] = ""
lines[#lines + 1] = "```text"
local current_ops = {}
for op in pairs(coverage.sets.current) do current_ops[#current_ops + 1] = op end
table.sort(current_ops)
for _, op in ipairs(current_ops) do lines[#lines + 1] = op end
lines[#lines + 1] = "```"
lines[#lines + 1] = ""
local cur = a.sets.current
lines[#lines + 1] = string.format("Current dynamic opcode coverage: **%s** (%s / %s).", fmt_pct(cur.percent), fmt_n(cur.covered), fmt_n(cur.total))
lines[#lines + 1] = ""

lines[#lines + 1] = "## Biggest missing opcodes"
lines[#lines + 1] = ""
lines[#lines + 1] = "| opcode | count | share |"
lines[#lines + 1] = "|---|---:|---:|"
for i = 1, math.min(20, #cur.unsupported) do
    local r = cur.unsupported[i]
    lines[#lines + 1] = string.format("| `%s` | %s | %s |", r.name, fmt_n(r.count), fmt_pct(r.count * 100 / cur.total))
end
lines[#lines + 1] = ""

lines[#lines + 1] = "## Incremental coverage gains"
lines[#lines + 1] = ""
lines[#lines + 1] = "| transition | gained dynamic count | gained coverage | top gained ops |"
lines[#lines + 1] = "|---|---:|---:|---|"
for _, key in ipairs { "current->cheap_next", "cheap_next->control_loop", "control_loop->object1" } do
    local d = a.deltas[key]
    local tops = {}
    for i = 1, math.min(8, #d.ops) do tops[#tops + 1] = d.ops[i].name end
    lines[#lines + 1] = string.format("| `%s` | %s | %s | %s |", key, fmt_n(d.gained), fmt_pct(d.percent), table.concat(tops, ", "))
end
lines[#lines + 1] = ""

lines[#lines + 1] = "## Top pair misses under current baseline"
lines[#lines + 1] = ""
lines[#lines + 1] = "| pair | count | both supported? |"
lines[#lines + 1] = "|---|---:|---:|"
local pair_misses = a.pair_sets.current.unsupported_pairs
for i = 1, math.min(20, #pair_misses) do
    local r = pair_misses[i]
    local both = coverage.sets.current[r.name1] and coverage.sets.current[r.name2]
    lines[#lines + 1] = string.format("| `%s %s` | %s | %s |", r.name1, r.name2, fmt_n(r.count), both and "yes" or "no")
end
lines[#lines + 1] = ""

lines[#lines + 1] = "## Interpretation"
lines[#lines + 1] = ""
lines[#lines + 1] = "The current backend is fast on covered numeric/control blocks, but AWFY coverage is only the first slice. Cheap scalar/control additions move coverage a little; the large jump comes from object/table/call-adjacent work, especially GETFIELD, SETFIELD, SELF, GETTABLE, SETTABLE, and GETUPVAL."
lines[#lines + 1] = ""
lines[#lines + 1] = "The next speed question is therefore not whether LOADI/ADD/MOVE are fast enough; they are. The next question is how quickly the stencil library can cover the dominant object/table/call motifs without losing the explicit outcome/projection discipline."
lines[#lines + 1] = ""

write_all(out_path, table.concat(lines, "\n"))
print("wrote " .. out_path)
print(string.format("current coverage: %s", fmt_pct(cur.percent)))
print(string.format("object1 coverage: %s", fmt_pct(a.sets.object1.percent)))
