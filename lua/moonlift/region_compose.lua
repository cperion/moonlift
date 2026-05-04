-- MoonLift region composition algebra.
--
-- Builds composed control regions from existing tokenizer/fragment regions.
-- All composition happens at Lua generation time: each combinator produces a
-- new MoonLift `RegionFragValue` ready for splicing into a module.
--
--   local C = RegionCompose.new("my_grammar")
--   local seq_ab = C:seq("ab", {frag_a, frag_b})
--   local star_a = C:star("astar", frag_a)
--
-- Continuation protocol (every input and output fragment must conform):
--   ok:   cont(next: i32)    -- matched, advanced to this position
--   fail: cont(at: i32)      -- failed at this position (no advancement)

local Host = require("moonlift.host_quote")

local RegionFragValue = {}
-- RegionFragValue metatable is inherited from host_quote

local Compose = {}
Compose.__index = Compose

---Create a fresh composition context.
--@param prefix string Unique prefix for generated region/block names.
function Compose.new(prefix)
    local self = setmetatable({ prefix = prefix or "c", next_id = 0 }, Compose)
    return self
end

function Compose:fresh_id(base)
    self.next_id = self.next_id + 1
    return string.format("%s_%s_%d", self.prefix, base, self.next_id)
end

---@param fragments table[] Ordered array of RegionFragValues.
---@return RegionFragValue
function Compose:seq(fragments)
    if type(fragments) ~= "table" or #fragments == 0 then
        error("seq expects a non-empty array of fragments", 2)
    end
    local name = self:fresh_id("seq")
    local parts = {}
    parts[#parts + 1] = "region " .. name .. "(p: ptr(u8), n: i32, pos: i32; ok: cont(next: i32), fail: cont(at: i32))\nentry start()\n    emit "

    -- First fragment
    parts[#parts + 1] = fragments[1]
    local next_block = #fragments > 1 and (name .. "_1") or "ok"
    parts[#parts + 1] = "(p, n, pos; ok = " .. next_block .. ", fail = fail)\n"

    -- Middle fragments
    for i = 2, #fragments do
        local block_name = name .. "_" .. (i - 1)
        local next_target = (i < #fragments) and (name .. "_" .. i) or "ok"
        parts[#parts + 1] = "end\nblock " .. block_name .. "(next: i32)\n    emit "
        parts[#parts + 1] = fragments[i]
        parts[#parts + 1] = "(p, n, next; ok = " .. next_target .. ", fail = fail)\n"
    end

    parts[#parts + 1] = "end\nend"
    return Host.source(parts)
end

---@param alternatives table[] Ordered array of RegionFragValues.
---@return RegionFragValue
function Compose:choice(alternatives)
    if type(alternatives) ~= "table" or #alternatives == 0 then
        error("choice expects a non-empty array of fragments", 2)
    end
    local name = self:fresh_id("choice")
    local parts = {}
    parts[#parts + 1] = "region " .. name .. "(p: ptr(u8), n: i32, pos: i32; ok: cont(next: i32), fail: cont(at: i32))\nentry start()\n    emit "

    parts[#parts + 1] = alternatives[1]
    local next_block = #alternatives > 1 and (name .. "_1") or "ok"
    local fail_target = #alternatives > 1 and "fail" or "fail"
    parts[#parts + 1] = "(p, n, pos; ok = " .. next_block .. ", fail = try_" .. name .. "_1)\n"

    for i = 2, #alternatives - 1 do
        local try_name = "try_" .. name .. "_" .. (i - 1)
        parts[#parts + 1] = "end\nblock " .. try_name .. "(at: i32)\n    emit "
        parts[#parts + 1] = alternatives[i]
        parts[#parts + 1] = "(p, n, pos; ok = ok, fail = try_" .. name .. "_" .. i .. ")\n"
    end

    if #alternatives > 1 then
        local last_try = "try_" .. name .. "_" .. (#alternatives - 1)
        parts[#parts + 1] = "end\nblock " .. last_try .. "(at: i32)\n    emit "
        parts[#parts + 1] = alternatives[#alternatives]
        parts[#parts + 1] = "(p, n, pos; ok = ok, fail = fail)\n"
    end

    parts[#parts + 1] = "end\nend"
    return Host.source(parts)
end

---Zero or more repetitions.
---@param fragment RegionFragValue
---@return RegionFragValue
function Compose:star(fragment)
    local name = self:fresh_id("star")
    return Host.source {
        "region ", name, "(p: ptr(u8), n: i32, pos: i32; ok: cont(next: i32))\n",
        "entry start()\n",
        "    emit ", fragment, "(p, n, pos; ok = ", name, "_loop, fail = ", name, "_zero)\n",
        "end\n",
        "block ", name, "_loop(next: i32)\n",
        "    emit ", fragment, "(p, n, next; ok = ", name, "_loop, fail = ", name, "_yield)\n",
        "end\n",
        "block ", name, "_yield(at: i32)\n",
        "    jump ok(next = at)\n",
        "end\n",
        "block ", name, "_zero()\n",
        "    jump ok(next = pos)\n",
        "end\nend",
    }
end

---One or more repetitions.
---@param fragment RegionFragValue
---@return RegionFragValue
function Compose:plus(fragment)
    local plus_frag = self:star(fragment)
    return self:seq({fragment, plus_frag})
end

---Optional (zero or one).
---@param fragment RegionFragValue
---@return RegionFragValue
function Compose:opt(fragment)
    local name = self:fresh_id("opt")
    return Host.source {
        "region ", name, "(p: ptr(u8), n: i32, pos: i32; ok: cont(next: i32))\n",
        "entry start()\n",
        "    emit ", fragment, "(p, n, pos; ok = ok, fail = ", name, "_none)\n",
        "end\n",
        "block ", name, "_none(at: i32)\n",
        "    jump ok(next = pos)\n",
        "end\nend",
    }
end

---Positive lookahead (&a). Succeeds if `fragment` matches but does not advance.
---@param fragment RegionFragValue
---@return RegionFragValue
function Compose:pred(fragment)
    local name = self:fresh_id("pred")
    return Host.source {
        "region ", name, "(p: ptr(u8), n: i32, pos: i32; ok: cont(next: i32), fail: cont(at: i32))\n",
        "entry start()\n",
        "    emit ", fragment, "(p, n, pos; ok = ", name, "_ok, fail = fail)\n",
        "end\n",
        "block ", name, "_ok(next: i32)\n",
        "    jump ok(next = pos)\n",
        "end\nend",
    }
end

---Negative lookahead (!a). Succeeds if `fragment` does NOT match.
---@param fragment RegionFragValue
---@return RegionFragValue
function Compose:not_pred(fragment)
    local name = self:fresh_id("not")
    return Host.source {
        "region ", name, "(p: ptr(u8), n: i32, pos: i32; ok: cont(next: i32), fail: cont(at: i32))\n",
        "entry start()\n",
        "    emit ", fragment, "(p, n, pos; ok = ", name, "_fail, fail = ", name, "_ok)\n",
        "end\n",
        "block ", name, "_ok(at: i32)\n",
        "    jump ok(next = pos)\n",
        "end\n",
        "block ", name, "_fail(next: i32)\n",
        "    jump fail(at = pos)\n",
        "end\nend",
    }
end

return Compose
