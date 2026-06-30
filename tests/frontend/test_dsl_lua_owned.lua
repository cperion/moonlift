package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema_projection")
local T = asdl.context()
Schema(T)
local dsl = require("lalin.dsl")(T)
local llbl = require("llbl")

local env = dsl.make_env()
assert(llbl.is_curried(env.lt) and llbl.is_curried(env.ge), "comparison helpers should be curried")
assert(llbl.is_curried(env.land) and llbl.is_curried(env.lor), "predicate composition helpers should be curried")
assert(env.land(env.gt(llbl._)(0))(env.lt(llbl._)(10)).kind == "logic", "curried predicate composition should emit logic expressions")

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

  fn. greeting
    {}
    [slice [u8]]
    {
      ret "hello, lalin",
    },

  fn. lit
    { x [i32] }
    [i32]
    {
      let. xs [array [i32] [2]] ({ x, x + 1 }),
      ret (xs[0]),
    },

  fn. atomic_ops
    { p [ptr [i32]], v [i32] }
    [i32]
    {
      let. a [i32] (aload (i32)(p)),
      astore (i32)(p)(v),
      let. b [i32] (armw ("xchg")(i32)(p)(v)),
      let. c [i32] (acas (i32)(p)(v)(0)),
      afence (),
      ret (a),
    },

  fn. contract_demo
    { buf [ptr [u8]], count [index] }
    [index]
    {
      requires {
        bounds (buf)(count),
        noalias (buf),
      },
      ret (count),
    },

  fn. readonly_contract
    { buf [ptr [u8]], count [index] }
    [index]
    {
      requires {
        bounds (buf)(count),
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

print("lalin lua-owned dsl ok")
