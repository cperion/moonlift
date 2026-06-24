package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")
local ll = require("llpvm")

local env = {}
local session = moon.family.use { scope = "env", target = env, global = false }
local desc = session:describe()
assert(desc.lang == "moonlift", "family session is named")
assert(env.ml and env.moonlift and env.llpvm and env.schema, "family installs member namespaces")
assert(env.ml == env.moonlift, "ml should be the short alias for the Moonlift namespace")
assert(env.region == require("llb").region, "family installs generic LLB region as the bare region head")
assert(rawget(env, "fn") == nil and rawget(env, "pvm") == nil and rawget(env, "i32") == nil and rawget(env, "task") == nil, "family does not leak member heads as bare globals")
assert(env.schema.product and env.schema.module and env.schema.FamilyProbe, "family installs MoonSchema through the schema namespace")
assert(require("llb").describe(env.moonlift).tag == "Namespace", "Moonlift family export should be an LLB namespace")
assert(require("llb").describe(env.llpvm).tag == "Namespace", "LLPVM family export should be an LLB namespace")
assert(require("llb").describe(env.schema).tag == "Namespace", "MoonSchema family export should be an LLB namespace")
assert(require("llb").describe(env.schema).default_head, "MoonSchema namespace should expose a default module head")

local reduction = moon.family.reduction()
assert(reduction.tag == "FamilyReduction", "family reduction is inspectable")
assert(#reduction.smells == 0, reduction.smells[1] and reduction.smells[1].message or "family should have no semantic ownership smells")
assert(reduction.owner["type-family"] == "moonschema.dsl", "MoonSchema owns product/sum/type-family semantics")
assert(reduction.owner["native-type-values"] == "moonlift.dsl", "Moonlift owns native type values")
assert(reduction.owner["bytecode-program"] == "llpvm.dsl", "LLPVM owns bytecode programs")
local llpvm_reuses_type_family = false
for _, member in ipairs(reduction.members or {}) do
  if member.name == "llpvm.dsl" then
    for _, semantic in ipairs(member.uses or {}) do
      llpvm_reuses_type_family = llpvm_reuses_type_family or semantic == "type-family"
    end
  end
end
assert(llpvm_reuses_type_family, "LLPVM should reuse schema type-family semantics")

local chunk = assert(loadstring([[
return {
  fields = ml.product { a [ml.i32], b [ml.i64] },

  moon = ml {
    ml.fn. add { a [ml.i32], b [ml.i32] } [ml.i32] {
      ml.ret (a + b),
    },
  },

  proc = llpvm.task. compile {
    llpvm.input [ml.i32],
    llpvm.output [ml.i64],
    llpvm.event. progress [ml.i32],
  },

  low = llpvm {
    llpvm.pvm. Demo {
      llpvm.lang. Demo {
        llpvm.type. Node {
          llpvm.op. Int { value [ml.i64] },
        },
      },

      llpvm.world. raw [Demo],

      llpvm.tape. raw_items [raw] {
        llpvm.record. one (Node.Int { value = 1 }),
      },

      llpvm.root { raw_items, one },
    },
  },
}
]], "llpvm_family_use.lua"))
setfenv(chunk, env)

local out = chunk()
assert(#out.fields.items == 2, "Moonlift fragment uses family auto names")
assert(out.moon.name == "moonlift" and #out.moon.items == 1, "moonlift zone is installed")
assert(out.moon.items[1].name == "add" and out.moon.items[1]:syntax_item(), "Moonlift function consumes generic LLB symbols")
assert(getmetatable(out.proc) == ll.TaskSpec, "LLPVM task head is installed")
assert(out.low.name == "llpvm" and #out.low.items == 1, "llpvm zone is installed")
assert(getmetatable(out.low.items[1]) == ll.ProgramSpec, "LLPVM pvm head is installed")
assert(ll.bytecode(out):sub(1, 4) == "LLPV", "family-authored LLPVM zone projects to bytecode")
local schema_zone = moon.family.load([[
return schema {
  schema. FamilySchemaSmoke {
    schema.product. Pair { schema.interned, left [MoonType.Type], right [MoonType.Type] },
  },
}
]], "family_schema.lua")
assert(schema_zone.name == "schema" and schema_zone.items[1].name == "FamilySchemaSmoke", "MoonSchema family namespace projects to schema zone")
local native = moon.compile("FamilyZoneSmoke", out)
assert(native.add(3, 4) == 7, "family-authored Moonlift zone projects to LuaJIT bytecode")

local formatted = moon.family.format(out, { width = 100 })
assert(formatted:match("moonlift%s*{"), "family formatter preserves moonlift zone")
assert(formatted:match("llpvm%s*{"), "family formatter preserves llpvm zone")
assert(moon.family.format(schema_zone):match("schema%. FamilySchemaSmoke"), "family formatter delegates MoonSchema zones")
assert(formatted:match("fn%. add"), "family formatter delegates Moonlift declarations")
assert(formatted:match("pvm%. Demo"), "family formatter delegates LLPVM programs")
assert(formatted:match("task%. compile"), "family formatter delegates direct LLPVM task values")
assert(ll.format(out.proc):match("input %[i32%]"), "LLPVM formatter should render scalar input as source type")
assert(ll.format(out.proc):match("\n  output %[i64%],"), "LLPVM formatter should use multiline task bodies")

local diagnostics = moon.family.diagnostics(out)
assert(not diagnostics:has_errors(), "family diagnostics should accept coherent mixed family value")

local bad = moon.family.load([[
return moonlift {
  ml.fn. bad {} [ml.i32] {
    ml.ret "not an integer",
  },
}
]], "family_bad.lua")
local bad_diagnostics = moon.family.diagnostics(bad)
assert(bad_diagnostics:has_errors(), "family diagnostics should report Moonlift semantic errors")
assert(bad_diagnostics.items[1].primary ~= nil or bad_diagnostics.items[1].message ~= nil, "family diagnostic should carry blame information")

local index = moon.family.index(out)
local saw_add, saw_demo, saw_task = false, false, false
for _, sym in ipairs(index.symbols or {}) do
  saw_add = saw_add or sym.name == "add"
  saw_demo = saw_demo or sym.name == "Demo"
  saw_task = saw_task or sym.name == "compile"
end
assert(saw_add and saw_demo and saw_task, "family index should include Moonlift and LLPVM symbols")

local markdown = moon.markdown { title = "Moonlift Family Reference" }
assert(markdown:match("# Moonlift Family Reference"), "moon markdown should include title")
assert(markdown:match("## LLB Syntax Model"), "moon markdown should include shared syntax primer")
assert(markdown:match("## Reduced Family"), "moon markdown should include reduction audit")
assert(markdown:match("type%-family"), "moon markdown should document semantic owners")
assert(markdown:match("no semantic ownership overlaps"), "moon markdown should report clean reduction audit")
assert(markdown:match("fn%. add"), "moon markdown should explain canonical dot-head style")
assert(markdown:match("Shared Lua Language Builder substrate"), "moon markdown should include llb singleton docs")
assert(markdown:match("## moonlift%.dsl"), "moon markdown should delegate Moonlift member docs")
assert(markdown:match("## llpvm%.dsl"), "moon markdown should delegate LLPVM member docs")
assert(markdown:match("## moonschema%.dsl"), "moon markdown should delegate MoonSchema member docs")
assert(markdown:match("schema%. product") or markdown:match("schema%.product"), "moon markdown should document the MoonSchema namespace")
assert(markdown:match("Moonlift LLB Surface"), "moon markdown should include Moonlift fallback introspection")
assert(markdown:match("LLPVM LLB Surface"), "moon markdown should include LLPVM fallback introspection")

local loaded = moon.family.load([[
return llpvm.task. quick {
  llpvm.input [ml.i32],
  llpvm.output [ml.i32],
}
]], "family_load.lua")
assert(getmetatable(loaded) == ll.TaskSpec, "family load uses composed environment")

io.write("llpvm family_use ok\n")
