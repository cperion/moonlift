local M = {}

local pvm = require("moonlift.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.c_cfg ~= nil then return T._moonlift_api_cache.c_cfg end

    local C = T.MoonC

    local Builder = {}
    Builder.__index = Builder

    local function new(ctx, opts)
        opts = opts or {}
        local self = setmetatable({}, Builder)
        self.ctx = ctx or {}
        self.blocks = {}
        self.next_label = opts.next_label or 0
        self.next_temp = opts.next_temp or 0
        self.current = nil
        if opts.entry ~= false then self:start_block(opts.entry_label or "entry", opts.entry_params or {}) end
        return self
    end

    function Builder:label(prefix)
        self.next_label = self.next_label + 1
        return C.CBackendLabel(sanitize(prefix or "bb") .. "_" .. tostring(self.next_label))
    end

    function Builder:join_label(prefix)
        return self:label(prefix or "join")
    end

    function Builder:local_id(prefix)
        self.next_temp = self.next_temp + 1
        return C.CBackendLocalId("tmp_" .. sanitize(prefix or "v") .. "_" .. tostring(self.next_temp))
    end

    function Builder:add_local(id, name, ty)
        local local_decl = C.CBackendLocal(id, C.CBackendName(sanitize(name or id.text)), ty)
        self.ctx.locals = self.ctx.locals or {}
        self.ctx.locals[#self.ctx.locals + 1] = local_decl
        self.ctx.local_types = self.ctx.local_types or {}
        self.ctx.local_types[id.text] = ty
        return local_decl
    end

    function Builder:temp(prefix, ty)
        local id = self:local_id(prefix)
        self:add_local(id, prefix, ty)
        return id, C.CBackendAtomLocal(id)
    end

    function Builder:result_temp(prefix, ty)
        return self:temp(prefix or "result", ty)
    end

    function Builder:start_block(label, params)
        if type(label) == "string" then label = C.CBackendLabel(sanitize(label)) end
        if self.current and self.current.term == nil then error("c_cfg: cannot start a new block before terminating current block", 2) end
        self.current = { label = label, params = params or {}, stmts = {}, term = nil }
        return self.current
    end

    function Builder:emit(stmt)
        if self.current == nil then error("c_cfg: no current block", 2) end
        if self.current.term ~= nil then error("c_cfg: cannot emit after terminator", 2) end
        self.current.stmts[#self.current.stmts + 1] = stmt
        return stmt
    end

    function Builder:terminate(term)
        if self.current == nil then error("c_cfg: no current block", 2) end
        if self.current.term ~= nil then error("c_cfg: block already terminated", 2) end
        self.current.term = term
        self.blocks[#self.blocks + 1] = C.CBackendBlock(self.current.label, self.current.params, self.current.stmts, term)
        return term
    end

    function Builder:goto_block(label, args)
        if type(label) == "string" then label = C.CBackendLabel(sanitize(label)) end
        return self:terminate(C.CBackendGoto(label, args or {}))
    end

    function Builder:if_goto(cond, then_label, else_label, then_args, else_args)
        if type(then_label) == "string" then then_label = C.CBackendLabel(sanitize(then_label)) end
        if type(else_label) == "string" then else_label = C.CBackendLabel(sanitize(else_label)) end
        return self:terminate(C.CBackendIfGoto(cond, then_label, then_args or {}, else_label, else_args or {}))
    end

    function Builder:switch_goto(value, cases, default_label, default_args)
        if type(default_label) == "string" then default_label = C.CBackendLabel(sanitize(default_label)) end
        return self:terminate(C.CBackendSwitchGoto(value, cases or {}, default_label, default_args or {}))
    end

    function Builder:return_void()
        return self:terminate(C.CBackendReturnVoid)
    end

    function Builder:return_value(atom)
        return self:terminate(C.CBackendReturn(atom))
    end

    function Builder:trap()
        return self:terminate(C.CBackendTrap)
    end

    function Builder:parallel_transfer(assignments)
        -- assignments: { { dst = CBackendLocalId, value = CBackendAtom, ty = CBackendType }, ... }
        -- First copy all sources into transfer temps, then assign temps to destinations.
        local temps = {}
        for i = 1, #(assignments or {}) do
            local a = assignments[i]
            local tid = self:local_id("transfer")
            self:add_local(tid, tid.text, a.ty)
            self:emit(C.CBackendAssign(tid, C.CBackendRAtom(a.value)))
            temps[i] = { dst = a.dst, value = C.CBackendAtomLocal(tid) }
        end
        for i = 1, #temps do self:emit(C.CBackendAssign(temps[i].dst, C.CBackendRAtom(temps[i].value))) end
        return temps
    end

    function Builder:block_param(local_id, ty)
        return C.CBackendBlockParam(local_id, ty)
    end

    function Builder:sealed_blocks(default_term)
        if self.current and self.current.term == nil then
            if default_term == false then error("c_cfg: current block is unterminated", 2) end
            self:terminate(default_term or C.CBackendTrap)
        end
        return self.blocks
    end

    function Builder:is_terminated()
        return self.current ~= nil and self.current.term ~= nil
    end

    local api = { new = new, Builder = Builder }

    T._moonlift_api_cache.c_cfg = api
    return api
end

return M
