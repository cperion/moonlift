package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local dsl = require("moonlift.dsl")

local src = [=[
return {
  struct. Vec2 {
    x [f32],
    y [f32],
  },

  union. Result {
    ok { value [i32] },
    err { code [i32] },
    none,
  },

  handle. SessionRef {
    invalid = 0,
  },

  extern. host_add
    { x [i32] }
    [i32]
    { symbol = "host_add" },

  const. answer [i32] (42),
  const. pi [f64] (3.14159),
  const. truth [bool] (true),
  static. zero [i32] (0),

  expr_frag. inc
    ({ x [i32] })
    [i32]
    (x + 1),

  fn. greeting
    {}
    [ptr [u8]]
    {
      ret "hello, moonlift",
    },

  fn. lit
    { x [i32] }
    [i32]
    {
      let. xs [array [i32] [2]] ({ x, x + 1 }),
      ret (xs[0]),
    },

  region. scan
    { x [i32] }
    {
      hit { pos [i32] },
      miss,
    }
    {
      entry. start {} {
        jump. hit { pos = x },
      },
    },

  fn. choose
    { x [i32] }
    [i32]
    {
      entry. start {} {
        emit. scan { x } {
          hit = done,
          miss = done,
        },
      },

      block. done { pos [i32] } {
        switch (pos) {
          case (0) {
            ret (answer),
          },

          default {
            ret (as [i32] (pos)),
          },
        },
      },
    },

  fn. atomic_ops
    { p [ptr [i32]], v [i32] }
    [i32]
    {
      let. a [i32] (aload (i32, p)),
      astore (i32, p, v),
      let. b [i32] (armw ("xchg", i32, p, v)),
      let. c [i32] (acas (i32, p, v, 0)),
      afence (),
      ret (a),
    },

  fn. contract_demo
    { buf [ptr [u8]], count [index] }
    [index]
    {
      requires {
        bounds (buf, count),
        noalias (buf),
      },
      ret (count),
    },

  fn. readonly_contract
    { buf [ptr [u8]], count [index] }
    [index]
    {
      requires {
        bounds (buf, count),
        readonly (buf),
        writeonly (buf),
      },
      ret (count),
    },

  fn. use_switch
    { x [i32] }
    [i32]
    {
      switch (x) {
        case (1) {
          ret (1),
        },

        default {
          ret (0),
        },
      },
    },

  fn. use_emit
    { x [i32] }
    [i32]
    {
      entry. start {} {
        emit. scan { x } {
          hit = done,
          miss = done,
        },
      },

      block. done { pos [i32] } {
        ret (pos),
      },
    },
}
]=]

local unit_value = dsl.to_unit("DslSmoke", dsl.loadstring(src, "dsl-smoke")())
assert(unit_value:syntax(), "syntax() failed")
assert(unit_value:ast(), "ast() failed")
assert(unit_value:typecheck(), "typecheck() failed")
assert(unit_value:lower({ site = "test_dsl_lua_owned", c_target = { dialect = "c11" } }), "lower() failed")

-- Test header / implementation split pattern
local header = dsl.loadstring([[
return {
  fn. add { a [i32], b [i32] } [i32],
  fn. sub { a [i32], b [i32] } [i32],
}
]], "header")()
assert(type(header[1]) == "table", "header fn. add did not produce callable stage")
assert(type(header[2]) == "table", "header fn. sub did not produce callable stage")

local impl = dsl.loadstring([[
local header = ...
return {
  header[1] { ret (a + b) },
  header[2] { ret (a - b) },
}
]], "impl")(header)
impl = dsl.to_unit("HeaderImpl", impl)
assert(impl:syntax(), "header/impl syntax failed")
assert(impl:ast(), "header/impl ast failed")
assert(impl:typecheck(), "header/impl typecheck failed")
assert(impl:lower({ site = "test_dsl_header_impl" }), "header/impl lower failed")

-- Test strict mode
local strict_src = [=[
accidental_global = 1
return {}
]=]

local ok, err = pcall(function()
    return dsl.loadstring(strict_src, "dsl-strict", { strict = true })()
end)
assert(not ok)
assert(tostring(err):match("unknown DSL global"))

print("moonlift lua-owned dsl ok")
