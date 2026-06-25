local pvm = require("lalin.pvm")
local schema_context = require("lalin.schema_context")

local M = {}

local function f(name, type_, opts)
    opts = opts or {}
    return { name = name, type = type_, list = opts.list, optional = opts.optional }
end

local function product(name, fields, unique)
    return { name = name, type = { kind = "product", unique = unique ~= false, fields = fields } }
end

local function sum(name, ctors)
    return { name = name, type = { kind = "sum", constructors = ctors } }
end

local function ctor(name, fields, unique)
    return { name = name, fields = fields, unique = unique ~= false }
end

local function q(name) return "LlPvm." .. name end

local definitions = {
    product(q("Symbol"), { f("value", "string") }),

    sum(q("ScalarType"), {
        ctor(q("Void")), ctor(q("Bool")), ctor(q("I8")), ctor(q("I16")), ctor(q("I32")), ctor(q("I64")),
        ctor(q("U8")), ctor(q("U16")), ctor(q("U32")), ctor(q("U64")), ctor(q("F32")), ctor(q("F64")), ctor(q("Index")),
    }),

    sum(q("Type"), {
        ctor(q("Scalar"), { f("scalar", q("ScalarType")) }),
        ctor(q("Handle"), { f("name", q("Symbol")) }),
        ctor(q("Pointer"), { f("to", q("Type")) }),
        ctor(q("View"), { f("item", q("Type")) }),
        ctor(q("Struct"), { f("name", q("Symbol")), f("fields", q("Field"), { list = true }) }),
    }),

    product(q("Field"), { f("name", q("Symbol")), f("type", q("Type")) }),
    product(q("OpKind"), { f("name", q("Symbol")), f("payload", q("Field"), { list = true }) }),
    product(q("Abi"), { f("name", q("Symbol")), f("version", "number"), f("ops", q("OpKind"), { list = true }), f("resource_type", q("Type"), { optional = true }) }),
    product(q("World"), { f("name", q("Symbol")), f("abi", q("Abi")) }),

    sum(q("OpPayloadValue"), {
        ctor(q("Nil")), ctor(q("BoolValue"), { f("value", "boolean") }), ctor(q("IntValue"), { f("value", "number") }),
        ctor(q("FloatValue"), { f("value", "number") }), ctor(q("StringValue"), { f("value", "string") }), ctor(q("RefValue"), { f("value", "number") }),
    }),

    product(q("Op"), { f("world", q("World")), f("kind", q("Symbol")), f("payload", q("OpPayloadValue"), { list = true }) }),

    sum(q("ArgValue"), {
        ctor(q("ArgNil")), ctor(q("ArgBool"), { f("value", "boolean") }), ctor(q("ArgInt"), { f("value", "number") }),
        ctor(q("ArgFloat"), { f("value", "number") }), ctor(q("ArgString"), { f("value", "string") }), ctor(q("ArgRef"), { f("value", "number") }),
    }),

    product(q("Args"), { f("values", q("ArgValue"), { list = true }) }),

    sum(q("Tape"), {
        ctor(q("Empty"), { f("world", q("World")) }),
        ctor(q("Once"), { f("op", q("Op")) }),
        ctor(q("Seq"), { f("world", q("World")), f("ops", q("Op"), { list = true }) }),
        ctor(q("Concat"), { f("tapes", q("Tape"), { list = true }) }),
        ctor(q("PhaseMap"), { f("phase", q("Phase")), f("input", q("Tape")), f("args", q("Args")) }),
    }),

    sum(q("Machine"), {
        ctor(q("RegionMachine"), { f("name", q("Symbol")), f("input", q("World")), f("output", q("World")), f("entry_symbol", q("Symbol")) }),
    }),

    sum(q("CacheMode"), { ctor(q("NoCache")), ctor(q("FullCache")), ctor(q("RecordOnly")) }),
    product(q("CachePolicy"), { f("mode", q("CacheMode")) }),
    product(q("Phase"), { f("name", q("Symbol")), f("input", q("World")), f("output", q("World")), f("machine", q("Machine")), f("cache", q("CachePolicy")) }),
    product(q("Diagnostic"), { f("code", "number"), f("message", "string") }),

    product(q("TaskEventSpec"), { f("name", q("Symbol")), f("payload", q("Type")) }),
    product(q("TaskSpec"), { f("name", q("Symbol")), f("input", q("Type")), f("output", q("Type")), f("events", q("TaskEventSpec"), { list = true }) }),
    product(q("TaskStepRun"), { f("index", "number"), f("phase", "string"), f("machine", "string"), f("status", "string") }),
    product(q("TaskRunEvent"), { f("seq", "number"), f("kind", "string"), f("message", "string") }),
    product(q("TaskRun"), { f("task", q("Symbol")), f("status", "string"), f("events", q("TaskRunEvent"), { list = true }), f("steps", q("TaskStepRun"), { list = true }) }),

    product(q("Program"), { f("abis", q("Abi"), { list = true }), f("worlds", q("World"), { list = true }), f("machines", q("Machine"), { list = true }), f("phases", q("Phase"), { list = true }), f("roots", q("Tape"), { list = true }) }),
}

function M.Define(T)
    if T.LlPvm ~= nil then return T end
    schema_context.define(T, definitions)
    return T
end

M.T = M.Define(pvm.context())
M.B = M.T:FastBuilders()

return M
