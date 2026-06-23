-- Public LLPVM facade — LLB DSL-first, no legacy mutation authoring surface.

local dsl = require("llpvm.dsl")
local bytecode = require("llpvm.bytecode")
local asdl = require("llpvm.asdl")
local task = require("llpvm.task")

local M = {
    dsl = dsl,
    asdl = asdl,
    task_model = task,
    T = asdl.T,
    B = asdl.B,
    language = dsl.language,
    meta_language = dsl.meta_language,
    ProgramSpec = dsl.ProgramSpec,
    ProgramImage = dsl.ProgramImage,
    MachineLanguage = dsl.MachineLanguage,
    TaskSpec = dsl.TaskSpec,
    Ident = dsl.Ident,
    Path = dsl.Path,
    Field = dsl.Field,
    Call = dsl.Call,
}

M.use = dsl.use
M.loadstring = dsl.loadstring
M.loadfile = dsl.loadfile
M.load = dsl.load
M.format = dsl.format
M.describe = dsl.describe
M.describe_head = dsl.describe_head
M.describe_role = dsl.describe_role
M.schema = dsl.schema
M.stream_items = dsl.stream_items
M.llpvm = dsl.llpvm
M._ = dsl._
M.spread = dsl.spread
M.bytebuffer = dsl.bytebuffer
M.records = dsl.records
M.validate = dsl.validate
M.inspect = dsl.inspect
M.task_run = task.run
M.task_event = task.event
M.task_step = task.step
M.record_task = task.record_handle

function M.bytecode(value, opts)
    local projected = dsl.to_program(value)
    if projected ~= nil and projected ~= value then return M.bytecode(projected, opts) end
    if type(value) == "table" and getmetatable(value) == dsl.ProgramSpec then return value:bytecode(opts) end
    if type(value) == "table" and getmetatable(value) == dsl.ProgramImage then return value:bytecode() end
    return bytecode.encode(value)
end

function M.format_file(path, opts) return dsl.file_text(dsl.loadfile(path, opts)(), opts) end
function M.write_format_file(path, opts) local text = M.format_file(path, opts); local f = assert(io.open(path, "wb")); f:write(text); f:close(); return text end

return M
