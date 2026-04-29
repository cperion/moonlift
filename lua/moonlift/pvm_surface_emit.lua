-- Emit lowerable MoonPvmSurface phase bodies as Moonlift surface region fragments.
--
-- The target shape is Moonlift's existing region-fragment/emit model:
-- a producer region calls an ambient typed emit fragment with `resume` filled by
-- the producer's continuation label.  Phase composition is therefore ordinary
-- typed jump/control flow, not an interpreted stream object.

local pvm = require("moonlift.pvm")
local Model = require("moonlift.pvm_surface_model")

local M = {}

local function is_a(cls, value)
    return type(cls) == "table" and cls.isclassof and cls:isclassof(value) or false
end

local function sanitize(name)
    return tostring(name):gsub("[^%w_]", "_")
end

local function push(out, n, line)
    out[#out + 1] = string.rep("    ", n) .. line
end

local function type_ref_name(Ph, ref)
    local cls = pvm.classof(ref)
    if ref == Ph.TypeRefAny then return "Value" end
    if cls == Ph.TypeRefValue then return ref.name end
    if cls == Ph.TypeRef then return ref.module_name .. "_" .. ref.type_name end
    return "Value"
end

local function id_type_name(Ph, ref)
    return type_ref_name(Ph, ref) .. "Id"
end

local function emit_fragment_name(Ph, ref)
    return "emit_" .. id_type_name(Ph, ref)
end

local Emitter = {}
Emitter.__index = Emitter

function Emitter:fresh(prefix)
    self.seq = self.seq + 1
    return sanitize(prefix) .. "_" .. tostring(self.seq)
end

function Emitter:expr(e)
    local S = self.S
    local cls = pvm.classof(e)
    if e == S.ExprSubject then return "subject" end
    if cls == S.ExprLocal then return e.name end
    if cls == S.ExprName then return e.name end
    if cls == S.ExprLiteralInt then return e.text end
    if cls == S.ExprLiteralBool then return e.value and "true" or "false" end
    if cls == S.ExprField then return self:expr(e.base) .. "." .. e.field_name end
    if cls == S.ExprCall then
        local args = {}
        for i = 1, #e.args do args[i] = self:expr(e.args[i]) end
        return e.func_name .. "(" .. table.concat(args, ", ") .. ")"
    end
    if cls == S.ExprCtor then
        local args = { "ctx" }
        for i = 1, #e.fields do args[#args + 1] = self:expr(e.fields[i].value) end
        local prefix = e.type_name ~= "" and (sanitize(e.type_name) .. "_") or ""
        return "make_" .. prefix .. sanitize(e.ctor_name) .. "(" .. table.concat(args, ", ") .. ")"
    end
    error("pvm_surface_emit: unsupported Expr " .. tostring(cls and cls.kind or e), 2)
end

function Emitter:producer(out, indent, producer, done_label)
    local S = self.S
    local cls = pvm.classof(producer)
    if producer == S.ProducerEmpty then
        push(out, indent, "jump " .. done_label .. "()")
    elseif cls == S.ProducerOnce then
        local tmp = self:fresh("out")
        push(out, indent, "let " .. tmp .. " = " .. self:expr(producer.value))
        push(out, indent, "emit " .. self.emit_fragment .. "(" .. tmp .. "; resume = " .. done_label .. ")")
    elseif cls == S.ProducerCallPhase then
        local args = { "ctx", self:expr(producer.subject) }
        for i = 1, #producer.args do args[#args + 1] = self:expr(producer.args[i]) end
        push(out, indent, "emit " .. sanitize(producer.phase_name) .. "(" .. table.concat(args, ", ") .. "; done = " .. done_label .. ")")
    elseif cls == S.ProducerConcat then
        self:concat(out, indent, producer.parts, 1, done_label)
    elseif cls == S.ProducerChildren then
        self:children(out, indent, producer, done_label)
    elseif cls == S.ProducerLet then
        push(out, indent, "let " .. producer.name .. " = " .. self:expr(producer.value))
        self:producer(out, indent, producer.body, done_label)
    elseif cls == S.ProducerIf then
        push(out, indent, "if " .. self:expr(producer.cond) .. " then")
        self:producer(out, indent + 1, producer.then_body, done_label)
        push(out, indent, "else")
        self:producer(out, indent + 1, producer.else_body, done_label)
        push(out, indent, "end")
    else
        error("pvm_surface_emit: unsupported Producer " .. tostring(cls and cls.kind or producer), 2)
    end
end

function Emitter:concat(out, indent, parts, index, done_label)
    if index > #parts then
        push(out, indent, "jump " .. done_label .. "()")
        return
    end
    if index == #parts then
        self:producer(out, indent, parts[index], done_label)
        return
    end
    local next_label = self:fresh("after_concat")
    self:producer(out, indent, parts[index], next_label)
    push(out, 0, "")
    push(out, indent, "block " .. next_label .. "()")
    self:concat(out, indent + 1, parts, index + 1, done_label)
    push(out, indent, "end")
end

function Emitter:children(out, indent, producer, done_label)
    local loop = self:fresh("children_loop")
    local after = self:fresh("after_child")
    local child = self:fresh("child")
    local range = self:expr(producer.range)
    push(out, indent, "jump " .. loop .. "(i = 0)")
    push(out, 0, "")
    push(out, indent, "block " .. loop .. "(i: index)")
    push(out, indent + 1, "if i >= " .. range .. ".len then")
    push(out, indent + 2, "jump " .. done_label .. "()")
    push(out, indent + 1, "end")
    push(out, indent + 1, "let " .. child .. " = range_get(ctx, " .. range .. ", i)")
    push(out, indent + 1, "emit " .. sanitize(producer.phase_name) .. "(ctx, " .. child .. "; done = " .. after .. ")")
    push(out, indent, "end")
    push(out, 0, "")
    push(out, indent, "block " .. after .. "()")
    push(out, indent + 1, "jump " .. loop .. "(i = i + 1)")
    push(out, indent, "end")
end

function Emitter:handler(out, indent, handler)
    local binds = {}
    for i = 1, #handler.binds do binds[#binds + 1] = handler.binds[i].name end
    push(out, indent, "case " .. handler.ctor_name .. "(" .. table.concat(binds, ", ") .. ")")
    self:producer(out, indent + 1, handler.body, "done")
end

function M.emit_phase_body(T, body, opts)
    opts = opts or {}
    Model.Define(T)
    local Ph, S = T.MoonPhase, T.MoonPvmSurface
    if pvm.classof(body) ~= S.PhaseBody then error("pvm_surface_emit.emit_phase_body expects MoonPvmSurface.PhaseBody", 2) end
    local self = setmetatable({ S = S, Ph = Ph, seq = 0, emit_fragment = opts.emit_fragment or emit_fragment_name(Ph, body.output) }, Emitter)
    local out = {}
    local phase_name = sanitize(body.name) .. "_uncached"
    push(out, 0, "-- generated PVM-on-Moonlift producer region")
    push(out, 0, "-- ambient emit fragment: " .. self.emit_fragment .. "(value; resume)")
    push(out, 0, "region " .. phase_name .. "(ctx: NativePvmContext, subject: " .. id_type_name(Ph, body.input) .. "; done: cont())")
    push(out, 0, "entry start()")
    push(out, 1, "let subject_value = arena_get(ctx, subject)")
    push(out, 1, "match subject_value")
    for i = 1, #body.handlers do self:handler(out, 1, body.handlers[i]) end
    if body.default_body ~= nil then
        push(out, 1, "default")
        self:producer(out, 2, body.default_body, "done")
    end
    push(out, 1, "end")
    push(out, 0, "end")
    return table.concat(out, "\n") .. "\n"
end

function M.Define(T)
    Model.Define(T)
    return {
        emit_phase_body = function(body, opts) return M.emit_phase_body(T, body, opts) end,
        emit_fragment_name = function(ref) return emit_fragment_name(T.MoonPhase, ref) end,
        id_type_name = function(ref) return id_type_name(T.MoonPhase, ref) end,
    }
end

return M
