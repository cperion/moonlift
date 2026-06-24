# LLB Guide

LLB (`lua/llb.lua`) is the standard Moonlift Lua DSL substrate. It is part of
the Moonlift standard library.

LLB is not a parser. Lua already parses the source. LLB gives meaning to the Lua
values produced by parserless authoring syntax:

```text
Lua syntax
  -> Lua values
  -> LLB events, heads, roles, fragments, origins, processes
  -> language AST / ASDL / IR
  -> diagnostics, formatting, LSP, phases, backends
```

Use LLB when you want a Lua-authored language surface that still behaves like a
real language: coherent grammar, semantic roles, diagnostics, formatting,
indexing, progress events, and controlled environments.

## The core idea

A normal Lua builder API usually hides language structure in functions and raw
tables.

LLB makes the structure explicit:

```text
Shape comes through a Channel as an Event.
A Slot accepts the Event.
A Role normalizes the Event value.
A Head sequences Slots into a language node.
A Fragment composes role-shaped values.
An Origin explains construction.
A Diagnostic reports failures.
A Format hook renders evaluated values.
An Environment exposes the authoring surface.
A Process streams long-running language work.
A Trait packages repeated behavior.
A Protocol defines reusable object behavior.
```

The ordinary user should see a small beautiful surface:

```lua
fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```

The language author should see the machinery clearly:

```lua
g.head. fn {
  g.trait. declaration,
  g.slot. name   [g.name]    { channel = llb.channel.index_name },
  g.slot. params [g.product] { channel = llb.channel.call_table },
  g.slot. result [g.type]    { channel = llb.channel.index_type, optional = true },
  g.slot. body   [g.body]    { channel = llb.channel.call_table },
  emit = function(n, lang) return lang.ast.fn(n) end,
}
```

## What LLB is for

LLB is for parserless DSLs where Lua is the metaprogramming language and the DSL
values are structured language data.

Good fits:

- compiler frontends embedded in Lua
- bytecode/image authoring DSLs
- VM and IR construction languages
- UI or document languages that need diagnostics and formatting
- test/data languages where generated structure must remain inspectable
- staged builder APIs where incomplete forms are useful

Bad fits:

- lossless Lua source rewriting
- comment-preserving formatting
- arbitrary textual macro expansion
- languages whose syntax must not be Lua syntax
- semantic engines that should live in the target compiler instead

LLB should stay generic. Moonlift-specific type rules, ownership, lowering, and
backend behavior belong to Moonlift, not LLB.

LLB's runtime compilation strategy is documented in
[`LLB_CODEGEN_APPROACH.md`](LLB_CODEGEN_APPROACH.md). Codegen specializes the
workbench machinery declared by LLB grammars: region plans, protocol exits,
role normalizers, future staged head machines, fragment expanders, family
projectors, diagnostics, indexing, formatting, and environment installers.

The region architecture is documented in
[`LLB_REGION_WORKBENCH_DESIGN.md`](LLB_REGION_WORKBENCH_DESIGN.md). This is the
architectural rule for new LLB work: region is the semantic control machine,
protocol names exits, GPS is one lowering ABI, and arrays, trees, reports,
indexes, diagnostic lists, or backend buffers are explicit materializers.

The generic semantic model is documented in
[`LLB_GENERIC_REGION_ALGEBRA.md`](LLB_GENERIC_REGION_ALGEBRA.md). Use it as the
design checklist before adding new process, phase, parser, scheduler,
diagnostic, or lowering machinery.

LLB owns the bare `region.` head in managed environments:

```lua
region. scan { input... } { exits... } { body... }
```

That creates a generic LLB `Region` descriptor. `region [Type]` remains normal
typed-name syntax; only dot-head use starts a region. Member languages consume
the descriptor according to their own backend. Moonlift consumes it as native
typed control when the body uses Moonlift block/jump/emit vocabulary.

Most workbench code should use a protocol-specific head instead of spelling the
full generic constructor. For example:

```lua
llb.process. records { "bytes" } (records_body)
llb.role_region. product ["role_items"] (product_body)
```

These are thin region-native heads. They still create `Region` descriptors; they
just own obvious protocol and input defaults.

## Surfaces

LLB has three public surfaces.

```text
Authoring surface
  What normal DSL users write.

Grammar surface
  What language authors write to define roles, heads, slots, traits, phases,
  helpers, type constructors, and formatting hooks.

Meta-protocol surface
  What workbench authors use for protocols, processes, origins, diagnostics,
  channels, shapes, and introspection.
```

Do not hide the meta surface. Power users need it. But do not make ordinary DSL
users pay for it in syntax.

The design rule:

```text
Expose power.
Name the danger.
Keep the default path simple.
```

## Design a language in the right order

Do not start by inventing heads. Start by identifying semantic roles.

### Step 1: Name the semantic products and sums

Ask what collections exist in the language:

```text
declarations
statements
fields
parameters
variants
continuations
attributes
imports
records
commands
```

Then decide their algebra:

```text
list/product     order matters, concatenate with ..
product          named fields, duplicate names usually invalid
sum/protocol     named alternatives, compose with +
record           keyed table, usually unordered
body             list with statement-like item rules
```

Example:

```lua
local g = llb.grammar

local Lang = llb.define "Demo" {
  g.role. decls   { kind = "array", algebra = "list" },
  g.role. body    { kind = "array", algebra = "list" },
  g.role. fields  { kind = "product", algebra = "product", unique_names = true },
  g.role. exits   { kind = "array", algebra = "sum", payload_role = "fields" },
}
```

A role is the main semantic unit. Heads should be thin. If two heads need the
same normalization rule, that rule belongs in a role.

### Step 2: Choose the Lua channel for each role

LLB channels describe how Lua delivered a value.

Common channels:

```text
index:name       fn. add
index:type       [i32], ptr [u8]
index:value      head [computed]
call:none        ret ()
call:value       ret (x)
call:table       { ... }
call:many        f(a, b, c)
operator:concat  ..
operator:choice  +
operator:decorate *
env:lookup       unknown global becomes a symbol/name
env:write        assignment in managed env
```

Public constants live in `llb.channel`.

Choose channels intentionally:

```lua
g.slot. name   [g.name]   { channel = llb.channel.index_name }
g.slot. params [g.fields] { channel = llb.channel.call_table }
g.slot. result [g.type]   { channel = llb.channel.index_type, optional = true }
g.slot. body   [g.body]   { channel = llb.channel.call_table }
```

Good channel choices make diagnostics precise:

```text
head fn expected result [type] through index:type
but received body through call:table
```

Bad channel choices make everything look like "some table was wrong".

### Step 3: Define heads as staged constructors

A head consumes slots in order. Each slot names a role and accepted channel.

```lua
g.head. module {
  g.slot. name [g.string] { channel = llb.channel.call_value },
  g.slot. body [g.decls]  { channel = llb.channel.call_table },
  emit = function(n)
    return { tag = "unit", name = n.name, body = n.body, origin = n.origin }
  end,
}

g.head. fn {
  g.slot. name   [g.name]   { channel = llb.channel.index_name },
  g.slot. params [g.fields] { channel = llb.channel.call_table },
  g.slot. result [g.type]   { channel = llb.channel.index_type, optional = true },
  g.slot. body   [g.body]   { channel = llb.channel.call_table },
  emit = function(n, lang)
    return {
      tag = "fn",
      name = n.name.text,
      params = n.params,
      result = n.result or lang.exports.void,
      body = n.body,
      origin = n.origin,
    }
  end,
}
```

Incomplete staged heads are intentional. They support headers, progressive
object building, and helper factories.

```lua
local add_header = fn. add { a [i32], b [i32] } [i32]
local add = add_header { ret (a + b) }
```

Do not treat incomplete closures as an error unless your language has a specific
semantic reason to reject them at a boundary.

### Step 4: Make fragments the metaprogramming unit

Fragments are role-tagged reusable pieces.

```lua
local xy = fields {
  x [i32],
  y [i32],
}

struct. Point {
  _(xy),
  z [i32],
}
```

`llb._(value)` is the preferred structural splice marker. `llb.spread(value)` is
the explicit alias.

Fragment algebra:

```text
product/list role .. same role       -> appended fragment
sum/protocol role + same role        -> alternatives fragment
sum/protocol role * product role     -> decorate alternatives
product role * sum/protocol role     -> decorate alternatives
```

Examples:

```lua
local xy = fields { x [i32] } .. fields { y [i32] }

local exits = conts { ok {} } + conts { err { code [i32] } }

local located = conts {
  eof {},
  syntax {},
} * fields {
  pos [index],
}
```

This is the preferred metaprogramming method for role-shaped sequences. Prefer
fragments over functions returning anonymous raw arrays.

Use functions for one computed value:

```lua
local function ptr_to(T)
  return ptr [T]
end
```

Use fragments for many role-shaped values:

```lua
local function vec_fields(T)
  return fields {
    data [ptr [T]],
    len [index],
  }
end
```

Use processes for streamed construction, analysis, progress, or stepping.

## Shape and event inspection

LLB can describe raw authoring values before they become semantic language data.

```lua
llb.shape_of(value)
llb.describe_shape(value)
llb.is_shape(value, "capture")
```

Common shapes:

```text
literal:string
literal:number
literal:boolean
name
symbol
capture
capture_init
expr
fragment
spread
array_table
record_table
mixed_table
llb_node
foreign_table
```

A staged head receives `Event` values:

```lua
local ev = llb.event(llb.channel.call_table, { x [i32] })
print(llb.describe_event(ev).shape)
```

Most users do not build events manually. Events matter for diagnostics,
introspection, and advanced grammar work.

## Names, symbols, types, expressions

Managed environments can auto-create unknown globals as symbols/names. This is
how parserless code can write:

```lua
a [i32]
ret (a + b)
```

The base atoms:

```lua
llb.name("x")
llb.symbol("x")
llb.N.x
llb.N["x"]
llb.type("i32")
llb.expr(value)
```

A language should decide whether unknown identifiers are names, symbols,
references, or errors. Do that through `use()` options, not scattered helper
functions.

## Environments and `use()`

LLB owns the generic environment lifecycle.

```lua
local session = Lang:family():use {
  scope = "permanent",
}

session:close()
```

Language methods are delegation helpers:

```lua
local session = Lang:use(opts)      -- delegates to Lang:family():use(opts)
local env = Lang:env(opts)          -- delegates to Lang:family():env(opts)
```

`llb.use(Lang, opts)` is accepted as a compatibility spelling, but it still
returns a family session. There is no separate language-only environment path.

Scopes:

```text
permanent  install exports into target until close or process end
scoped     same install behavior, but caller owns cleanup discipline
env        isolated environment, no global mutation
```

Use `scope = "env"` for loaders, tests, formatters, LSP, and tools.

```lua
local session = Lang:use { scope = "env" }
local env = session.env
```

Use `llb.with_use` when temporary globals are acceptable but cleanup must be
reliable:

```lua
llb.with_use(Lang, { scope = "scoped" }, function(env, session)
  -- DSL globals visible here.
end)
```

Important options:

```lua
Lang:use {
  scope = "env",
  target = {},
  base = "safe",       -- "safe" | "inherit" | table
  exports = {},
  helpers = true,
  strict = true,
  override = false,
  auto_names = true,
  requires = { "moonlift.types" },
  provides = { "my.language" },
}
```

Capabilities make language dependencies explicit. If one DSL depends on another,
model that with `requires` and `provides` instead of silently installing hidden
dependencies.

Low-level stacking is valid for tests and tools:

```lua
moon.use { scope = "env", target = env, global = false }
ll.use   { scope = "env", target = env, global = false }
```

But a coherent authoring surface should be a language family.

## Language families

A language is a grammar/protocol object. A family is the unit of authoring
coherence.

```text
Language:
  heads, roles, formatting, diagnostics, protocols

Family:
  multiple languages
  one environment contract
  one collision policy
  one capability graph
  one universal auto-name policy
  one value interop story
```

Every LLB language belongs to a family. The smallest family contains exactly one
member: `llb` itself. A single-language family is really `llb + language`.
Language `use`, `env`, and `loadstring` delegate through that family.

Use explicit multi-language families when languages are designed to be used
together and their values are expected to cross boundaries.

```lua
local Family = llb.family. moonlift {
  prefer = {
    task = "llpvm.dsl",
  },

  {
    name = "moonlift.dsl",
    lang = Moon,
    exports = moon_exports,
    provides = { "moonlift.types", "moonlift.dsl" },
  },

  {
    name = "llpvm.dsl",
    lang = LLPVM,
    exports = llpvm_exports,
    requires = { "moonlift.types" },
    provides = { "llpvm.dsl" },
  },

  {
    name = "llisle.dsl",
    lang = Llisle,
    exports = llisle_exports,
    requires = { "llb.core" },
    provides = { "llisle.dsl" },
  },
}
```

The family validates member requirements, composes exports, and rejects
undeclared collisions. Same-object exports are accepted. Different objects with
the same name require an explicit `prefer` entry.

Unknown identifiers always become generic `llb.Symbol` values:

```text
Lua unknown identifier
  -> llb.Symbol
  -> role/head slot
  -> language-specific semantic value
```

This is not configurable per language. Any LLB language that wants normal
authoring must accept `llb.Symbol` / `llb.Name` at semantic boundaries. Private
language name objects may exist as explicit helpers, but they are not the naming
substrate.

Public use is dot-style:

```lua
local session = moon.family.use {
  scope = "env",
  target = env,
  global = false,
}
```

Family methods are dot-only. Do not use colon syntax for family operations.

```lua
family.use { ... }
family.env { ... }
family.load(src, name)
family.loadfile(path)
family.prefer { task = "llpvm.dsl" }
family.only { "moonlift.types" }
family.subtract "llpvm.dsl"
```

The Moonlift family installs Moonlift, MoonSchema, LLPVM, and Llisle namespace
values together. Each member language consumes generic LLB symbols through its
roles. That avoids order-dependent metatable stacking.

Family environments expose member namespaces. Dedicated member islands may layer
that language with `Lang.use { scope = "env", target = env, base = env }` when
the code wants bare local heads without changing the mixed-family namespace
contract.

Llisle is the rule/rewrite/selection member. It reuses existing family algebra:
relations are typed product-to-product questions, projections classify family
values into MoonSchema-backed facts, rules and choices are sum arms, patterns
are product-shaped values, and rule bodies are process-shaped construction
bodies.

Llisle does not use a hidden callback registry as its semantic model. The
semantic declarations live in LLB values:

```lua
llisle {
  project. classify_expr {
    input { expr [MoonExpr] },
    output { class [ExprClassFact] },
    strategy { select. best_cost, ambiguity. error, coverage. complete },
  },

  predicate. has_type [has_type_impl] {
    input { value [Any], ty [Any] },
    pure,
  },

  constructor. add_i32 [build_add_i32],
}
```

`predicate` and `constructor` declarations are the public semantics. The `[]` slot carries the Lua implementation value directly, so there is no host side-table registry and no string reconnection seam. That keeps lowerings inspectable, documentable, diagnosable, and available to family tooling.

The same rule applies to typed relation fields: `input { expr [Tr.Expr] }`
splices the actual ASDL class value. Llisle `:is` guards understand those class
values, so ASDL lowering rules can dispatch on `P.expr :is (Tr.ExprLit)` without
inventing string-shaped dispatch records.

The same algebra is available inside roles:

```text
.. = sequence/list composition
+  = sum/choice composition
*  = product/conjunction composition
```

In a Llisle guard role, `+` means guard sum/or and `*` means guard product/and.
That is a role interpretation of LLB algebra, not a private boolean operator.

Family algebra composes authoring universes:

```lua
local Full = MoonFamily .. LLPVMFamily
local AlsoFull = MoonFamily + LLPVMFamily
local Tooling = Full.prefer {
  task = "llpvm.dsl",
  rule = "llisle.dsl",
}
local TypesOnly = Full.only { "moonlift.types" }
local NoLLPVM = Full - "llpvm.dsl"
```

Composition checks capabilities, export collisions, shared naming, and declared
preferences. Algebra operates on compatibility contracts, not just tables.

Inspection:

```lua
session:installed()
session:skipped()
session:auto_created()
session:requires()
session:provides()
session:exports()
session:describe()
```

## Origins and provenance

Lua helpers are the normal abstraction mechanism. Without origin threading,
errors inside helper-generated declarations point at the helper body instead of
the call site.

LLB provides:

```lua
llb.here(kind)
llb.at(origin, value)
llb.with_origin(origin, fn, ...)
llb.origin_of(value)
llb.source.leading_comment(origin)
llb.provenance(value)
llb.render_origin(origin)
llb.render_provenance(value)
```

Origins capture the source line and, when source text is available, the
contiguous Lua comment block immediately above that line. Generated references
use this as declaration documentation. This keeps interface prose beside the
head that owns it:

```lua
-- Defines a native function boundary.
g.head. fn {
  ...
}
```

Factory convention:

```lua
local function make_add(name, origin)
  origin = origin or llb.here("make_add")
  return fn:at(origin) [llb.at(origin, name)] {
    a [i32],
    b [i32],
  } [i32] {
    ret (a + b),
  }
end
```

If your DSL encourages abstraction, origin threading is not optional. It is the
difference between good diagnostics only in handwritten code and good
diagnostics everywhere.

## Diagnostics

LLB diagnostics are structured values:

```lua
local d = llb.diagnostic {
  severity = "error",
  code = "E_BAD_FIELD",
  message = "duplicate field",
  primary = origin,
  labels = {
    { origin = first_origin, message = "first field is here" },
  },
  notes = {
    "field names must be unique inside this role",
  },
}

print(d:render())
```

Diagnostic bags collect diagnostics:

```lua
local bag = llb.diagnostics()
bag:error { code = "E", message = "failed" }
bag:warning { code = "W", message = "suspicious" }

if bag:has_errors() then
  print(bag:render())
end
```

Use `llb.fail(message, spec)` at hard grammar boundaries. Use process diagnostics
for streamed analysis where the caller should continue receiving events.

```lua
return next_state, ctx:diagnostic {
  code = "E_BAD_RECORD",
  message = "record is truncated",
  offset = offset,
}
```

A good diagnostic should know:

```text
what event was consumed
which head consumed it
which slot expected it
which role normalized it
where the value came from
what the user can do next
```

## Formatting

LLB includes a small document algebra and width-aware renderer.

```lua
local text = llb.format(value, { width = 100, indent = 2 })
```

Document API:

```lua
local d = llb.doc

local doc = d.group {
  "fn. ", name, d.space(), params, d.space(), body,
}

print(llb.render(doc, { width = 100, indent = 2 }))
```

Format hooks can live on heads:

```lua
g.head. fn {
  g.slot. name [g.name],
  g.slot. params [g.fields],
  g.slot. body [g.body],

  format = function(node, f)
    return f:group {
      "fn. ",
      f:name(node.name),
      " ",
      f:braced_list(node.params),
      " ",
      f:block(node.body),
    }
  end,
}
```

Dispatch order:

```text
value metatable __llb_format hook
head format hook
language formatter table
generic LLB fallback
literal fallback
```

The formatter operates on evaluated values. It is not a token-preserving Lua
formatter. Origin-leading comments may be surfaced as documentation, but the
formatter will not preserve arbitrary comments or metaprogramming shape.

Canonical dot style for Moonlift-family DSLs is:

```lua
fn. add
lang. Expr
op. Int
ctx. record
```

The dot visually belongs to the keyword/head. Normal expression field access
stays tight:

```lua
value.field
object.owner
```

## Processes And GPS

LLB processes are event-protocol regions lowered to `gen,param,state`.

A process is pull-driven. The consumer asks for the next event; the generator
computes only enough work to produce that event. Do not prebuild an event array
unless the process is explicitly wrapping a materializing boundary such as a
whole backend call.

```lua
local region = llb.region

local function records_body(ctx, bytes)
  local function gen(param, state)
    if state == 0 then
      return 1, ctx:make_event("header", { bytes = #param.bytes })
    end
    if state == 1 then
      return 2, ctx:make_event("record", { index = 1 })
    end
    return nil
  end
  return gen, { bytes = bytes }, 0
end

local records = llb.process. records { "bytes" } (records_body)

for ev in records(image) do
  print(ev.seq, ev.kind)
end
```

A process is:

```text
region with event protocol
  + gen,param,state lowering
  + LLB event protocol
  + diagnostics bag
  + origin/provenance
  + budget/cancel hooks
  + resumable handle
```

Each `event` exit payload becomes a `ProcessEvent`:

```text
process  process name
kind     semantic event kind
seq      monotonic event order inside this run
origin   construction origin
```

Payload fields are flattened onto the event. Domain payloads may use `index`;
process order is always `seq`.

Manual handle API:

```lua
local h = records:start(bytes, llb.process_opts { budget = 100 })
local ev = h:resume()
for ev in h:events() do ... end
h:status()
h:done()
h:failed()
h:error()
h:result()
h:cancel()
```

Context API:

```lua
ctx:make_event("load", { uri = uri })       -- construct event
ctx:event("index", { analysis = analysis }) -- construct event dynamically
ctx:diagnostic { ... }                      -- construct diagnostic event
ctx:consume(1)
ctx:cancelled()
ctx:here("event")
ctx:at(value, origin)
```

These helpers return events. They do not yield and they do not enqueue. A
generator must return the event explicitly:

```lua
return next_state, ctx:make_event("step", { pc = pc })
```

Use processes for:

```text
source load/eval/index
bytecode inspection and validation
LSP indexing: symbol, hover, diagnostic
compiler progress
interpreter/debug stepping
long-running transforms
```

Do not use processes just to compute one pure value. Use a function for that.

Moonlift uses processes directly:

```lua
moon.source(src, name, { eval = true })
ll.validate(bytes)
require("moonlift.compiler_driver").lower_module(module, opts)
Debugger.process(debugger, { "init", "start", "step" })
```

LLB owns GPS event mechanics. LLPVM owns typed process declarations and
run records when the process becomes part of compiler/runtime architecture:

```lua
task. compile {
  input [i32],
  output [i32],
  event. progress [i32],
  event. diagnostic [i32],
}
```

Moonlift phase execution reports expose `report.run` as an
`LlPvm.TaskRun`, so progress tracking, validation, LSP indexing, source
analysis, and debugger stepping can share one typed event/run model instead of
ad hoc traces.

The architectural rule:

```text
Functions compute values.
Fragments compose role-shaped values.
Processes run region-shaped language work.
```

## Traits

Traits are behavior bundles applied at language definition time. They are not
inheritance.

```lua
g.trait. declaration {
  apply = function(lang, head, spec)
    head.lsp = head.lsp or {
      symbol = function(node)
        return { name = tostring(node.name), kind = head.name, origin = node.origin }
      end,
    }
  end,
}

g.head. fn {
  g.trait. declaration,
  g.slot. name [g.name],
  g.slot. body [g.body],
}
```

Use traits when repeated behavior has one semantic name:

```text
declaration
statement
control_block
source_indexed
formattable
hoverable
```

Do not create traits merely to be clever. A trait should remove duplication or
make tooling behavior consistent.

## Protocols

Protocols define reusable behavior families for LLB objects. They manufacture
immediate metatables. They do not rely on Lua metatable inheritance.

```lua
local protocol = llb.protocol("fragment", {
  operators = {
    concat = true,
    choice = true,
    decorate = true,
  },
})

llb.validate_protocol(protocol)
llb.describe_protocol(protocol)
llb.describe_metatable(protocol:metatable())
```

Use protocols when the behavior is an object family concern: fragments,
processes, staged heads, symbols, formatters, sessions, diagnostics.

Raw metatable mutation is Lua-legal, but protocol-generated metatables are the
supported LLB path.

## Phases and analysis

LLB can declare grammar phases:

```lua
g.phase. bind {
  run = function(ctx, unit)
    ctx:index_symbol(...)
    return unit
  end,
}
```

The generic phase/context layer is intentionally small. Moonlift's real compiler
phases live in Moonlift's PVM and frontend pipeline. LLB phases are for language
workbench structure and smaller language analyses.

For long-running phase progress, expose a process:

```lua
local region = llb.region

local function analyze_body(ctx, unit)
  local events = {
    ctx:make_event("phase", { name = "normalize" }),
    ctx:make_event("phase", { name = "bind" }),
  }
  return llb.gps.raw(llb.gps.from.array(events))
end

local analyze = llb.process. analyze { "unit" } (analyze_body)
```

## LSP and indexing

LLB does not implement an LSP server. It gives language authors the right event
shape for LSP tools.

A good language should expose pull-shaped process regions for:

```text
load
index
symbol
hover
diagnostic
completion
reference
definition
```

Use processes for this:

```lua
local region = llb.region

local function document_body(ctx, src, uri)
  local function gen(param, state)
    if state.phase == "load" then
      state.phase = "index"
      return state, ctx:make_event("load", { uri = uri, bytes = #src })
    end
    if state.phase == "index" then
      state.ast = load_ast(src, uri)
      state.symbols = symbols(state.ast)
      state.i = 1
      state.phase = "symbols"
      return state, ctx:make_event("index", { ast = state.ast })
    end
    if state.phase == "symbols" then
      local sym = state.symbols[state.i]
      if sym then
        state.i = state.i + 1
        return state, ctx:make_event("symbol", { symbol = sym })
      end
      state.diagnostics = diagnostics(state.ast)
      state.i = 1
      state.phase = "diagnostics"
    end
    if state.phase == "diagnostics" then
      local d = state.diagnostics[state.i]
      if d then
        state.i = state.i + 1
        return state, ctx:diagnostic(d)
      end
      state.phase = "result"
    end
    if state.phase == "result" then
      state.phase = "done"
      return state, ctx:make_event("result", { result = state.ast })
    end
    return nil
  end
  return gen, {}, { phase = "load" }
end

local document = llb.process. document { "src", "uri" } (document_body)
```

Moonlift's LSP dispatch exposes `lsp_document` this way and routes symbol,
hover, and diagnostic requests through process events.

## Introspection

LLB objects are inspectable:

```lua
llb.describe(value)
llb.describe_shape(value)
llb.describe_event(event)
llb.describe_head(lang, "fn")
llb.describe_role(lang, "fields")
llb.describe_fragment(fragment)
llb.describe_protocol("fragment")
llb.describe_process("records")
```

Languages should expose these directly:

```lua
M.describe = function(value) return llb.describe(value or Lang) end
M.describe_head = function(name) return Lang:describe_head(name) end
M.describe_role = function(name) return Lang:describe_role(name) end
```

Introspection powers documentation, tests, LSP hover, grammar visualization, and
diagnostics.

## A complete small language shape

```lua
local llb = require("llb")
local g = llb.grammar
local ch = llb.channel

local Mini = llb.define "Mini" {
  g.role. decls  { kind = "array", algebra = "list" },
  g.role. fields { kind = "product", algebra = "product", unique_names = true },
  g.role. body   { kind = "array", algebra = "list" },

  g.trait. declaration {
    apply = function(_, head)
      head.lsp = head.lsp or {
        symbol = function(n)
          return { name = tostring(n.name), kind = head.name, origin = n.origin }
        end,
      }
    end,
  },

  g.head. module {
    g.slot. name [g.string] { channel = ch.call_value },
    g.slot. body [g.decls]  { channel = ch.call_table },
    emit = function(n)
      return { tag = "unit", name = n.name, body = n.body, origin = n.origin }
    end,
  },

  g.head. fn {
    g.trait. declaration,
    g.slot. name   [g.name]   { channel = ch.index_name },
    g.slot. params [g.fields] { channel = ch.call_table },
    g.slot. result [g.type]   { channel = ch.index_type, optional = true },
    g.slot. body   [g.body]   { channel = ch.call_table },
    emit = function(n, lang)
      return {
        tag = "fn",
        name = n.name.text,
        params = n.params,
        result = n.result or lang.exports.void,
        body = n.body,
        origin = n.origin,
      }
    end,
  },
}

local function use(opts)
  return Mini:use {
    scope = opts and opts.scope or "permanent",
    target = opts and opts.target or _G,
    strict = opts and opts.strict,
    auto_names = true,
    provides = { "mini.dsl" },
  }
end

return {
  language = Mini,
  use = use,
  describe = function(value) return llb.describe(value or Mini) end,
  describe_head = function(name) return Mini:describe_head(name) end,
  describe_role = function(name) return Mini:describe_role(name) end,
}
```

User code:

```lua
local mini = require("mini")
mini.use()

return unit. Demo {
  fn. id { x [i32] } [i32] {
    ret (x),
  },
}
```

## Family zones

Every LLB family includes the `llb` singleton member. It is the smallest family
in the algebra and provides the shared substrate: `llb`, `N`, `_`, `spread`,
process helpers, and origin helpers. Language families are built on top of it,
so all family environments share `llb.Symbol` names and the same fragment/spread
semantics.

An LLB family can expose language zones as ordinary callable values:

```lua
return {
  moonlift {
    fn. add { a [i32], b [i32] } [i32] { ret (a + b) },
  },

  llpvm {
    task. compile {
      input [i32],
      output [i32],
      event. progress [i32],
    },
  },
}
```

A zone is a value with `family`, `member`, `name`, `role`, and `items`.
It is a semantic partition, not a lexical scope. Each language projects the
zones it owns and ignores foreign zones.

Same-language zones concatenate with `..`:

```lua
local a = moonlift { fn. one {} [i32] { ret (1) } }
local b = moonlift { fn. two {} [i32] { ret (2) } }
return a .. b
```

Different zones concatenate into a family bundle:

```lua
return moonlift { ... } .. llpvm { ... }
```

Public constructors:

```lua
llb.zone_head { family = "moonlift", member = "moonlift.dsl", name = "moonlift", role = "decls" }
llb.zone { family = "moonlift", member = "moonlift.dsl", name = "moonlift", role = "decls", items = { ... } }
llb.family_bundle { family = "moonlift", zones = { ... } }
```

Family tooling is also family-first:

```lua
local value = moon.family.loadfile("program.lua")()

local text = moon.family.format(value)
local diagnostics = moon.family.diagnostics(value)
local index = moon.family.index(value)
local reference = moon.family.markdown { title = "Moonlift Family Reference" }
moon.family.write_markdown("docs/MOONLIFT_FAMILY_REFERENCE.md")
```

Members contribute formatting, diagnostics, index, and Markdown hooks. The
family walks plain tables, zones, and bundles, delegates owned values to the
right member, and preserves LLB origins for diagnostics. This is what makes
cross-language family seams disappear at tooling boundaries.

Family Markdown generation is introspection-first:

- the family emits the overview, capabilities, collisions, shared names, zones,
  and tool list
- every generated family reference starts with the shared LLB syntax model:
  dot heads, index/type slots, table/call slots, fragments, algebra, and zones
- each member may provide a `markdown(member, opts, family)` hook
- members without a custom hook fall back to `llb.markdown_language(lang)`
- generated references are documentation views over the live language objects,
  including origin-leading comments when available, not hand-maintained
  duplicate specs

Formatting defaults should be semantic and stable:

- block heads use multiline bodies by default
- dot heads use keyword-side dots, such as `fn. add`
- product fields use `name [Type]`
- zones preserve their language name, such as `moonlift { ... }`
- family formatters delegate owned values instead of printing raw tables
- raw Lua table addresses should never appear in formatter output

## Design checklist

Before calling an LLB language complete, answer these questions.

Roles:

- What are the product/list/sum roles?
- Which roles compose with `..`, `+`, or `*`?
- Which roles reject duplicate names?
- Which roles own custom normalization?

Heads:

- What slots does each head consume?
- Which channel does each slot accept?
- Which slots are optional?
- Does each head stay thin and delegate shared rules to roles?

Metaprogramming:

- Are reusable pieces fragments instead of raw arrays?
- Is `_()` the structural splice marker?
- Are factories origin-threaded?

Environment:

- Does `use()` expose the complete surface?
- Are dependencies modeled with `requires`/`provides`?
- Do tools use `scope = "env"`?
- Are unknown names accepted as `llb.Symbol`, or rejected through strict mode?

Diagnostics:

- Do errors include head/slot/role/event context where possible?
- Do helper-generated values preserve caller origins?
- Are process diagnostics streamed instead of hidden until the end?

Formatting:

- Does the language have a canonical dot style?
- Are evaluated values formattable?
- Are role and head format hooks centralized?

Processes:

- Is source/load/eval/index process-shaped?
- Is inspection/validation process-shaped?
- Are long compiler or runtime operations process-shaped?
- Are debug/step operations process-shaped?

Tooling:

- Can the language yield symbol, hover, diagnostic, and index events?
- Does introspection describe roles, heads, fragments, protocols, and processes?

If the answer is no, the language may still work, but it is not fully wired as
an LLB language.

## Anti-patterns

Avoid these patterns:

```text
raw arrays passed between helpers with no role tag
hidden global dependency installation inside use()
stringly typed semantics inside callbacks
heads that duplicate role normalization rules
formatters that guess from source text instead of evaluated values
generators returning arbitrary values instead of process events
metatables mutated ad hoc instead of protocol-generated behavior
factories that lose caller origin
```

Prefer these patterns:

```text
role-tagged fragments
explicit use() capabilities
thin heads and strong roles
structured diagnostics
semantic formatting
process streams
origin-threaded factories
introspection-first language objects
```

## Relationship to Moonlift

Moonlift is the main LLB language in this repository.

```text
Lua syntax
  -> LLB staged heads and role normalization
  -> Moonlift DSL normalization
  -> MoonSyntax / MoonTree / MoonOpen ASDL
  -> typecheck / lowering / backend
```

LLB is the reusable substrate. Moonlift is the compiled language built on top.
LLPVM is another LLB language in the same ecosystem.

The shared doctrine:

```text
Lua is metaprogramming.
LLB is language construction.
ASDL/IR is semantic truth.
Processes expose work.
Backends execute results.
```

## Atom/protocol model

The deeper conceptual model is documented in
[`LLB_ATOM_PROTOCOL_MODEL.md`](LLB_ATOM_PROTOCOL_MODEL.md).
