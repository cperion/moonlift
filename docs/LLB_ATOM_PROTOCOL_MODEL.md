# LLB Atom and Protocol Model

LLB is the standard Lalin Lua DSL substrate. It is not a parser, a class
system, or a Lalin semantic engine. It is a language-event substrate built on
Lua values and metatables.

Metatables are the implementation carrier. They are not the conceptual model.

The stable conceptual atoms are:

```text
Shape
Channel
Event
Role
Slot
Head
Fragment
Zone
Origin
Diagnostic
Format
Environment
Phase
Trait
Protocol
Region
```

The architecture is:

```text
Lua syntax produces a Shape.
A Shape arrives through a Channel as an Event.
A Slot accepts or rejects Events.
A Role normalizes Event values.
A Head sequences Slots.
A Fragment stores role-tagged reusable values.
A Zone partitions multi-language family values.
An Origin explains where construction happened.
Diagnostics report failed Events with Slot/Role context.
Format renders evaluated values.
Environment exposes language exports.
Phases analyze or transform normalized values.
Traits package reusable behavior.
Protocols define object behavior families.
Regions define pull-shaped control machines with named exit protocols.
```

## Surfaces

LLB has three public surfaces.

```text
Authoring surface
  Used by normal DSL users.
  Example: fn. add { a [i32] } [i32] { ret (a) }

Grammar surface
  Used by language authors.
  Example: g.head. fn { g.slot. name [g.name], ... }

Meta-protocol surface
  Used by language workbench authors and advanced metaprogrammers.
  Example: protocols, traits, channels, events, modes, provenance.
```

All three are public. The meta-protocol surface is sharp, but supported and
inspectable.

The rule is:

```text
Expose power.
Name the danger.
Keep the default path simple.
```

## Shape

A shape is the raw authoring structure Lua gives to LLB.

Examples:

```lua
fn. add
x [i32]
ret (x)
{ a [i32], b [i32] }
{ name = "memory", min = 1 }
product { x [i32] } .. product { y [i32] }
```

Shape is pre-semantic. A table is not inherently a product, body, fill map, or
protocol. It becomes meaningful through a role.

Shape information should be computed on demand, not allocated for every value.

Canonical shape names:

```text
nil
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

Public API:

```lua
llb.shape_of(value)
llb.describe_shape(value)
llb.is_shape(value, "array_table")
```

## Channel

A channel is how Lua syntax delivered a value to LLB.

Channels are the syntax physics of parserless LLB authoring.

Canonical channels:

```text
index:name       -- fn. add
index:type       -- [i32], ptr [u8]
index:value      -- head [computed]
call:none        -- ret ()
call:value       -- ret (x)
call:table       -- { ... }
call:many        -- f(a, b, c)
operator:concat  -- ..
operator:choice  -- +
operator:decorate -- *
env:lookup       -- unknown name becomes symbol/name token
env:write        -- assignment in managed environment
```

Public channel table:

```lua
llb.channel.index_name
llb.channel.index_type
llb.channel.index_value
llb.channel.call_none
llb.channel.call_value
llb.channel.call_table
llb.channel.call_many
llb.channel.operator_concat
llb.channel.operator_choice
llb.channel.operator_decorate
llb.channel.env_lookup
llb.channel.env_write
```

Grammar sugar maps to explicit channels.

```lua
g.slot. result [g.type] { optional = true }
```

is sugar for a slot accepting `index:type` with role `type`.

## Event

Event is the runtime atom between Lua syntax and LLB semantics.

A channel alone is too abstract. A shape alone is passive. A slot receives an
event:

```lua
{
  __llb_tag = "Event",
  channel = llb.channel.call_table,
  value = {...},
  argc = 1,
  origin = origin,
  shape = llb.shape_of(value),
}
```

Heads should consume events, not loose `(action, value, argc, origin)` tuples.

This makes diagnostics precise:

```text
head fn expected slot result [type] via index:type
got call:table with array_table
```

Public API:

```lua
llb.event(channel, value, opts)
llb.describe_event(event)
```

## Role

A role assigns meaning to a shape carried by an event.

Examples:

```text
product
body
decls
protocol
fillmap
type
expr
name
attrs
```

Roles are the reusable semantic units. Heads should stay thin.

A role may declare:

```text
kind
accepted input shapes/channels
normalizer
checker
fragment algebra
item role
payload role
diagnostic policy
format policy
description metadata
```

Example:

```lua
g.role. product {
  kind = "product",
  algebra = "product",
  unique_names = true,

  region = llb.role_region. ProductRole ["role_items"] (function(lang, ctx, value)
    return gen, param, state
  end),

  check = function(ctx, fields)
    ctx:reject_duplicate_names(fields)
  end,

  format = function(fields, f)
    return f:braced_list(fields)
  end,
}
```

Role hooks are preferred over duplicated head behavior.

## Slot

A slot is a position in a head. A slot accepts events through channels and
normalizes the event value through a role.

Canonical slot record:

```lua
{
  name = "result",
  role = "type",
  channels = { llb.channel.index_type },
  optional = true,
  default = nil,
  label = "result type",
}
```

Sugar remains supported:

```lua
g.slot. result [g.type] { optional = true }
```

Slot diagnostics must be channel-aware:

```text
fn. add expected result type through [] before body
because head fn declares slot result [type] via channel index:type
```

LLB rejects ambiguous adjacent optional slots at define time when their channels
overlap. Staged construction is greedy and does not backtrack; ambiguous grammar
must fail loudly.

## Head

A head is a staged constructor.

Example:

```lua
fn. add
  { a [i32], b [i32] }
  [i32]
  {
    ret (a + b),
  }
```

A head is an event machine:

```text
name
slots
traits
emit
check
format
lsp/index hooks
```

Runtime stages should store:

```lua
events[slot_name]
raw[slot_name]
fields[slot_name]
origins[slot_name]
```

`raw` remains useful, but the canonical consumption record is the event.

Example declaration:

```lua
g.head. fn {
  g.trait. named_declaration,

  g.slot. name   [g.name],
  g.slot. params [g.product],
  g.slot. result [g.type] { optional = true },
  g.slot. body   [g.body],

  emit = function(n, lang)
    return lang.ast.fn(n)
  end,
}
```

## Fragment

A fragment is a role-tagged reusable DSL value.

Fragments are first-class and array-like:

```lua
fragment.role
fragment.items
fragment.origin
fragment.algebra
fragment.role_spec
#fragment
tostring(fragment)
fragment:describe()
fragment:format(opts)
```

Fragment algebra:

```text
product/list .. product/list       -> append
sum/protocol + sum/protocol        -> choice
sum/protocol * product             -> decorate alternatives
product * sum/protocol             -> decorate alternatives
```

Examples:

```lua
local xy =
  product { x [i32] }
  .. product { y [i32] }

local exits =
  conts { ok {} }
  + conts { err { code [i32] } }

local located_errors =
  conts { eof {}, syntax {} }
  * product { pos [index] }
```

Invalid algebra fails loudly:

```lua
product { a [i32] } + product { b [i32] } -- wrong operator
product { a [i32] } .. conts { ok {} }    -- role mismatch
conts { ok {} } + conts { ok {} }         -- duplicate alternative
```

The preferred splice marker is `_`:

```lua
struct. Point {
  _(xy),
}
```

`spread(value)` remains the explicit fallback.

## Zone

A zone is a first-class family partition:

```lua
return {
  lalin {
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

Zones carry `family`, `member`, `name`, `role`, `items`, `origin`, and optional
metadata. They are values, not lexical scopes.

Projection is language-owned: Lalin consumes Lalin zones and LLPVM
consumes LLPVM zones. Same-language zones concatenate with `..`; mixed zones
compose into a family bundle.

Public API:

```lua
llb.zone_head { family = "lalin", member = "lalin.dsl", name = "lalin", role = "decls" }
llb.zone { family = "lalin", member = "lalin.dsl", name = "lalin", role = "decls", items = { ... } }
llb.family_bundle { family = "lalin", zones = { ... } }
llb.describe_zone(zone)
llb.describe_family_bundle(bundle)
```

## Origin

An origin records where and why a value was created or consumed.

Origins are provenance chains, not just file/line locations.

Minimum useful shape:

```lua
{
  __llb_tag = "Origin",
  kind = "factory-call",
  file = "demo.lua",
  line = 12,
  text = "...",

  parent = parent_origin,

  generated_by = {
    name = "make_vec",
    origin = call_origin,
  },

  consumed_by = {
    head = "fn",
    slot = "params",
    role = "product",
    channel = "call:table",
  },
}
```

Existing factory convention:

```lua
local origin = llb.here("make_add")
local value = llb.at(origin, name)
local decl = fn:at(origin) [llb.at(origin, name)] { ... }
```

Public API:

```lua
llb.origin_of(value)
llb.provenance(value)
llb.render_origin(origin)
llb.render_provenance(value)
```

Diagnostics should be able to explain:

```text
x [i32]
was captured as a product field
because it appeared inside:
  slot params of head fn
  role product
  module Demo
```

## Diagnostic

Diagnostics are part of the model, not an afterthought.

A diagnostic should be able to reference events, slots, roles, heads, origins,
and related provenance.

Example:

```lua
ctx:error {
  code = "E_BAD_SLOT",
  message = "expected result type before body",
  event = event,
  slot = slot,
  role = role,
  head = head,
}
```

Rendering should understand those structured fields and produce channel-aware
messages.

## Format

Formatting is semantic pretty-printing for evaluated LLB values.

It is not Lua token formatting and does not preserve arbitrary comments or host
metaprogram shape.

The document algebra remains the right abstraction:

```lua
local d = llb.doc

return d.group {
  "fn. ",
  name,
  " ",
  params,
  " ",
  body,
}
```

Format hooks should exist at role and head levels:

```lua
role.format(value, f)
head.format(node, f)
```

Dispatch order:

```text
value metatable __llb_format hook
head format hook
role format hook
language formatter table
generic fallback
literal fallback
```

## Environment

Environment is a first-class atom.

LLB-managed authoring environments are represented by `UseSession`.

Scopes:

```text
permanent -- install into target until close or process end
scoped    -- temporary global install, caller owns cleanup
env       -- isolated environment, no global mutation
```

API:

```lua
local session = Lang:family():use {
  scope = "env",
  base = "safe",
  strict = true,
  auto_names = true,
}

session.env
session:close()
```

`Lang:use`, `Lang:env`, `Lang:loadstring`, and `llb.use(Lang, opts)` are
family delegation helpers. They do not create a language-only authoring world.

Unknown identifiers are always generic LLB symbols:

```text
unknown Lua identifier -> llb.Symbol
```

This is a language-workbench invariant, not a per-language customization point.
Family-compatible languages must normalize `llb.Symbol` / `llb.Name` at their
semantic boundaries. Private name classes may exist as explicit helper values,
but they are not the auto-name substrate.

Inspection:

```lua
session:installed()
session:skipped()
session:auto_created()
session:describe()
```

Loaders, formatters, LSP, and tests should prefer `scope = "env"`.

## Family

Family is the unit of authoring coherence.

The smallest family is the `llb` singleton. Every other family includes it and
therefore shares the same `llb`, `N`, `_`, `spread`, process helpers, origin
helpers, and generic symbol substrate.

Every language belongs to a family. A single-language family is valid, but it is
really `llb + language`. Language-level `use`, `env`, and loading delegate
through that family.

Families compose authoring universes:

```text
family .. family  -> checked composition
family + family   -> checked composition
family - member   -> remove a language/capability member
family.only {...} -> projection
family.prefer {...} -> collision preference overlay
```

Family methods use dot syntax only:

```lua
family.use { scope = "env" }
family.only { "lalin.types" }
family.prefer { task = "llpvm.dsl" }
```

Family algebra operates on compatibility contracts:

```text
exports
capabilities
reserved names
shared protocols
symbol normalization
format/process/diagnostic interop
```

It is not a table merge.

## Phase

A phase is a named operation over normalized values.

Examples:

```text
normalize
bind
check
typecheck
lower
format
index
emit
```

Public shape:

```lua
g.phase. bind {
  after = "normalize",
  run = function(ctx, unit)
    ...
  end,
}
```

A phase context should provide:

```lua
ctx:error { ... }
ctx:warning { ... }
ctx:scope()
ctx:typeof(expr)
ctx:resolve(name)
ctx:index_symbol(...)
ctx:emit(...)
```

The phase system is generic. Lalin owns Lalin-specific type rules and
lowering.

## Trait

A trait is a declarative behavior bundle applied at define time.

Traits are not inheritance. They package repeated behavior.

Examples:

```text
named_declaration
scoped
source_indexed
formattable
hoverable
check_duplicates
traceable
origin_tracked
lsp_symbol
```

Trait contract:

```lua
g.trait. named_declaration {
  apply = function(lang, target, spec)
    ...
  end,
}
```

Traits may add:

```text
check hooks
format hooks
lsp hooks
scope hooks
description metadata
```

Example use:

```lua
g.head. fn {
  g.trait. named_declaration,
  g.slot. name [g.name],
  g.slot. params [g.product],
  g.slot. result [g.type] { optional = true },
  g.slot. body [g.body],
}
```

Traits should exist only when they remove real duplication or create visible
user-facing consistency.

## Protocol

A protocol defines a behavior family for LLB objects.

Protocols are public, but they are not magic inheritance.

Definitive rule:

```text
Protocols manufacture immediate metatables.
They do not rely on metatable inheritance.
```

Lua does not inherit metamethods through metatable metatables. Therefore every
VM-visible metamethod must be installed directly on the immediate metatable.

Example protocol description:

```lua
g.protocol. fragment {
  operators = {
    concat = llb.concat,
    choice = llb.choice,
    decorate = llb.decorate,
  },
}
```

Public doctrine:

```text
Raw metatable mutation is allowed by Lua.
LLB-supported protocol construction is preferred.
LLB validates protocol-generated metatables.
```

Inspection:

```lua
llb.describe_protocol("fragment")
llb.validate_protocol(protocol)
llb.describe_metatable(mt)
```

## Modes

Modes are selected on environment, load, or analysis calls.

Canonical modes:

```text
fast
  minimal provenance and instrumentation

debug
  full provenance and richer diagnostics

lsp
  full provenance, indexes, incomplete-stage retention

format
  formatting metadata retained where useful

trace
  channel/event protocol exits recorded
```

API:

```lua
Lang:use { mode = "lsp" }
Lang:analyze_string(src, name, { mode = "debug" })
```

Modes are overlays. They must not duplicate grammar declarations.

## Introspection

LLB should be self-describing.

Public API:

```lua
llb.describe(value)
llb.describe_shape(value)
llb.describe_event(event)
llb.describe_head(lang, name)
llb.describe_role(lang, name)
llb.describe_fragment(fragment)
llb.describe_protocol(name_or_protocol)
llb.provenance(value)
llb.render_provenance(value)
```

Example head description:

```lua
{
  tag = "Head",
  name = "fn",
  protocol = "staged_head",

  slots = {
    {
      name = "name",
      role = "name",
      channels = { "index:name" },
    },
    {
      name = "params",
      role = "product",
      channels = { "call:table" },
    },
    {
      name = "result",
      role = "type",
      channels = { "index:type" },
      optional = true,
    },
    {
      name = "body",
      role = "body",
      channels = { "call:table" },
    },
  },

  traits = {
    "named_declaration",
    "formattable",
  },
}
```

This powers documentation, debug tooling, LSP hover, grammar visualization,
tests, and diagnostics.

## Non-goals

LLB must not become:

```text
a parser
a Lalin semantic engine
a backend
a CLOS clone
a general-purpose class system
a source-to-source Lua rewriter
```

LLB remains:

```text
a parserless language-event substrate
with explicit shape, channel, event, role, slot, head, fragment, origin,
diagnostic, format, environment, process, phase, trait, and protocol atoms
```

## Doctrine

The real atoms of LLB are not metatables.

Metatables are how Lua lets LLB implement the atoms.

The final architecture is:

```text
Shape comes through Channel as Event.
Slot receives Event.
Role gives Event.value meaning.
Head sequences Slots.
Fragment composes role-values.
Origin explains all construction.
Diagnostic reports failed Events with semantic context.
Format renders evaluated values.
Environment exposes the language.
Process streams long-running language work as typed events.
Phase performs language work.
Trait packages reusable behavior.
Protocol defines behavior families.
```

The meta layer exists to make the common authoring line easier to define,
inspect, diagnose, format, and extend:

```lua
fn. add { a [i32], b [i32] } [i32] {
  ret (a + b),
}
```
