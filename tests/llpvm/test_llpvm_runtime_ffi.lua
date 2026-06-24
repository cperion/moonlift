package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ll = require("llpvm")

assert(package.loaded["llpvm.runtime_ffi"] == nil, "LLPVM tests do not use retired C/FFI runtime path")

local spec = ll.load([[return language. RuntimeContract {
  type. Node {
    op. Int { value [i64] },
    op. Add { left [Node], right [Node] },
  },

  lang. Back {
    type. Value {
      op. ConstI64 { value [i64] },
    },
  },

  world. raw,
  world. lowered [Back],

  phase. lower_expr {
    from. raw,
    to. lowered,
    entry. ll_lower_expr,
    cache. full,
  },
} {
  raw. input {
    Int. one { value = 1 },
    Int. two { value = 2 },
    Add. sum { left = one, right = two },
  },

  root {
    input,
    lower_expr (input),
  },
}]], "runtime-contract")

local image = spec:bytecode()
assert(image:sub(1, 4) == "LLPV", "runtime contract produces LLPV image")

local buf, len = ll.bytebuffer(image)
assert(len == #image, "bytebuffer reports exact image length")
assert(buf ~= nil, "bytebuffer returns FFI buffer for runtime boundary")

local lowered = spec:lower()
assert(#lowered.root_ids == 2, "runtime image has explicit root tapes")
assert(#lowered.root_ops == 3, "runtime image exposes first-root op table")
assert(lowered.lowering.phases.lower_expr ~= nil, "runtime image includes phase metadata")

print("llpvm runtime contract dsl ok")
