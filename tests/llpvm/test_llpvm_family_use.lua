package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local LLPVM = require("llpvm")

local env = {}
local session = lalin.family.use { scope = "env", target = env, global = false }
local desc = session:describe()
assert(desc.lang == "lalin", "family session is named")
assert(env.ll and env.lalin and env.llpvm and env.schema, "family installs member namespaces")
assert(env.ll == env.lalin, "ll should be the short alias for the Lalin namespace")
assert(env.region == require("llb").region, "family installs generic LLB region as the bare region head")
assert(rawget(env, "fn") == nil and rawget(env, "pvm") == nil and rawget(env, "i32") == nil and rawget(env, "task") == nil, "family does not leak member heads as bare globals")
assert(env.schema.product and env.schema.module and env.schema.FamilyProbe, "family installs LalinSchema through the schema namespace")
assert(require("llb").describe(env.lalin).tag == "Namespace", "Lalin family export should be an LLB namespace")
assert(require("llb").describe(env.llpvm).tag == "Namespace", "LLPVM family export should be an LLB namespace")
assert(require("llb").describe(env.schema).tag == "Namespace", "LalinSchema family export should be an LLB namespace")
assert(require("llb").describe(env.schema).default_head, "LalinSchema namespace should expose a default module head")

local reduction = lalin.family.reduction()
assert(reduction.tag == "FamilyReduction", "family reduction is inspectable")
assert(#reduction.smells == 0, reduction.smells[1] and reduction.smells[1].message or "family should have no semantic ownership smells")
assert(reduction.owner["type-family"] == "lalinschema.dsl", "LalinSchema owns product/sum/type-family semantics")
assert(reduction.owner["native-type-values"] == "lalin.dsl", "Lalin owns native type values")
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
  fields = ll.product { a [ll.i32], b [ll.i64] },

  lalin = ll {
    ll.fn. add { a [ll.i32], b [ll.i32] } [ll.i32] {
      ll.ret (a + b),
    },
  },

  proc = llpvm.task. compile {
    llpvm.input [ll.i32],
    llpvm.output [ll.i64],
    llpvm.event. progress [ll.i32],
  },

  low = llpvm {
    llpvm.pvm. Demo {
      llpvm.lang. Demo {
        llpvm.type. Node {
          llpvm.op. Int { value [ll.i64] },
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
assert(#out.fields.items == 2, "Lalin fragment uses family auto names")
assert(out.lalin.name == "lalin" and #out.lalin.items == 1, "lalin zone is installed")
assert(out.lalin.items[1].name == "add" and out.lalin.items[1]:syntax_item(), "Lalin function consumes generic LLB symbols")
assert(getmetatable(out.proc) == LLPVM.TaskSpec, "LLPVM task head is installed")
assert(out.low.name == "llpvm" and #out.low.items == 1, "llpvm zone is installed")
assert(getmetatable(out.low.items[1]) == LLPVM.ProgramSpec, "LLPVM pvm head is installed")
assert(LLPVM.bytecode(out):sub(1, 4) == "LLPV", "family-authored LLPVM zone projects to bytecode")
local schema_zone = lalin.family.load([[
return schema {
  schema. FamilySchemaSmoke {
    schema.product. Pair { schema.interned, left [LalinType.Type], right [LalinType.Type] },
  },
}
]], "family_schema.lua")
assert(schema_zone.name == "schema" and schema_zone.items[1].name == "FamilySchemaSmoke", "LalinSchema family namespace projects to schema zone")
local native = lalin.compile("FamilyZoneSmoke", out)
assert(native.add(3, 4) == 7, "family-authored Lalin zone projects to LuaJIT bytecode")

local formatted = lalin.family.format(out, { width = 100 })
assert(formatted:match("lalin%s*{"), "family formatter preserves lalin zone")
assert(formatted:match("llpvm%s*{"), "family formatter preserves llpvm zone")
assert(lalin.family.format(schema_zone):match("schema%. FamilySchemaSmoke"), "family formatter delegates LalinSchema zones")
assert(formatted:match("fn%. add"), "family formatter delegates Lalin declarations")
assert(formatted:match("pvm%. Demo"), "family formatter delegates LLPVM programs")
assert(formatted:match("task%. compile"), "family formatter delegates direct LLPVM task values")
assert(LLPVM.format(out.proc):match("input %[i32%]"), "LLPVM formatter should render scalar input as source type")
assert(LLPVM.format(out.proc):match("\n  output %[i64%],"), "LLPVM formatter should use multiline task bodies")

local diagnostics = lalin.family.diagnostics(out)
assert(not diagnostics:has_errors(), "family diagnostics should accept coherent mixed family value")

local bad = lalin.family.load([[
return lalin {
  ll.fn. bad {} [ll.i32] {
    ll.ret "not an integer",
  },
}
]], "family_bad.lua")
local bad_diagnostics = lalin.family.diagnostics(bad)
assert(bad_diagnostics:has_errors(), "family diagnostics should report Lalin semantic errors")
assert(bad_diagnostics.items[1].primary ~= nil or bad_diagnostics.items[1].message ~= nil, "family diagnostic should carry blame information")

local index = lalin.family.index(out)
local saw_add, saw_demo, saw_task = false, false, false
for _, sym in ipairs(index.symbols or {}) do
  saw_add = saw_add or sym.name == "add"
  saw_demo = saw_demo or sym.name == "Demo"
  saw_task = saw_task or sym.name == "compile"
end
assert(saw_add and saw_demo and saw_task, "family index should include Lalin and LLPVM symbols")

local markdown = lalin.markdown { title = "Lalin Family Reference" }
assert(markdown:match("# Lalin Family Reference"), "lalin markdown should include title")
assert(markdown:match("## LLB Syntax Model"), "lalin markdown should include shared syntax primer")
assert(markdown:match("## Reduced Family"), "lalin markdown should include reduction audit")
assert(markdown:match("type%-family"), "lalin markdown should document semantic owners")
assert(markdown:match("no semantic ownership overlaps"), "lalin markdown should report clean reduction audit")
assert(markdown:match("fn%. add"), "lalin markdown should explain canonical dot-head style")
assert(markdown:match("Shared Lua Language Builder substrate"), "lalin markdown should include llb singleton docs")
assert(markdown:match("## lalin%.dsl"), "lalin markdown should delegate Lalin member docs")
assert(markdown:match("## llpvm%.dsl"), "lalin markdown should delegate LLPVM member docs")
assert(markdown:match("## lalinschema%.dsl"), "lalin markdown should delegate LalinSchema member docs")
assert(markdown:match("schema%. product") or markdown:match("schema%.product"), "lalin markdown should document the LalinSchema namespace")
assert(markdown:match("Lalin LLB Surface"), "lalin markdown should include Lalin fallback introspection")
assert(markdown:match("LLPVM LLB Surface"), "lalin markdown should include LLPVM fallback introspection")

local loaded = lalin.family.load([[
return llpvm.task. quick {
  llpvm.input [ll.i32],
  llpvm.output [ll.i32],
}
]], "family_load.lua")
assert(getmetatable(loaded) == LLPVM.TaskSpec, "family load uses composed environment")

io.write("llpvm family_use ok\n")
