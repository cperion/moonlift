-- Parser protocol sugar over ASDL-native region_compose.
--
-- This module owns the traditional ok/fail/pos/next byte-parser defaults.  The
-- generic region algebra intentionally does not know those names.

local RegionCompose = require("moonlift.region_compose")

local M = {}
local ParserCompose = {}
ParserCompose.__index = ParserCompose

function M.new(moon_or_session, opts)
    opts = opts or {}
    local core = RegionCompose.new(moon_or_session, opts)
    return setmetatable({
        core = core,
        success = opts.success or "ok",
        failure = opts.failure or "fail",
        position_param = opts.position_param or "pos",
        next_param = opts.next_param or "next",
        failure_param = opts.failure_param or "at",
    }, ParserCompose)
end

function ParserCompose:opts(extra)
    extra = extra or {}
    extra.success = extra.success or self.success
    extra.failure = extra.failure or self.failure
    extra.position_param = extra.position_param or self.position_param
    extra.next_param = extra.next_param or self.next_param
    extra.failure_param = extra.failure_param or self.failure_param
    return extra
end

function ParserCompose:seq(fragments, opts) return self.core:seq(fragments, self:opts(opts)) end
function ParserCompose:choice(alternatives, opts) return self.core:choice(alternatives, self:opts(opts)) end
function ParserCompose:star(fragment, opts) return self.core:star(fragment, self:opts(opts)) end
function ParserCompose:plus(fragment, opts) return self.core:plus(fragment, self:opts(opts)) end
function ParserCompose:opt(fragment, opts) return self.core:opt(fragment, self:opts(opts)) end
function ParserCompose:pred(fragment, opts) return self.core:pred(fragment, self:opts(opts)) end
function ParserCompose:not_pred(fragment, opts) return self.core:not_pred(fragment, self:opts(opts)) end
function ParserCompose:fresh(base) return self.core:fresh(base) end

M.ParserCompose = ParserCompose
return M
