package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local ll = require("llpvm")
assert(ll.T and ll.B, "llpvm exposes ASDL context and FastBuilders")

local vm = ll.vm { cache_bytes = 64 * 1024 }

local Expr = vm.language "Expr"
local ExprNode = Expr "Node"
ExprNode.Int = { value = moon.i64 }
ExprNode.Add = { left = ExprNode, right = ExprNode }

local Back = vm.language "Back"
local BackValue = Back "Value"
BackValue.ConstI64 = { value = moon.i64 }
BackValue.AddI64 = {}

local ExprWorld = Expr:world()
local BackWorld = Back:world()

assert(type(ExprWorld.Node.Int) == "table", "world constructor is a callable table")
assert(ExprWorld.Node.Int.name == "Int", "constructor table keeps its name")

local one = ExprWorld.Node.Int { value = 1 }
local two = ExprWorld.Node.Int { value = 2 }
local sum = ExprWorld.Node.Add { left = one, right = two }

local input = ExprWorld:seq { one, two, sum }

local ops = input:drain()
assert(#ops == 3, "seq drains to three authored ops")
assert(ops[1].kind == "Int", "first op kind preserved")
assert(ops[1].payload[1] == 1, "named payload lowers to schema order")
assert(ops[3].payload[1] == one and ops[3].payload[2] == two, "typed payloads retain produced values")

local machine = vm.machine "lower_expr" {
    from = ExprWorld,
    to = BackWorld,
    entry = "ll_lower_expr",
}

local lower = vm.phase "lower_expr" {
    from = ExprWorld,
    to = BackWorld,
    machine = machine,
    cache = "full",
}

local mapped = lower {
    target = "wasm32",
    opt = 3,
} (input)

local mapped_node = mapped:one()
assert(mapped_node.kind == "phase_map", "phase call returns a phase-map stream")

local retained_input = vm.retain(input)
local rebuilt = vm.rebuild(function(next_vm)
    return ExprWorld:seq {
        retained_input:get():drain()[1],
        ExprWorld.Node.Int { value = 4 },
    }
end)
assert(#rebuilt:drain() == 2, "retained nodes can seed an incremental rebuild")

local ok_missing = pcall(function() ExprWorld.Node.Add { left = one } end)
assert(not ok_missing, "typed constructors reject missing fields")
local ok_extra = pcall(function() ExprWorld.Node.Int { value = 1, extra = true } end)
assert(not ok_extra, "typed constructors reject unknown fields")
local ok_wrong_type = pcall(function() ExprWorld.Node.Add { left = one, right = BackWorld.Value.ConstI64 { value = 3 } } end)
assert(not ok_wrong_type, "typed constructors reject values from another type/world")
local ok_after_seal = pcall(function() ExprNode.Bad = {} end)
assert(not ok_after_seal, "sealed languages reject new constructors")
assert(ll.node == nil, "global erased node type is not part of the public API")
assert(vm.abi == nil and vm.seq == nil, "old ABI-level constructor path is not exposed")
assert(ll.i64 == nil and ll.u32 == nil and ll.struct == nil and ll.ptr == nil, "ll does not expose a parallel type API")

local program = vm.program { input, mapped }
assert(#vm.abis == 2, "program captures ABIs")
assert(#vm.worlds == 2, "program captures implicit worlds")
assert(#vm.machines == 1, "program captures machines")
assert(#vm.phases == 1, "program captures phases")
assert(#program.root_ids == 2, "program captures roots")
assert(program:bytecode():sub(1, 4) == "LLPV", "program proxy encodes to LLPVM bytecode")

local direct = ll.B.LlPvm.Symbol { value = "direct-literal" }
assert(ll.symbol(direct) ~= nil, "standard ASDL layer remains available")

local Flat = vm.language "Flat"
local FlatNode = Flat "Node"
FlatNode.Pair = {
    { name = "right", type = moon.i64 },
    { name = "left", type = moon.i64 },
}
local FlatWorld = Flat:world()
local pair = FlatWorld.Node.Pair { right = 7, left = 3 }
assert(pair.payload[1] == 7 and pair.payload[2] == 3, "field list preserves source order")

print("llpvm lua api ok")
