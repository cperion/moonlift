local pvm = require("pvm")

local M = {}

function M.Define(T)
    T:Define [[
        module LlPvm {
            Symbol = Symbol(string value) unique

            ScalarType = Void
                       | Bool
                       | I8 | I16 | I32 | I64
                       | U8 | U16 | U32 | U64
                       | F32 | F64
                       | Index

            Type = Scalar(LlPvm.ScalarType scalar) unique
                 | Handle(LlPvm.Symbol name) unique
                 | Pointer(LlPvm.Type to) unique
                 | View(LlPvm.Type item) unique
                 | Struct(LlPvm.Symbol name, LlPvm.Field* fields) unique

            Field = (LlPvm.Symbol name,
                     LlPvm.Type type) unique

            OpKind = (LlPvm.Symbol name,
                      LlPvm.Field* payload) unique

            Abi = (LlPvm.Symbol name,
                   number version,
                   LlPvm.OpKind* ops,
                   LlPvm.Type? resource_type) unique

            World = (LlPvm.Symbol name,
                     LlPvm.Abi abi) unique

            OpPayloadValue = Nil
                           | BoolValue(boolean value) unique
                           | IntValue(number value) unique
                           | FloatValue(number value) unique
                           | StringValue(string value) unique
                           | RefValue(number value) unique

            Op = (LlPvm.World world,
                  LlPvm.Symbol kind,
                  LlPvm.OpPayloadValue* payload) unique

            ArgValue = ArgNil
                     | ArgBool(boolean value) unique
                     | ArgInt(number value) unique
                     | ArgFloat(number value) unique
                     | ArgString(string value) unique
                     | ArgRef(number value) unique

            Args = (LlPvm.ArgValue* values) unique

            Stream = Empty(LlPvm.World world) unique
                   | Once(LlPvm.Op op) unique
                   | Seq(LlPvm.World world, LlPvm.Op* ops) unique
                   | Concat(LlPvm.Stream* streams) unique
                   | PhaseMap(LlPvm.Phase phase,
                              LlPvm.Stream input,
                              LlPvm.Args args) unique

            Machine = RegionMachine(LlPvm.Symbol name,
                                    LlPvm.World input,
                                    LlPvm.World output,
                                    LlPvm.Symbol entry_symbol) unique

            CacheMode = NoCache | FullCache | RecordOnly

            CachePolicy = (LlPvm.CacheMode mode) unique

            Phase = (LlPvm.Symbol name,
                     LlPvm.World input,
                     LlPvm.World output,
                     LlPvm.Machine machine,
                     LlPvm.CachePolicy cache) unique

            Diagnostic = (number code,
                          string message) unique

            Program = (LlPvm.Abi* abis,
                       LlPvm.World* worlds,
                       LlPvm.Machine* machines,
                       LlPvm.Phase* phases,
                       LlPvm.Stream* roots) unique
        }
    ]]
    return T
end

M.T = M.Define(pvm.context())
M.B = M.T:FastBuilders()

return M
