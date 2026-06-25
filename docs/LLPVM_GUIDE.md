# LLPVM Guide

LLPVM is the low-level VM/task member of the Lalin family. It is not a second
compiler architecture. It owns bytecode images, worlds, tapes, machines,
phases, task specs, and run records.

Use it when a language or tool needs a portable typed VM boundary rather than a
native Lalin function.

## Public Module

```lua
local llpvm = require("llpvm")
```

In the Lalin family environment:

```lua
local lalin = require("lalin")
lalin.family.use()

return llpvm {
  llpvm.task. compile {
    llpvm.input [ll.i32],
    llpvm.output [ll.i32],
    llpvm.event. progress [ll.i32],
  },
}
```

## Canonical Surface

World:

```lua
llpvm.world. Demo {
  llpvm.symbol. add,
  llpvm.record. Pair {
    left [ll.i32],
    right [ll.i32],
  },
}
```

Program:

```lua
llpvm.program. image {
  llpvm.root. main,
  llpvm.tape. code {
    -- bytecode words or typed instruction records
  },
}
```

Task:

```lua
llpvm.task. validate {
  llpvm.input [llpvm.image],
  llpvm.output [llpvm.report],
  llpvm.event. diagnostic [llpvm.diagnostic],
}
```

## Semantics

LLPVM owns:

- bytecode image structure
- borrowed image/runtime ABI
- world definitions
- tapes and instruction records
- machine and phase declarations
- task specs and run records
- process-backed inspection and validation

LLPVM reuses:

- LLB namespaces, fragments, origins, diagnostics, processes, and regions
- Lalin type values where native type interop is required
- LalinSchema product/sum semantics where schema-level structure is needed

## Process Shape

Validation and inspection should be process-shaped:

```text
input image
  -> event(header)
  -> event(record)
  -> diagnostic(...)
  -> done(report)
```

This lets callers stop early, stream diagnostics, or materialize a whole report
explicitly.

## Runtime Boundary

The runtime boundary is borrowed and explicit:

- buffers are passed with length and ownership policy
- bytecode images are validated before execution
- C-facing close boundaries are small and named
- handles and stores keep representation casts behind trusted APIs

Do not hide bytecode validity in callbacks or side tables. Validation facts must
be visible to the task/run model.

## Relationship To PVM

The older PVM machinery remains an implementation substrate for schema values,
interning, phase triplets, and cache boundaries. LLPVM is the public low-level
VM language. New docs and public APIs should describe LLPVM and LLB region/GPS
machinery, not a separate public PVM doctrine.

## Tests

Useful checks:

```sh
luajit tests/run.lua llpvm
luajit tests/llpvm/test_llpvm_family_use.lua
luajit tests/llpvm/test_llpvm_task_dsl.lua
luajit tests/llpvm/test_llpvm_bytecode.lua
```

## Rules

1. Bytecode images are data, not hidden closures.
2. Validation is process-shaped.
3. Task runs expose typed events.
4. Borrowed buffers must have explicit lifetime and length.
5. Product/sum semantics are reused from the family instead of reinvented.
