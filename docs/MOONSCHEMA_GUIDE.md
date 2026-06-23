# MoonSchema Guide

MoonSchema is Moonlift's schema source language.

It is not a parser and it is not text ASDL. A schema file is an ordinary Lua
module that uses LLB heads to build a structured MoonSchema value.

```text
MoonSchema Lua module
  -> MoonSchema value
  -> MoonAsdl.Schema runtime projection
  -> runtime classes/builders/interning
  -> compiler phases and tools
```

`MoonAsdl` is the internal projection vocabulary. It is not the authoring API.
Use `moonlift.schema.dsl` to author schema and `moonlift.schema_projection` to
install the runtime classes into a context.

## Canonical file shape

```lua
local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonDemo {
  product. Name {
    interned,
    text [str],
  },

  sum. Expr {
    LitInt {
      variant_unique,
      raw [str],
    },

    Add {
      variant_unique,
      lhs [ty. MoonDemo.Expr],
      rhs [ty. MoonDemo.Expr],
    },
  },
}
```

The dot belongs to the keyword side: `product. Name`, `sum. Expr`,
`schema. MoonDemo`.

## Heads

```lua
schema. ModuleName { ... }
product. Name { ... }
sum. Name { ... }
alias. Name [T]
field. reserved_or_dynamic_name [T]
```

Use bare field captures when the field name is a safe unbound identifier:

```lua
text [str]
items [many [ty. MoonDemo.Item]]
```

Use `field` when the field name collides with Lua, LLB, or MoonSchema globals:

```lua
field. name [str]
field. id [ty. MoonProject.TaskId]
field. value [bool]
field. local_id [ty. MoonC.CBackendLocalId]
```

## Type slots

Builtins:

```lua
str
bool
number
any
table_ty
function_ty
nil_ty
```

Schema references are explicit:

```lua
ty. MoonCore.Name
ty. MoonType.Type
ty. MoonTree.Expr
```

Wrappers:

```lua
many [T]
optional [T]
ref [T]
id [T]
map [K] [V]
```

These wrappers are MoonSchema semantics. The current runtime class projection
maps them to the existing runtime representation:

```text
many[T]      -> list field
optional[T]  -> optional field
ref[T]       -> projected payload value
id[T]        -> projected payload value
map[K][V]    -> list of projected values in the runtime class layer
```

## Projection API

```lua
local pvm = require("moonlift.pvm")
local Projection = require("moonlift.schema_projection")

local T = pvm.context()
Projection(T)

local Core = T.MoonCore
local id = Core.Id("x")
```

For direct schema modules:

```lua
local S = require("moonlift.schema.dsl")
local module_value = require("moonlift.schema.core")
local schema_value = S.to_asdl_schema(T, { module_value })
```

## Formatting

MoonSchema is formatter-owned. Use the MoonSchema formatter output as the
canonical source shape.

```lua
local S = require("moonlift.schema.dsl")
local mod = require("moonlift.schema.project")
print(S.file_text(mod, { width = 100, indent = 2 }))
```

Do not hand-maintain a second constructor-form source. There is one source path:
MoonSchema DSL Lua modules.
