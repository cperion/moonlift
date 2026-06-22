package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local dsl = require("moonlift.dsl")

local src = [[
return module "DslSmoke" {
  struct .Vec2 {
    x[f32],
    y[f32],
  },

  union .Result {
    ok { value[i32] },
    err { code[i32] },
    none,
  },

  handle .SessionRef {
    invalid = 0,
  },

  extern .host_add
    { x[i32] }
    [i32]
    { symbol = "host_add" },

  const .answer [i32] { 42 },
  static .zero [i32] { 0 },

  expr_frag .inc
    { x[i32] }
    [i32]
    { x + 1 },

  region .scan
    { x[i32] }
    {
      hit { pos[i32] },
      miss,
    }
    {
      entry .start {} {
        jump .hit { pos = x },
      },
    },

  fn .choose
    { x[i32] }
    [i32]
    {
      entry .start {} {
        emit .scan { x } {
          hit = done,
          miss = done,
        },
      },

      block .done { pos[i32] } {
        switch { pos } {
          case_value(0) {
            ret { answer },
          },

          default {
            ret { as[i32](pos) },
          },
        },
      },
    },
}
]]

local module = dsl.loadstring(src, "dsl-smoke")()
assert(module:syntax())
assert(module:ast())
assert(module:typecheck())
assert(module:lower({ site = "test_dsl_lua_owned" }))

local strict_src = [[
accidental_global = 1
return module "Strict" {}
]]

local ok, err = pcall(function()
    return dsl.loadstring(strict_src, "dsl-strict", { strict = true })()
end)
assert(not ok)
assert(tostring(err):match("unknown DSL global"))

print("moonlift lua-owned dsl ok")
