package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

package.loaded["llpvm"] = nil
package.loaded["llpvm.bytecode"] = nil
local standalone_bytecode = require("llpvm.bytecode")
assert(package.loaded["llpvm"] == nil, "llpvm.bytecode must not load the llpvm facade")

local ll = require("llpvm")

local vm = ll.vm {}
local Expr = vm.abi "Expr" {
    Int = { value = ll.i64 },
    Add = { left = ll.node, right = ll.node },
}
local Back = vm.abi "Back" {
    ConstI64 = { value = ll.i64 },
}
local expr_world = Expr:world()
local back_world = Back:world()
local input = vm.seq(expr_world) {
    Expr.Int { value = 1 },
    Expr.Int { value = 2 },
    Expr.Add {},
}
local machine = vm.machine "lower_expr" {
    from = expr_world,
    to = back_world,
    entry = "ll_lower_expr",
}
local phase = vm.phase "lower_expr" {
    from = expr_world,
    to = back_world,
    machine = machine,
    cache = "full",
}
local program = vm.program { input, phase(input) }
local bytes = program:bytecode()

assert(bytes:sub(1, 4) == "LLPV", "bytecode image has LLPV magic")
assert(#bytes > 64, "bytecode image contains records")
assert(bytes == ll.bytecode(program), "facade bytecode helper matches Program:bytecode")
assert(bytes == standalone_bytecode.encode(program.__llpvm_node), "standalone bytecode encoder matches facade")

local path = os.tmpname()
local wrote_path, n = program:write(path)
assert(wrote_path == path and n == #bytes, "Program:write returns byte count")
local f = assert(io.open(path, "rb"))
local disk = f:read("*a")
f:close()
os.remove(path)
assert(disk == bytes, "Program:write writes bytecode image")

print("llpvm bytecode ok")
