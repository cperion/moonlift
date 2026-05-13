# Tape × Memory Machine Design

The current experiment is `machine.mlua`.

Machine state is explicit in block parameters, not hidden in a mutable state pointer. This makes the control graph and state transitions visible.

## State tuple

The current state carried between blocks is:

```text
pc        current tape position
tape_len  number of tape events observed
acc       concrete memory/state summary
live      live-object summary
phase     current submachine selector
fuel      termination guard
```

## Regions

The current machine has three reusable regions:

- `inv` — checks product-space invariants on the state tuple.
- `exec` — decodes and executes one tape operation.
- `gc` — performs the GC projection step.

The top-level function wires them through blocks:

```text
start -> dispatch -> mode -> exec/gc -> recv -> dispatch
                         \-> done
```

## Tape language

Current opcodes:

```text
0 imm   add immediate to acc
1       add one to acc
2       allocate/live++
3       drop root/live-- and enter GC phase
4       GC hint / enter GC phase
9       halt
```

## Product-space invariant

Each step updates two projections:

- tape projection: `tape_len` and phase/fact movement,
- memory projection: `acc`, `live`, and `pc`.

A transition is valid only if:

- `fuel > 0`,
- `pc >= 0`,
- `tape_len >= 0`,
- `live >= 0`,
- all state changes are explicit in jump arguments.

## Why this shape matters

This version is useful because it makes state flow visible. It is a typed control/state skeleton for exploring the product-space idea.
