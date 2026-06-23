# PVM Erasure

PVM is a bootstrap phase compiler, not a permanent runtime dependency.
Generated phase code should erase the generic PVM boundary when the phase shape
is explicit enough to rewrite safely.

Current tool:

```sh
luajit scripts/pvm_erase.lua lua/moonlift/source_text_apply.lua target/pvm-erased/source_text_apply.lua
```

The eraser is source-to-source. It scans Lua source, extracts balanced
`pvm.phase(...)` calls, and emits direct Lua for supported phase shapes.

Current scan status:

```text
lua/moonlift + lua/ui: 258 / 259 pvm.phase definitions erase
remaining unsupported phase: lua/moonlift/pvm.lua itself
```

Supported scalar phases:

```lua
local phase_name = pvm.phase("semantic_name", function(node, env)
  return Result(node, env)
end, { node_cache = "none", args_cache = "none" })

local result = pvm.one(phase_name(node, env))
```

and scalar cached phases when the generator is allowed to strip cache
semantics:

```lua
local phase_name = pvm.phase("semantic_name", function(node)
  return Result(node)
end)

local result = pvm.one(phase_name:triplet_uncached(node))
```

Generated scalar shape:

```lua
local schema = require("moonlift.schema_runtime")

local function phase_name(node, env)
  return Result(node, env)
end

local result = phase_name(node, env)
```

`pvm.classof`, `pvm.with`, `pvm.NIL`, and `pvm.context` become calls through
`moonlift.schema_runtime`. If unsupported `pvm.*` calls remain, the original PVM
import is preserved so partially transformed files stay runnable.

Supported dispatch-table phases:

```lua
local phase = pvm.phase("name", {
  [T.NodeA] = function(node) return pvm.once(A(node.x)) end,
  [T.NodeB] = function(node) return pvm.seq(node.items) end,
})
```

Generated dispatch shape:

```lua
local schema = require("moonlift.schema_runtime")
local erased = require("moonlift.phase_erased_runtime")

local function phase(node, ...)
  local cls = schema.classof(node)
  if cls == T.NodeA then
    return erased.once(A(node.x))
  elseif cls == T.NodeB then
    return erased.seq(node.items)
  else
    error("erased phase name: no handler for " .. tostring(cls and cls.kind or type(node)), 2)
  end
end
```

Dispatch phases return arrays. `pvm.drain(phase(...))` becomes `phase(...)`.
`pvm.one(phase(...))` becomes `erased.one(phase(...))`.
