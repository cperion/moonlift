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
    return { tag = "module", name = n.name, body = n.body, origin = n.origin }
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
local session = Lang:use {
  scope = "permanent",
}

session:close()
```

Equivalent:

```lua
local session = llb.use(Lang, opts)
```

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
  auto_name = function(name, origin)
    return llb.symbol(name, { origin = origin })
  end,
  requires = { "moonlift.types" },
  provides = { "my.language" },
}
```

Capabilities make language dependencies explicit. If one DSL depends on another,
model that with `requires` and `provides` instead of silently installing hidden
dependencies.

```lua
moon.use { scope = "env", target = env, global = false }
ll.use   { scope = "env", target = env, global = false }
```

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
llb.provenance(value)
llb.render_origin(origin)
llb.render_provenance(value)
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
ctx. error {
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
formatter. It will not preserve comments or arbitrary metaprogramming shape.

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

## Processes and coroutines

LLB processes are coroutine-backed event streams.

```lua
local records = llb.process. records (function(ctx, bytes)
  ctx. header { bytes = #bytes }
  ctx. record { index = 1 }
  return { records = 1 }
end)

for ev in records(image) do
  print(ev.seq, ev.kind)
end
```

A process is:

```text
Lua coroutine
  + LLB event protocol
  + diagnostics bag
  + origin/provenance
  + budget/cancel hooks
  + resumable handle
```

Each yielded value is a `ProcessEvent`:

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
ctx. load { uri = uri }
ctx. index { analysis = analysis }
ctx. symbol { symbol = fact }
ctx:event("diagnostic", { diagnostic = fact })
ctx. step { pc = pc }
ctx:consume(1)
ctx:cancelled()
ctx:here("event")
ctx:at(value, origin)
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
Pipeline.Define(T).lower_module_process(module, opts)
Debugger.process(debugger, { "init", "start", "step" })
```

The architectural rule:

```text
Functions compute values.
Fragments compose role-shaped values.
Processes stream language work.
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
local analyze = llb.process. analyze (function(ctx, unit)
  ctx. phase { name = "normalize" }
  local normalized = normalize(unit)
  ctx. phase { name = "bind" }
  local bound = bind(normalized)
  return bound
end)
```

## LSP and indexing

LLB does not implement an LSP server. It gives language authors the right event
shape for LSP tools.

A good language should be able to stream:

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
local document = llb.process. document (function(ctx, src, uri)
  ctx. load { uri = uri, bytes = #src }
  local ast = load_ast(src, uri)
  ctx. index { ast = ast }
  for _, sym in ipairs(symbols(ast)) do
    ctx. symbol { symbol = sym }
  end
  for _, d in ipairs(diagnostics(ast)) do
    ctx:event("diagnostic", { diagnostic = d })
  end
  return ast
end)
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
      return { tag = "module", name = n.name, body = n.body, origin = n.origin }
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
    auto_name = function(name, origin)
      return llb.symbol(name, { origin = origin })
    end,
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

return module "Demo" {
  fn. id { x [i32] } [i32] {
    ret (x),
  },
}
```

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
- Are unknown names intentional through `auto_name`, or rejected through strict mode?

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
coroutines yielding arbitrary values instead of process events
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
