package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

package.loaded["llpvm"] = nil
package.loaded["llpvm.bytecode"] = nil
local standalone_bytecode = require("llpvm.bytecode")
assert(package.loaded["llpvm"] == nil, "llpvm.bytecode must not load the llpvm facade")

local ll = require("llpvm")

local spec = ll.load([[return language. BytecodeDemo {
  type. Node {
    op. Int { value [i64] },
    op. Add { left [Node], right [Node] },
  },

  world. raw,
} {

  raw. input {
    Int. a { value = 1 },
    Int. b { value = 2 },
    Add. c { left = a, right = b },
  },

  root { input },
}]], "bytecode-demo")

local image = spec:lower()
local bytes = image:bytecode()
assert(bytes:sub(1, 4) == "LLPV", "bytecode image has LLPV magic")
assert(#bytes > 64, "bytecode image contains records")
assert(type(standalone_bytecode.builder) == "function", "standalone bytecode builder remains importable")

local events = ll.inspect(bytes)
assert(events[1].kind == "header" and events[1].magic == "LLPV", "records process emits header")
assert(events[1].seq == 1, "validation process events carry seq")
local saw_record = false
for _, ev in ipairs(events) do
    if ev.kind == "record" and ev.tag_name == "stream_seq" then saw_record = true end
end
assert(saw_record, "records process emits decoded record metadata")

local validation = ll.validate:start(bytes)
assert(validation:resume().kind == "header", "validate process starts with header")
while validation:resume() do end
assert(validation:result().valid == true, "validate process returns validity summary")

local path = os.tmpname()
local wrote_path, n = image:write(path)
assert(wrote_path == path and n == #bytes, "ProgramImage:write returns byte count")
local f = assert(io.open(path, "rb"))
local disk = f:read("*a")
f:close()
os.remove(path)
assert(disk == bytes, "ProgramImage:write writes bytecode image")

local formatted = ll.format(spec)
assert(formatted:match("language%. BytecodeDemo"), "formatter emits language head")
assert(formatted:match("raw%. input"), "formatter emits generated world stream head")
assert(formatted:match("Int%. a"), "formatter emits generated op value heads")

local tmp = os.tmpname() .. ".lua"
local wf = assert(io.open(tmp, "wb"))
wf:write([[return language. BytecodeDemo {
  type. Node { op. Int { value [i64] }, },
  world. raw,
} {
  raw. input { Int. a { value = 1 }, },
  root { input },
}]])
wf:close()
local out = ll.write_format_file(tmp, { width = 80 })
assert(out:match('local ll = require%("llpvm"%)'), "format file writes Lua-owned LLPVM file")
local rf = assert(io.open(tmp, "rb"))
local saved = rf:read("*a")
rf:close()
os.remove(tmp)
assert(saved == out, "write_format_file writes returned text")

print("llpvm bytecode dsl ok")
