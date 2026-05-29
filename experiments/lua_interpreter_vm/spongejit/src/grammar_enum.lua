-- grammar_enum.lua — Complete PUC Lua bytecode grammar enumeration
--
-- Generates ALL grammatically-valid opcode sequences up to arity 4.
-- Every PUC Lua 5.4 opcode is included, grouped by operand layout.

local Util = require("src.util")
local SSA = require("src.ssa")
local Facts = require("src.facts")
local FactAxes = require("src.ssa_fact_axes")

local M = {}

-- Slot tracker: register allocation for data-flow consistency
local function SlotTracker()
    return setmetatable({
        next_slot = 0, written = {}, read_only = {},
    }, { __index = {
        alloc = function(self, n)
            local s = self.next_slot
            self.next_slot = self.next_slot + (n or 1)
            self.written[tostring(s)] = true
            return s
        end,
        read = function(self, _)
            for s, _ in pairs(self.written) do return tonumber(s) end
            local s = self.next_slot
            self.next_slot = self.next_slot + 1
            self.read_only[tostring(s)] = true
            return s
        end,
        clone = function(self)
            local c = SlotTracker()
            c.next_slot = self.next_slot
            for k, v in pairs(self.written) do c.written[k] = v end
            for k, v in pairs(self.read_only) do c.read_only[k] = v end
            return c
        end,
    }})
end

-- Opcode categories — every PUC Lua 5.4 opcode, grouped by operand pattern.
--   name:   category label
--   reps:   concrete opcode names in this category
--   is_terminal: true for branch/jump/return
--   gen:    function(seq_id, pos, slots, rep_name) -> {op=..., a=..., b=..., c=...}

local CATEGORIES = {}

-- Helper: register write + one register read
local function cat1w1r(name, reps, gen_extra)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=false,
        gen = function(_, _, slots, r)
            local src = slots:read(1)
            local dst = slots:alloc(1)
            local ev = {op=r, a=dst, b=src}
            if gen_extra then gen_extra(ev, slots) end
            return ev
        end}
end

-- Helper: register write + two register reads
local function cat1w2r(name, reps)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=false,
        gen = function(_, _, slots, r)
            return {op=r, a=slots:alloc(1), b=slots:read(1), c=slots:read(1)}
        end}
end

-- Helper: register write only (immediate/constant)
local function cat1w(name, reps, gen_extra)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=false,
        gen = function(_, _, slots, r)
            local ev = {op=r, a=slots:alloc(1)}
            if gen_extra then gen_extra(ev, slots) end
            return ev
        end}
end

-- Helper: register write + one register read + immediate
local function cat1w1r_imm(name, reps)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=false,
        gen = function(_, _, slots, r)
            return {op=r, a=slots:alloc(1), b=slots:read(1), c=5}
        end}
end

-- Helper: register write + two register reads + immediate
local function cat1w2r_k(name, reps)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=false,
        gen = function(_, _, slots, r)
            return {op=r, a=slots:alloc(1), b=slots:read(1), c=slots:read(1), k=0}
        end}
end

-- Helper: table write (reg, key, value)
local function cat_table_set(name, reps)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=false,
        gen = function(_, _, slots, r)
            local tbl = slots:read(1)
            local key = slots:read(1)
            local val = slots:read(1)
            return {op=r, a=tbl, b=key, c=val}
        end}
end

-- Helper: CALL-like (not a terminator but has complex register effects)
local function cat_call(name, reps)
    CATEGORIES[#CATEGORIES + 1] = {name=name, reps=reps, is_terminal=true,
        gen = function(_, _, slots, r)
            local fn = slots:read(1)
            return {op=r, a=fn, b=0, c=0}
        end}
end

-- ── Continuers (can appear at any position) ──────────────────────────

-- LOAD immediate
cat1w("LOADI",   {"LOADI"},   function(ev) ev.sbx = 42 end)
cat1w("LOADF",   {"LOADF"},   function(ev) ev.sbx = 42 end)
cat1w("LOADK",   {"LOADK"},   function(ev) ev.bx = 0 end)

-- LOAD boolean/nil
cat1w("LOADTRUE",  {"LOADTRUE","LFALSESKIP"})
cat1w("LOADFALSE", {"LOADFALSE"})
cat1w("LOADNIL",   {"LOADNIL"})

-- MOVE
cat1w1r("MOVE", {"MOVE"})

-- Upvalue load/store (reads/writes upvalues, not register-to-register)
cat1w("GETUPVAL",  {"GETUPVAL"}, function(ev,slots) ev.b = 0 end)
CATEGORIES[#CATEGORIES+1] = {name="SETUPVAL", reps={"SETUPVAL"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:read(1), b=0} end}

-- Binary ops: RA = RB op RC
cat1w2r("ADD", {"ADD","SUB","MUL","DIV","MOD","POW","IDIV"})
cat1w2r("BAND", {"BAND","BOR","BXOR","SHL","SHR"})

-- Binary ops with immediate: RA = RB op sC
cat1w1r_imm("ADDI", {"ADDI"})
cat1w1r_imm("SHLI", {"SHLI","SHRI"})

-- Binary ops with constant key: RA = RB op K[C]
cat1w2r_k("ADDK", {"ADDK","SUBK","MULK","MODK","POWK","DIVK","IDIVK"})
cat1w2r_k("BANDK", {"BANDK","BORK","BXORK"})

-- Unary: RA = op(RB)
cat1w1r("UNM", {"UNM","BNOT","NOT","LEN"})

-- Comparison: Lua 5.5 A B k format (no A_out, synthetic dest)
CATEGORIES[#CATEGORIES+1] = {name="EQ", reps={"EQ","LT","LE"}, is_terminal=false,
    gen = function(_,_,slots,r) 
        local ra = slots:read(1)  -- register A
        local rb = slots:read(1)  -- register B
        local res = slots:alloc(1) -- synthetic dest
        return {op=r, a=ra, b=rb, dest=res, k=0}
    end}

-- Comparison with constant key (Lua 5.5: A B k)
CATEGORIES[#CATEGORIES+1] = {name="EQK", reps={"EQK"}, is_terminal=false,
    gen = function(_,_,slots,r) 
        local ra = slots:read(1)  -- register A
        return {op=r, a=ra, bx=0, k=0}
    end}

-- Comparison with immediate (Lua 5.5: A sB k — A=reg, sB=imm, no A_out)
CATEGORIES[#CATEGORIES+1] = {name="EQI", reps={"EQI","LTI","LEI","GTI","GEI"}, is_terminal=false,
    gen = function(_,_,slots,r)
        local ra = slots:read(1)  -- A is the register
        local res = slots:alloc(1) -- synthetic dest (comparison produces 0/1)
        return {op=r, a=ra, sb=5, dest=res, k=0}
    end}

-- TEST / TESTSET
cat1w1r("TEST",    {"TEST"},    function(ev,slots) ev.c = 0 end)
cat1w1r("TESTSET", {"TESTSET"}, function(ev,slots) ev.c = 0 end)

-- Table read: RA = table[RB]
CATEGORIES[#CATEGORIES+1] = {name="GETTABLE", reps={"GETTABLE","GETI"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:alloc(1), b=slots:read(1), c=slots:read(1)} end}
cat1w1r("GETFIELD", {"GETFIELD","GETTABUP"})
cat1w1r("SELF", {"SELF"}, function(ev,slots) ev.c = slots:read(1) end)

-- Table write: RA[RB] = RC
cat_table_set("SETTABLE", {"SETTABLE","SETI"})
CATEGORIES[#CATEGORIES+1] = {name="SETFIELD", reps={"SETFIELD"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:read(1), b=slots:read(1), c=0} end}
CATEGORIES[#CATEGORIES+1] = {name="SETTABUP", reps={"SETTABUP"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=0, b=slots:read(1), c=slots:read(1)} end}

-- NEWTABLE
CATEGORIES[#CATEGORIES+1] = {name="NEWTABLE", reps={"NEWTABLE"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:alloc(1), b=0, c=0} end}

-- CONCAT: RA = concat(RB..RC)
cat1w2r("CONCAT", {"CONCAT"})

-- CLOSURE
cat1w("CLOSURE", {"CLOSURE"}, function(ev) ev.bx = 0 end)

-- VARARG
cat1w("VARARG", {"VARARG"}, function(ev,slots) ev.b = 2 end)

-- SETLIST
CATEGORIES[#CATEGORIES+1] = {name="SETLIST", reps={"SETLIST"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:read(1), b=0, c=0} end}

-- MMBIN / MMBINI / MMBINK (metamethod binary operations)
cat1w2r("MMBIN",   {"MMBIN"})
cat1w1r_imm("MMBINI", {"MMBINI"})
cat1w("MMBINK", {"MMBINK"}, function(ev,slots) ev.b = slots:read(1) end)

-- CLOSE / TBC (close upvalues)
CATEGORIES[#CATEGORIES+1] = {name="CLOSE", reps={"CLOSE"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:read(1)} end}
CATEGORIES[#CATEGORIES+1] = {name="TBC", reps={"TBC"}, is_terminal=false,
    gen = function(_,_,slots,r) return {op=r, a=slots:read(1)} end}

-- LOADKX (extra large constant)
cat1w("LOADKX", {"LOADKX"}, function(ev) ev.ax = 0 end)

-- FORPREP / TFORPREP (branch, but target is reachable as continuer)
CATEGORIES[#CATEGORIES+1] = {name="FORPREP", reps={"FORPREP"}, is_terminal=false,
    gen = function(_,_,slots,r) local v=slots:read(1); return {op=r, a=v, sbx=3} end}
CATEGORIES[#CATEGORIES+1] = {name="TFORPREP", reps={"TFORPREP"}, is_terminal=false,
    gen = function(_,_,slots,r) local v=slots:read(1); return {op=r, a=v, sbx=3} end}

-- ── Terminators (last position only) ─────────────────────────────────

-- JMP (isJ format — 25-bit signed offset, not sBx!)
CATEGORIES[#CATEGORIES+1] = {name="JMP", reps={"JMP"}, is_terminal=true,
    gen = function(_,_,_,_) return {op="JMP", sj=-1} end}

-- RETURN
CATEGORIES[#CATEGORIES+1] = {name="RETURN0", reps={"RETURN0"}, is_terminal=true,
    gen = function(_,_,_,_) return {op="RETURN0"} end}
CATEGORIES[#CATEGORIES+1] = {name="RETURN1", reps={"RETURN1"}, is_terminal=true,
    gen = function(_,_,slots,_) return {op="RETURN1", a=slots:read(1)} end}
CATEGORIES[#CATEGORIES+1] = {name="RETURN", reps={"RETURN"}, is_terminal=true,
    gen = function(_,_,slots,_) return {op="RETURN", a=slots:read(1)} end}

-- CALL / TAILCALL
cat_call("CALL",     {"CALL"})
cat_call("TAILCALL", {"TAILCALL"})

-- FORLOOP / TFORCALL / TFORLOOP (conditional branch)
CATEGORIES[#CATEGORIES+1] = {name="FORLOOP", reps={"FORLOOP"}, is_terminal=true,
    gen = function(_,_,slots,_) return {op="FORLOOP", a=slots:read(1), sbx=-3} end}
CATEGORIES[#CATEGORIES+1] = {name="TFORCALL", reps={"TFORCALL"}, is_terminal=true,
    gen = function(_,_,slots,_) return {op="TFORCALL", a=slots:read(1)} end}
CATEGORIES[#CATEGORIES+1] = {name="TFORLOOP", reps={"TFORLOOP"}, is_terminal=true,
    gen = function(_,_,slots,_) return {op="TFORLOOP", a=slots:read(1), sbx=-3} end}

-- ── generation logic ─────────────────────────────────────────────────

function M.generate_all(max_arity)
    max_arity = max_arity or 4

    local continuers, terminators = {}, {}
    for _, cat in ipairs(CATEGORIES) do
        if cat.is_terminal then terminators[#terminators + 1] = cat
        else continuers[#continuers + 1] = cat end
    end

    local sequences = {}

    local function pick_rep(cat, idx)
        local reps = cat.reps or {cat.name}
        return reps[((idx - 1) % #reps) + 1]
    end

    local function enumerate_len(L)
        -- All-continuer sequences
        local function gen(pos, cur, slots, idx)
            if pos > L then
                sequences[#sequences + 1] = {ops = cur}
                return
            end
            for ci, cat in ipairs(continuers) do
                local r = pick_rep(cat, idx + ci + pos)
                local s2 = slots:clone()
                local ev = cat.gen(pos, pos, s2, r)
                local nv = {}
                for _, o in ipairs(cur) do nv[#nv + 1] = o end
                nv[#nv + 1] = ev
                gen(pos + 1, nv, s2, idx + ci)
            end
        end
        gen(1, {}, SlotTracker(), 0)

        -- Sequences ending in a terminator (only if L >= 2)
        if L >= 2 then
            local function gen_t(pos, cur, slots, idx)
                if pos >= L then
                    for ti, cat in ipairs(terminators) do
                        local r = pick_rep(cat, idx + ti + pos)
                        local s2 = slots:clone()
                        local ev = cat.gen(pos, pos, s2, r)
                        local nv = {}
                        for _, o in ipairs(cur) do nv[#nv + 1] = o end
                        nv[#nv + 1] = ev
                        sequences[#sequences + 1] = {ops = nv}
                    end
                    return
                end
                for ci, cat in ipairs(continuers) do
                    local r = pick_rep(cat, idx + ci + pos)
                    local s2 = slots:clone()
                    local ev = cat.gen(pos, pos, s2, r)
                    local nv = {}
                    for _, o in ipairs(cur) do nv[#nv + 1] = o end
                    nv[#nv + 1] = ev
                    gen_t(pos + 1, nv, s2, idx + ci)
                end
            end
            gen_t(1, {}, SlotTracker(), 0)
        end
    end

    for L = 1, max_arity do enumerate_len(L) end

    -- Deduplicate by SSA handler equivalence class
    local handler_map = {
        LOADI="LOAD_IMM", LOADF="LOAD_IMM",
        LOADK="LOAD_TBL", LOADKX="LOAD_TBL",
        LOADTRUE="LOAD_BOOL", LOADFALSE="LOAD_BOOL", LFALSESKIP="LOAD_BOOL",
        LOADNIL="LOAD_NIL",
        MOVE="MOVE", GETUPVAL="MOVE",
        SETUPVAL="SETUPV",
        NEWTABLE="OTHR", CONCAT="OTHR", CLOSURE="OTHR", VARARG="OTHR", SETLIST="OTHR",
        CALL="CALL", TAILCALL="CALL",
        RETURN="RET", RETURN0="RET", RETURN1="RET",
        JMP="JMP",
        CLOSE="CLOSE", TBC="CLOSE",
        ADD="BINOP_RR", SUB="BINOP_RR", MUL="BINOP_RR", DIV="BINOP_RR", MOD="BINOP_RR",
        POW="BINOP_RR", IDIV="BINOP_RR",
        BAND="BINOP_RR", BOR="BINOP_RR", BXOR="BINOP_RR", SHL="BINOP_RR", SHR="BINOP_RR",
        ADDI="BINOP_RI", SHLI="BINOP_RI", SHRI="BINOP_RI",
        ADDK="BINOP_K", SUBK="BINOP_K", MULK="BINOP_K",
        MODK="BINOP_K", POWK="BINOP_K", DIVK="BINOP_K", IDIVK="BINOP_K",
        BANDK="BINOP_K", BORK="BINOP_K", BXORK="BINOP_K",
        UNM="UNARY", BNOT="UNARY", NOT="UNARY", LEN="UNARY",
        GETTABLE="TBL_GET", GETI="TBL_GET",
        GETFIELD="FLD_GET", GETTABUP="FLD_GET", SELF="FLD_GET",
        SETTABLE="TBL_SET", SETI="TBL_SET",
        SETFIELD="FLD_SET", SETTABUP="FLD_SET",
        EQ="CMP_RR", LT="CMP_RR", LE="CMP_RR",
        EQK="CMP_K",
        EQI="CMP_RI", LTI="CMP_RI", LEI="CMP_RI", GTI="CMP_RI", GEI="CMP_RI",
        TEST="TEST", TESTSET="TESTSET",
        MMBIN="MMBIN", MMBINI="MMBINI", MMBINK="MMBINK",
        FORPREP="FPREP", TFORPREP="FPREP",
        FORLOOP="FLOOP", TFORLOOP="FLOOP", TFORCALL="FLOOP",
    }
    local function handler_of(op)
        local n = type(op) == "table" and op.op or tostring(op)
        return handler_map[n] or "UNK"
    end

    local eq = {}
    for _, seq in ipairs(sequences) do
        local handlers = {}
        for _, op in ipairs(seq.ops) do
            handlers[#handlers + 1] = handler_of(op)
        end
        local key = table.concat(handlers, "|")
        if not eq[key] then
            eq[key] = {handlers = handlers, ops = seq.ops, count = 0}
        end
        eq[key].count = eq[key].count + 1
    end

    local deduped = {}
    for _, e in pairs(eq) do
        deduped[#deduped + 1] = {ops = e.ops, count = e.count, handlers = e.handlers}
    end

    return deduped
end

-- ── fact enumeration ─────────────────────────────────────────────────

local function fact_axes_for_ops(ops)
    return FactAxes.axes_for_ops(ops)
end

local function fact_subsets(axes, config)
    return FactAxes.subsets(axes, config)
end

-- ── compile all ──────────────────────────────────────────────────────

function M.enumerate_grammar(config)
    config = config or {}
    local max_arity = tonumber(config.max_arity or 4) or 4

    local sequences = M.generate_all(max_arity)
    print(string.format("[grammar] Generated %d opcode sequences (arity 1-%d)", #sequences, max_arity))

    local forms_by_hash, total_compiles, total_ok = {}, 0, 0

    for si, seq in ipairs(sequences) do
        local ops = seq.ops
        local axes = fact_axes_for_ops(ops)
        local subsets = fact_subsets(axes, config)

        for _, facts in ipairs(subsets) do
            local result = SSA.compile(ops, facts, config)
            total_compiles = total_compiles + 1
            if result.ok then
                total_ok = total_ok + 1
                local key = result.normal_form_hash
                if not forms_by_hash[key] then
                    forms_by_hash[key] = {
                        key = key, normal_form = result.normal_form,
                        active_ops = result.active_ops,
                        ops = ops, facts = facts,
                        count = 0, changed = result.changed, source_ops = ops,
                    }
                end
                forms_by_hash[key].count = forms_by_hash[key].count + 1
            end
        end
        if si % 1000 == 0 then
            io.stderr:write(string.format("[grammar] %d/%d seq (x%d facts avg, %d OK, %d unique)...\n",
                si, #sequences, total_compiles > 0 and math.floor(total_compiles / si) or 0, total_ok, #forms_by_hash))
        end
    end

    local unique_count = 0
    for _ in pairs(forms_by_hash) do unique_count = unique_count + 1 end

    local stats = {sequences = #sequences, compiles = total_compiles, ok = total_ok, unique_forms = unique_count}

    local forms = {}
    for _, f in pairs(forms_by_hash) do forms[#forms + 1] = f end
    table.sort(forms, function(a, b) return a.count > b.count end)

    print(string.format("[grammar] %d unique SSA forms from %d compiles (%d OK, %d failed)",
        #forms, total_compiles, total_ok, total_compiles - total_ok))

    return {forms = forms, forms_by_hash = forms_by_hash, stats = stats}
end

-- Exact single-op floor set. This intentionally bypasses handler-class
-- deduplication so the runtime selector has a legal L0 fallback for every
-- concrete PUC opcode, not just one representative per handler class.
function M.generate_l0_all()
    local out, seen = {}, {}
    local function add(ev)
        if ev and ev.op and not seen[ev.op] then
            out[#out + 1] = {ops = {ev}, count = 1, l0 = true}
            seen[ev.op] = true
        end
    end
    for _, cat in ipairs(CATEGORIES) do
        for _, rep in ipairs(cat.reps or {}) do
            local slots = SlotTracker()
            add(cat.gen(1, 1, slots, rep))
        end
    end
    -- Opcodes not otherwise represented in the reduced foundry grammar still
    -- need exact L0 floor stencils so runtime fallback is total over PUC Lua.
    add({op="GETVARG", a=0, b=0, c=0})
    add({op="ERRNNIL", a=0, bx=0})
    add({op="VARARGPREP"})
    add({op="EXTRAARG", ax=0})
    return out
end

return M
