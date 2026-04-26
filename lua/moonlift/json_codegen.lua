local ffi = require("ffi")
local JsonLibrary = require("moonlift.json_library")
local BufferView = require("moonlift.buffer_view")

local M = {}

local Projector = {}
Projector.__index = Projector
local ViewDecoder = {}
ViewDecoder.__index = ViewDecoder
local next_view_layout_id = 1

local function c_ident(s)
    s = tostring(s):gsub("[^%w_]", "_")
    if not s:match("^[A-Za-z_]") then s = "_" .. s end
    return s
end

local function printable_ascii(s)
    if s == "" then return false end
    for i = 1, #s do
        local b = s:byte(i)
        if b < 32 or b > 126 then return false end
    end
    return true
end

local function normalize_fields(fields)
    local out = {}
    local issues = {}
    local names = {}
    local idents = {}
    fields = fields or {}
    for i, f in ipairs(fields) do
        local name, ty
        if type(f) == "string" then
            name, ty = f, "i32"
        else
            name = f and f.name
            ty = (f and f.type) or "i32"
        end
        name = tostring(name or "")
        ty = tostring(ty or "i32")
        if ty ~= "i32" and ty ~= "bool" then
            issues[#issues + 1] = ("field %d (%s) has unsupported projection type `%s` (supported: i32, bool)"):format(i, name, ty)
        end
        if name == "" then
            issues[#issues + 1] = ("field %d has an empty JSON key name"):format(i)
        elseif not printable_ascii(name) then
            issues[#issues + 1] = ("field %d (%s) must be printable ASCII for raw indexed lookup"):format(i, name)
        end
        if names[name] then issues[#issues + 1] = ("field %d duplicates JSON key `%s`"):format(i, name) end
        names[name] = true
        local id = c_ident(name)
        if idents[id] then issues[#issues + 1] = ("field %d (%s) collides after generated identifier sanitization as `%s`"):format(i, name, id) end
        idents[id] = true
        out[#out + 1] = { name = name, type = ty, index = i - 1, ident = id }
    end
    if #issues ~= 0 then return nil, { issues = issues } end
    return out, nil
end

local function report_string(report)
    return table.concat(report and report.issues or {}, "\n")
end

function M.project(fields, opts)
    opts = opts or {}
    local normalized, report = normalize_fields(fields)
    if not normalized then error(report_string(report), 2) end
    return setmetatable({
        fields = normalized,
        stack_cap = opts.stack_cap or 256,
        byte_cap = opts.byte_cap,
        tape_cap = opts.tape_cap,
    }, Projector)
end

function Projector:compile()
    if self.compiled then return self end
    local compiled, err = JsonLibrary.compile()
    if not compiled then error("json library compile failed at " .. tostring(err and err.stage), 2) end
    self.compiled = compiled
    self.decoder = JsonLibrary.doc_decoder(compiled, {
        byte_cap = self.byte_cap or 4096,
        tape_cap = self.tape_cap or self.byte_cap or 4096,
        stack_cap = self.stack_cap,
    })
    return self
end

local function fill_from_doc(self, doc, out)
    for i, f in ipairs(self.fields) do
        local value, err
        if f.type == "bool" then
            value, err = doc:get_bool(f.name)
            if err == "missing" then
                out[i - 1] = 0
            elseif err then
                return nil, "type:" .. f.name
            else
                out[i - 1] = value and 1 or 0
            end
        else
            value, err = doc:get_i32(f.name)
            if err == "missing" then
                out[i - 1] = 0
            elseif err then
                return nil, "type:" .. f.name
            else
                out[i - 1] = value
            end
        end
    end
    return out, 0
end

function Projector:decode_i32(src, out)
    self:compile()
    out = out or ffi.new("int32_t[?]", #self.fields)
    local doc, err = self.decoder:decode(src)
    if not doc then return nil, err end
    return fill_from_doc(self, doc, out)
end

function Projector:decode_doc(doc, out)
    self:compile()
    out = out or ffi.new("int32_t[?]", #self.fields)
    return fill_from_doc(self, doc, out)
end

function Projector:decode_table(src)
    local out, err = self:decode_i32(src)
    if not out then return nil, err end
    local t = {}
    for i, f in ipairs(self.fields) do
        local v = tonumber(out[i - 1])
        if f.type == "bool" then v = v ~= 0 end
        t[f.name] = v
    end
    return t, 0
end

function Projector:view_layout(opts)
    opts = opts or {}
    if self._view_layout then return self._view_layout end
    local id = next_view_layout_id
    next_view_layout_id = next_view_layout_id + 1
    local name = c_ident(opts.name or ("JsonProjectView" .. tostring(id)))
    local ctype = "Moonlift" .. name
    local lines = { "typedef struct " .. ctype .. " {" }
    local view_fields = {}
    for i, f in ipairs(self.fields) do
        local cfield = "f" .. tostring(i)
        lines[#lines + 1] = "int32_t " .. cfield .. ";"
        if f.type == "bool" then
            view_fields[i] = { name = f.name, cfield = cfield, kind = "i32", storage_kind = "i32", expose_kind = "bool" }
        else
            view_fields[i] = { name = f.name, cfield = cfield, kind = "i32" }
        end
    end
    lines[#lines + 1] = "} " .. ctype .. ";"
    self._view_layout = BufferView.define_record({
        name = name,
        ctype = ctype,
        cdef_key = ctype,
        cdef = table.concat(lines, "\n"),
        fields = view_fields,
    })
    return self._view_layout
end

function Projector:view_layout_facts(T, opts)
    opts = opts or {}
    local HostFacts = require("moonlift.host_layout_facts").Define(T)
    local layout = self:view_layout(opts.layout)
    return HostFacts.fact_set_for_buffer_view(layout, opts)
end

function Projector:new_view(opts)
    opts = opts or {}
    local layout = self:view_layout(opts.layout)
    local init = {}
    for _, f in ipairs(self.fields) do init[f.name] = 0 end
    return layout:new(init, opts)
end

function Projector:decode_into_view(src, view)
    local out = ffi.cast("int32_t*", view:ptr())
    local got, err = self:decode_i32(src, out)
    if not got then return nil, err end
    return view, 0
end

function Projector:decode_doc_into_view(doc, view)
    local out = ffi.cast("int32_t*", view:ptr())
    local got, err = self:decode_doc(doc, out)
    if not got then return nil, err end
    return view, 0
end

function Projector:view_decoder(opts)
    opts = opts or {}
    local view = assert(self:new_view(opts))
    return setmetatable({ projector = self, view = view }, ViewDecoder)
end

function ViewDecoder:decode(src)
    return self.projector:decode_into_view(src, self.view)
end

function ViewDecoder:free()
    self.view = nil
end

function Projector:free()
    if self.compiled and self.compiled.artifact then self.compiled.artifact:free() end
    self.compiled = nil
    self.decoder = nil
end

M.null = JsonLibrary.null
M.compile_validator = JsonLibrary.compile
M.decode_tape = JsonLibrary.decode_tape
M.index_tape = JsonLibrary.index_tape
M.parse = JsonLibrary.parse
M.doc_decoder = JsonLibrary.doc_decoder
M.JsonDoc = JsonLibrary.JsonDoc
M.JsonDocDecoder = JsonLibrary.JsonDocDecoder
M.normalize_spec = normalize_fields
M.projection_report_string = report_string
M.Projector = Projector
M.ViewDecoder = ViewDecoder

return M
