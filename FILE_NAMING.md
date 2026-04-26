# moonlift file naming discipline

Moonlift file names should mirror the ASDL vocabulary and the bottom-up phase
order.  A file name should make it obvious which ASDL module/type family or
phase boundary it owns.

This is not cosmetic.  In moonlift, the implementation order is architectural:
we complete and validate the lowest abstraction layer before moving upward.  File
names must preserve that discipline.

---

## 1. Naming rule

Use this shape:

```text
<layer>_<noun>.lua
<layer>_<verb>_<noun>.lua
<layer>_<from>_to_<to>.lua
<layer>_<noun>_<fact|decision|validate|emit>.lua
```

Where:

- `<layer>` is the ASDL module prefix without `Moon2`:
  - `core`
  - `back`
  - `type`
  - `open`
  - `bind`
  - `sem`
  - `tree`
  - `vec`
- `<noun>` is an ASDL type family name in snake case:
  - `cmd`
  - `program`
  - `scalar`
  - `binding`
  - `residence`
  - `layout`
  - `const`
  - `expr`
  - `stmt`
  - `loop`
  - `module`
- `<verb>` is the phase verb:
  - `validate`
  - `classify`
  - `gather`
  - `decide`
  - `lower`
  - `emit`
  - `replay`
  - `translate`

Good names:

```text
back_program.lua
back_validate.lua
back_to_moonlift.lua
back_emit_current.lua

type_classify.lua
type_abi_decide.lua

bind_residence_gather.lua
bind_residence_decide.lua

sem_layout_resolve.lua
sem_const_eval.lua
sem_switch_decide.lua
sem_call_decide.lua

tree_expr_type.lua
tree_stmt_type.lua
tree_module_to_back.lua

vec_loop_facts.lua
vec_loop_decide.lua
vec_to_back.lua
```

Bad names:

```text
utils.lua
helpers.lua
common.lua
compiler.lua
lower.lua
process.lua
stuff.lua
pipeline.lua        -- unless it is only a thin orchestration file
```

If a name could fit almost anywhere, it is too vague.

---

## 2. ASDL module to file prefix map

| ASDL module | File prefix | Meaning |
|---|---|---|
| `Moon2Core` | `core_` | shared atoms, ids, scalar/operator/intrinsic vocabulary |
| `Moon2Back` | `back_` | lowest executable flat command layer |
| `Moon2Type` | `type_` | type spine, type classes, ABI-facing type facts |
| `Moon2Open` | `open_` | slots, fragments, fills, validation, rewrite/open-code facts |
| `Moon2Bind` | `bind_` | binding/value-ref/residence/env facts and decisions |
| `Moon2Sem` | `sem_` | layout, const, call, switch, semantic decision facts |
| `Moon2Tree` | `tree_` | recursive Expr/Stmt/Place/Loop/Item/Module spines |
| `Moon2Vec` | `vec_` | vector/code-shape facts, proofs, rejects, decisions, IR |

Do not put `Moon2Back` implementation in a `tree_` file or `Moon2Tree` typing in
a `sem_` file.  If a file crosses a boundary, name the boundary explicitly:

```text
tree_to_back.lua
vec_to_back.lua
back_to_moonlift.lua
```

---

## 3. One file owns one ASDL question

A file should correspond to one phase question or one ASDL family.

Examples:

```text
back_validate.lua
Question: is a Moon2Back.BackProgram structurally valid?
Input:    Moon2Back.BackProgram
Output:   validation facts / errors

bind_residence_decide.lua
Question: should this binding be value, stack, or cell resident?
Input:    Moon2Bind.Binding + gathered facts
Output:   Moon2Bind.ResidenceDecision

sem_switch_decide.lua
Question: are switch keys const-preservable or expr/fallback?
Input:    Moon2Tree.ExprSwitch / switch facts
Output:   Moon2Sem.SwitchDecision

vec_loop_facts.lua
Question: what vector-relevant facts does this loop/body expose?
Input:    Moon2Tree.Loop
Output:   Moon2Vec.VecLoopFacts
```

If a file answers two unrelated questions, split it.

---

## 4. Bottom-up file order

Implementation should appear in this order:

```text
core_*.lua
back_*.lua
type_*.lua
open_*.lua
bind_*.lua
sem_*.lua
tree_*.lua
vec_*.lua
```

Do not start broad `tree_` or parser files before `back_` has enough coverage to
execute basic flat programs.  Higher layers exist to feed lower layers.  If a
higher layer is awkward to implement, first ask whether the lower-layer ASDL
contract is missing a fact or decision.

---

## 5. Phase file naming

PVM phase files should include the phase verb in the file name.

| Phase kind | File pattern | Example |
|---|---|---|
| fact gathering | `<layer>_<noun>_facts.lua` | `vec_loop_facts.lua` |
| classification | `<layer>_<noun>_classify.lua` | `type_classify.lua` |
| decision | `<layer>_<noun>_decide.lua` | `sem_switch_decide.lua` |
| validation | `<layer>_validate.lua` / `<layer>_<noun>_validate.lua` | `back_validate.lua` |
| lowering | `<from>_to_<to>.lua` | `tree_to_back.lua` |
| replay/bridge | `<from>_to_<external>.lua` | `back_to_moonlift.lua` |

A `pvm.phase("...")` name should match the file's question.

Example:

```lua
-- file: sem_switch_decide.lua
local decide_switch = pvm.phase("moon2_sem_switch_decide", ...)
```

---

## 6. Test file naming

Tests mirror implementation files:

```text
test_<file_without_lua>.lua
```

Examples:

```text
test_back_validate.lua
test_back_to_moonlift.lua
test_type_classify.lua
test_bind_residence_decide.lua
test_sem_switch_decide.lua
test_vec_loop_facts.lua
```

Vertical slice tests should name the lowest layer they validate:

```text
test_back_add_i32.lua
test_back_branch.lua
test_tree_to_back_add_i32.lua
```

---

## 7. Project-management files

If/when moonlift adds ASDL-backed project management, use the `project_` prefix:

```text
project_asdl.lua
project_apply.lua
project_ready_facts.lua
project_report.lua
```

These files manage the rewrite plan; they must not own compiler semantics.

---

## 8. Escape hatch rule

A generic name is allowed only if the file is a thin facade that re-exports or
orchestrates precise files.  Its header must say so.

Allowed:

```text
source.lua       -- public facade over parse/type/lower files
pipeline.lua     -- thin orchestration only, no semantic decisions
```

Not allowed:

```text
pipeline.lua     -- contains hidden lowering/type/storage decisions
helpers.lua      -- contains semantic branches
```

If it makes a semantic decision, its file name must name the ASDL fact/decision
it produces.
