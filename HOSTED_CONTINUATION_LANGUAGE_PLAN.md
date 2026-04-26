# Moonlift Hosted Continuation Language Plan

Status: implementation plan / design target.

This document defines the intended hosted Moonlift metaprogramming language:

```text
Lua as the staging language
  + Moonlift typed continuation regions as the object language
  + ASDL/PVM as the semantic representation
```

The goal is **not** to clone Terra quotes. Terra is useful mainly as proof that
Lua-hosted staged programming can feel good. Moonlift's real primitive is
stronger:

```text
typed regions + typed blocks + typed jumps + explicit continuation parameters
```

Hosted syntax must expose those primitives directly.

---

## 1. Core thesis

Moonlift should not be quote-centric.

It should be **continuation-centric**.

The central object-language values are:

```text
func      closed compile unit
module    collection of compile units
region    typed control graph / region fragment
entry     entry continuation with initialized parameters
block     typed local continuation
jump      typed tail call to a continuation
yield     exit a region expression
return    exit a function
emit      compile-time fragment expansion/fusion
cont(...) continuation/block parameter type
@{...}    host Lua antiquote/splice
```

A block is a typed continuation:

```moonlift
block found(pos: i32)
    yield pos
end
```

A jump is a typed tail call:

```moonlift
jump found(pos = i)
```

A reusable region fragment should be parameterized by continuation values:

```moonlift
region scan_until(
    p: ptr(u8),
    n: i32,
    target: i32;

    hit: cont(pos: i32),
    miss: cont(pos: i32)
)
entry scan(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if zext<i32>(p[i]) == target then jump hit(pos = i) end
    jump scan(i = i + 1)
end
end
```

A consumer fuses it with local blocks:

```moonlift
func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32

    entry start()
        emit scan_until(p, n, target; hit = found, miss = not_found)
    end

    block found(pos: i32)
        yield pos
    end

    block not_found(pos: i32)
        yield -1
    end

    end
end
```

No runtime callbacks. No runtime function pointers. No source-level JSON/parser
pollution. This is compile-time CPS over typed block/jump regions.

---

## 2. Architectural invariants

### 2.1 ASDL remains the semantic truth

Hosted syntax is a frontend only.

All meaningful compiler distinctions must lower into explicit ASDL values:

```text
Moon2Open
Moon2Tree
Moon2Type
Moon2Bind
Moon2Sem
Moon2Back
```

The hosted language must not introduce hidden semantics in:

- string hacks
- opaque Lua tables
- mutable captured state
- Rust-side ad hoc IR
- parser-only magic

### 2.2 PVM phases remain the semantic boundaries

Hosted parsing may produce ASDL directly or through the existing source parser,
but semantic questions must still flow through PVM phase boundaries.

Examples:

```text
parse hosted source -> hosted forms / source spans
lower hosted forms -> Moon2Open/Moon2Tree ASDL
expand open fragments -> closed tree
validate open fragments -> explicit issues
validate control graph -> explicit decisions/rejects
lower tree -> flat backend commands
```

### 2.3 Syntax must map to primitives

Every surface form needs a direct semantic mapping.

| Hosted form | Semantic target |
|---|---|
| `func` | `Moon2Tree.Func*` or `FuncOpen` |
| `module` | `Moon2Tree.Module` or open module value |
| `region -> T ... end` | `ExprControl(ControlExprRegion)` |
| `region name(...) ... end` | `Moon2Open.RegionFrag` / region value |
| `entry` | `EntryControlBlock` |
| `block` | `ControlBlock` / typed continuation value |
| `jump` | `StmtJump` with `JumpArg*` |
| `yield` | `StmtYield*` |
| `emit expr_frag(...)` | `ExprUseExprFrag` |
| `emit region_frag(...; ...)` | `StmtUseRegionFrag` |
| `cont(...)` | continuation/block interface type; likely new ASDL facet |
| `@{...}` | explicit host splice/fill/literal/type/fragment insertion |

### 2.4 Quote syntax is not the core

Current `host_quote.lua` proves custom keywords and hosted staging. It is a
bootstrap frontend.

Long-term layering:

```text
host_quote.lua / hosted parser
  -> code values / direct ASDL
  -> PVM compiler phases
```

Not:

```text
host_quote.lua
  -> permanent source-string semantics
```

---

## 3. User-facing hosted API

### 3.1 Host file model

Hosted files use a Moonlift-hosted Lua dialect, tentatively `.mlua`:

```bash
luajit moonlift/run_mlua.lua file.mlua
```

A hosted file is mostly Lua, with recognized Moonlift forms:

```text
func ... end
module ... end
region ... end
expr ... end
@{...}
```

Ordinary Lua still stages generation:

```lua
local function make_addk(k)
    return func addk(x: i32) -> i32
        return x + @{k}
    end
end

return make_addk(7)
```

### 3.2 Function quote

```moonlift
func add1(x: i32) -> i32
    return x + 1
end
```

Returns a hosted `FuncValue` / `FuncQuote` Lua value.

Expected Lua use:

```lua
local add1 = func add1(x: i32) -> i32
    return x + 1
end

local c_add1 = add1:compile()
assert(c_add1(41) == 42)
c_add1:free()
```

### 3.3 Module quote

```moonlift
module
export func add1(x: i32) -> i32
    return x + 1
end

export func mul2(x: i32) -> i32
    return x * 2
end
end
```

Expected Lua use:

```lua
local cm = m:compile()
local add1 = cm:get("add1")
assert(add1(41) == 42)
cm:free()
```

### 3.4 Inline expression control region

Use `region -> T` where a value expression is required:

```moonlift
func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32

    entry scan(i: i32 = 0)
        if i >= n then yield -1 end
        if zext<i32>(p[i]) == target then yield i end
        jump scan(i = i + 1)
    end

    end
end
```

This is sugar over existing `control -> T` / `block` machinery, but the hosted
language should standardize on `region` to make the object model clear.

### 3.5 Local blocks as continuations

```moonlift
func classify(x: i32) -> i32
    return region -> i32

    entry start()
        if x < 0 then jump negative(value = x) end
        if x == 0 then jump zero() end
        jump positive(value = x)
    end

    block negative(value: i32)
        yield -1
    end

    block zero()
        yield 0
    end

    block positive(value: i32)
        yield 1
    end

    end
end
```

### 3.6 Region fragment with continuation parameters

Reusable region fragments should use semicolon-separated runtime vs control
parameters:

```moonlift
region scan_until(
    p: ptr(u8),
    n: i32,
    target: i32;

    hit: cont(pos: i32),
    miss: cont(pos: i32)
)
entry scan(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if zext<i32>(p[i]) == target then jump hit(pos = i) end
    jump scan(i = i + 1)
end
end
```

The fragment itself is a hosted Lua value.

### 3.7 Fragment fusion with `emit`

```moonlift
func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32

    entry start()
        emit scan_until(p, n, target; hit = found, miss = not_found)
    end

    block found(pos: i32)
        yield pos
    end

    block not_found(pos: i32)
        yield -1
    end

    end
end
```

Semantics:

```text
emit scan_until(...; hit = found, miss = not_found)
  -> StmtUseRegionFrag(...)
  -> open expansion resolves to concrete statements/jumps
```

`emit` must be visibly compile-time. Do not make region fragments look like
runtime calls.

### 3.8 Expression fragments

```moonlift
expr abs_i32(x: i32) -> i32
    select(x < 0, -x, x)
end
```

Use in expressions:

```moonlift
func foo(x: i32) -> i32
    return emit abs_i32(x) + 1
end
```

Semantics:

```text
emit abs_i32(x)
  -> ExprUseExprFrag(...)
  -> open expansion resolves to expression body
```

### 3.9 Type and value antiquote

Lua values can be staged into Moonlift code:

```lua
local function make_find_byte(target)
    return func find(p: ptr(u8), n: i32) -> i32
        return region -> i32
        entry scan(i: i32 = 0)
            if i >= n then yield -1 end
            if zext<i32>(p[i]) == @{target} then yield i end
            jump scan(i = i + 1)
        end
        end
    end
end
```

Type staging should also work:

```lua
local function make_sum(T)
    return func sum(xs: ptr(@{T}), n: i32) -> @{T}
        return region -> @{T}
        entry loop(i: i32 = 0, acc: @{T} = 0)
            if i >= n then yield acc end
            jump loop(i = i + 1, acc = acc + xs[i])
        end
        end
    end
end
```

Antiquote must lower to explicit ASDL forms:

```text
literal insertion
slot fill
type insertion
fragment insertion
continuation insertion
```

It must not become hidden capture.

---

## 4. Continuation parameter model

### 4.1 Why continuation parameters matter

The powerful reusable abstraction is not a parser/state-machine DSL.

It is compile-time CPS over typed blocks:

```text
fragment receives continuations
fragment jumps directly to them
consumer supplies local blocks
expansion fuses the control graph
```

This supports:

- byte parsers
- regex/NFA/decision trees
- protocol decoders
- vector loop skeletons
- early-exit scans
- error/success routing
- parser combinators without runtime callbacks

### 4.2 Surface type

Tentative syntax:

```moonlift
cont()
cont(pos: i32)
cont(pos: i32, value: i32)
```

These are compile-time/control parameters, not runtime values.

They probably should not be ordinary `Moon2Type.Type` values forever. They are a
phase/interface facet for region fragments.

### 4.3 Possible ASDL addition

Current `Moon2Open.RegionSlot` and `SlotRegion` can represent region holes, but
continuation parameters are more specific.

Likely needed:

```asdl
ContParam = (string key, string name, Moon2Tree.BlockParam* params) unique
ContArg = (Moon2Open.ContParam param, Moon2Tree.BlockLabel target) unique
```

or a more layer-explicit variant:

```asdl
ContinuationSlot = (string key, string pretty_name, Moon2Tree.BlockParam* params) unique
SlotContinuation(Moon2Open.ContinuationSlot slot)
SlotValueContinuation(Moon2Tree.BlockLabel label)
```

Do **not** add this until implementing `emit region_frag(...; hit = block)`
requires it. First classify the lowerable shape.

### 4.4 Validation questions

For every continuation parameter / block argument binding:

- Does the continuation exist?
- Does the supplied block exist?
- Do parameter names match?
- Are required args supplied?
- Are extra args rejected?
- Do types match?
- Is a continuation used only in compatible region scope?
- Are generated labels hygienically rebased?

These should produce explicit reject/issue ASDL values, not raw Lua errors after
parsing succeeds.

---

## 5. Implementation layers

### 5.1 Current bootstrap layer

Existing file:

```text
moonlift/lua/moonlift/host_quote.lua
```

Current role:

```text
hosted syntax scanner
  -> quote.lua generated Lua
  -> existing Moonlift source parser
```

Keep this as the bootstrap path while syntax evolves.

### 5.2 Hosted parser layer

Future file candidates:

```text
moonlift/lua/moonlift/host_parse.lua
moonlift/lua/moonlift/host_lower.lua
moonlift/lua/moonlift/host_splice.lua
```

Responsibilities:

- parse outer hosted Lua enough to locate Moonlift forms
- parse Moonlift hosted forms with spans
- parse antiquote boundaries robustly
- preserve source maps for generated Lua and Moonlift diagnostics
- lower hosted forms to explicit Lua calls / ASDL constructors

### 5.3 Code value layer

Future file candidates:

```text
moonlift/lua/moonlift/type_values.lua
moonlift/lua/moonlift/tree_expr_values.lua
moonlift/lua/moonlift/tree_region_values.lua
moonlift/lua/moonlift/open_fragment_values.lua
```

Purpose:

```text
Lua values wrapping typed ASDL objects and enforcing shape at construction time
```

Core values:

```text
TypeValue
ExprValue<T>
PlaceValue<T>
BlockValue<params>
RegionValue<result>
ExprFragValue
RegionFragValue
FuncValue
ModuleValue
```

Hosted syntax should eventually lower to these values or directly to the same
ASDL these values create.

### 5.4 Open expansion layer

Existing files:

```text
moonlift/lua/moonlift/open_expand.lua
moonlift/lua/moonlift/open_validate.lua
moonlift/lua/moonlift/open_rewrite.lua
```

Needed work:

- make `ExprUseExprFrag` expansion executable enough for `emit expr_frag(...)`
- make `StmtUseRegionFrag` expansion executable enough for `emit region_frag(...)`
- rebase generated labels/bindings hygienically
- represent continuation bindings explicitly
- validate unfilled slots/fragments before typecheck/lower

### 5.5 Tree/typecheck/control layer

Existing files:

```text
moonlift/lua/moonlift/tree_typecheck.lua
moonlift/lua/moonlift/tree_control_facts.lua
moonlift/lua/moonlift/tree_to_back.lua
```

Needed work:

- typecheck expanded region fragments
- check jump arg names/types after fragment fusion
- reject invalid continuation wiring explicitly
- ensure no open forms reach backend lowering
- preserve current fast block/jump lowering

### 5.6 Runner/session layer

Existing files:

```text
moonlift/run_mlua.lua
moonlift/lua/moonlift/host_quote.lua
```

Future shape:

```lua
local Host = require("moonlift.host")
local chunk = Host.loadfile("file.mlua")
local result = chunk(...)
```

Later with owned/state-aware LuaJIT integration:

```lua
local sess = ml.session()
local f = sess:compile(func_value)
f(...)
```

But this is optional. Parser/primitive semantics do not depend on owning
`lua_State*` yet.

---

## 6. Detailed lowering targets

### 6.1 `func`

Surface:

```moonlift
func name(params...) -> result
    body...
end
```

Initial lowering:

```text
source string -> Parse.parse_module -> FuncQuote
```

Final lowering:

```text
HostFuncQuote
  -> Moon2Tree.FuncLocal / FuncExport / FuncOpen
```

### 6.2 `module`

Surface:

```moonlift
module
    items...
end
```

Initial lowering:

```text
source string -> Parse.parse_module -> ModuleQuote
```

Final lowering:

```text
HostModuleQuote -> Moon2Tree.Module / open module value
```

### 6.3 inline `region -> T`

Surface:

```moonlift
region -> i32
entry loop(i: i32 = 0)
    ...
end
end
```

Lowering:

```text
ExprControl(
  ControlExprRegion(
    region_id,
    result_ty,
    EntryControlBlock(...),
    ControlBlock* ...
  )
)
```

### 6.4 named `region` fragment

Surface:

```moonlift
region scan_until(runtime_params ; cont_params)
entry ...
end
end
```

Lowering target:

```text
Moon2Open.RegionFrag(
  params = OpenParam* for runtime params,
  open = OpenSet(... continuation slots/imports ...),
  body = Stmt* or control region statement/expression body
)
```

This likely needs refinement because a region fragment with multiple blocks is
not just `Stmt*`; it is naturally a control region body/facet. We should adjust
ASDL only after confirming the exact lowerable shape.

### 6.5 `emit` region fragment

Surface:

```moonlift
emit scan_until(p, n, target; hit = found, miss = not_found)
```

Lowering target:

```text
StmtUseRegionFrag(
  h,
  use_id,
  frag,
  args,
  fills
)
```

Continuation arguments may require new slot binding kinds.

### 6.6 `emit` expression fragment

Surface:

```moonlift
emit abs_i32(x)
```

Lowering target:

```text
ExprUseExprFrag(
  h,
  use_id,
  frag,
  args,
  fills
)
```

---

## 7. Diagnostics and errors

### 7.1 Parse-time diagnostics

Hosted parser should report:

- unterminated hosted form
- malformed parameter list
- malformed `@{...}`
- malformed `emit`
- unexpected top-level hosted keyword
- ambiguous `module`/Lua identifier case

### 7.2 Open validation diagnostics

Open validation should report:

- unfilled expression slots
- unfilled region slots
- unfilled continuation slots
- unexpanded expression fragments
- unexpanded region fragments
- wrong number of fragment args
- wrong continuation binding names

### 7.3 Control validation diagnostics

Control validation should report:

- duplicate blocks
- missing jump targets
- duplicate jump args
- missing jump args
- extra jump args
- jump type mismatch
- yield type mismatch
- unterminated block
- irreducible control graph, if applicable

### 7.4 Backend guardrail

No open/host-only forms should reach backend lowering.

If they do, that is an architecture bug and should produce an explicit compiler
issue before backend, not a late trap command or generic Lua error.

---

## 8. Example target programs

### 8.1 Scalar add

```lua
local add1 = func add1(x: i32) -> i32
    return x + 1
end

local c = add1:compile()
assert(c(41) == 42)
c:free()
```

### 8.2 Find byte with inline region

```lua
local find_byte = func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry scan(i: i32 = 0)
        if i >= n then yield -1 end
        if zext<i32>(p[i]) == target then yield i end
        jump scan(i = i + 1)
    end
    end
end
```

### 8.3 Reusable continuation fragment

```lua
local scan_until = region scan_until(
    p: ptr(u8), n: i32, target: i32;
    hit: cont(pos: i32), miss: cont(pos: i32)
)
entry scan(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if zext<i32>(p[i]) == target then jump hit(pos = i) end
    jump scan(i = i + 1)
end
end

local find_byte = func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry start()
        emit scan_until(p, n, target; hit = found, miss = missing)
    end
    block found(pos: i32)
        yield pos
    end
    block missing(pos: i32)
        yield -1
    end
    end
end
```

### 8.4 Type-specialized sum

```lua
local function make_sum(T)
    return func sum(xs: ptr(@{T}), n: i32) -> @{T}
        return region -> @{T}
        entry loop(i: i32 = 0, acc: @{T} = 0)
            if i >= n then yield acc end
            jump loop(i = i + 1, acc = acc + xs[i])
        end
        end
    end
end

local sum_i32 = make_sum(i32)
local sum_f64 = make_sum(f64)
```

### 8.5 Parser combinator shape

```lua
local parse_digit = region parse_digit(
    p: ptr(u8), n: i32, pos: i32;
    ok: cont(next: i32, value: i32),
    err: cont(pos: i32, code: i32)
)
entry start()
    if pos >= n then jump err(pos = pos, code = ERR_EOF) end
    let c: i32 = zext<i32>(p[pos])
    if c >= 48 and c <= 57 then
        jump ok(next = pos + 1, value = c - 48)
    end
    jump err(pos = pos, code = ERR_EXPECT_DIGIT)
end
end
```

---

## 9. Implementation phases

### Phase 0 — Keep current hosted bootstrap stable

Current implementation exists:

```text
host_quote.lua
run_mlua.lua
test_host_quote.lua
test_host_quote_file.mlua
```

It proves custom keywords and `@{...}` staging through source-string lowering.

### Phase 1 — Hosted syntax cleanup

Goal: make current hosted bootstrap reliable enough to iterate syntax.

Tasks:

- split scanner/translator/splice/compiler concerns into focused modules
- preserve source names/spans in generated chunks
- make error messages include hosted source context
- add tests for comments, strings, nested Lua functions, nested Moonlift regions
- add runner arguments and return semantics

### Phase 2 — Inline `region -> T` syntax

Goal: standardize hosted object-language control syntax around `region` rather
than `control`.

Tasks:

- extend Moonlift parser to accept `region -> T` as alias/front door for
  `control -> T`
- accept `entry` as the entry block keyword
- keep old `control`/`block` syntax during transition
- add parser tests
- add hosted function tests

### Phase 3 — `expr` fragments

Goal: expression fragments become hosted values and usable with `emit`.

Tasks:

- parse hosted `expr name(params...) -> T ... end`
- produce `ExprFragValue`
- lower `emit expr_frag(args...)` to `ExprUseExprFrag`
- implement expansion path if incomplete
- validate arity/type issues explicitly
- add tests for expression fusion

### Phase 4 — region fragments without continuation params

Goal: reusable statement/control fragments with runtime parameters.

Tasks:

- parse hosted `region name(params...) ... end`
- produce `RegionFragValue`
- lower `emit frag(args...)` to `StmtUseRegionFrag`
- implement expansion/rebase path for labels and bindings
- add tests for simple fused region snippets

### Phase 5 — continuation parameters

Goal: typed CPS composition.

Tasks:

- design final ASDL for continuation slots/params/fills
- parse `cont(...)` in code-parameter position
- parse semicolon-separated runtime/control params
- lower continuation params into explicit open facts/fills
- validate continuation arg names/types
- implement block label rebasing/hygiene
- add tests for `scan_until(...; hit = found, miss = missing)`

### Phase 6 — code values/direct ASDL construction

Goal: stop relying on source strings as the primary internal representation.

Tasks:

- introduce typed code value modules
- expose TypeValue / ExprValue / BlockValue / RegionValue / FuncValue
- make hosted parser lower to code values or direct ASDL
- keep source-string lowering only as compatibility/bootstrap path
- add equivalence tests: source syntax and code-value construction produce same
  ASDL/compiler behavior

### Phase 7 — module/package integration

Goal: hosted files become practical libraries.

Tasks:

- package/module loading conventions
- local hosted fragment exports
- cross-file imports
- caching of parsed/compiled hosted modules
- clear public API for `Host.loadfile`, `Host.dofile`, `Host.require`

### Phase 8 — session/runtime object model

Goal: better runtime ergonomics, optionally before owned LuaJIT state.

Tasks:

- explicit `Session` object
- session-local compile cache
- artifact lifetime retention
- callable compiled functions
- better `__gc` where possible
- eventual native userdata/state-aware integration

---

## 10. Implementation complete checklist

### A. Hosted syntax bootstrap

- [x] Hosted `func ... end` recognized inside Lua chunks
- [x] Hosted `module ... end` recognized inside Lua chunks
- [x] Root `quote.lua` used for hygienic generated Lua emission
- [x] `Host.load(src)` returns a chunk function
- [x] `Host.eval(src)` executes a hosted chunk immediately
- [x] `Host.loadfile(path)` loads `.mlua` source as a chunk function
- [x] `Host.dofile(path)` executes `.mlua` source
- [x] `moonlift/run_mlua.lua` runner exists
- [x] Basic `@{...}` antiquote works for scalar/source splices
- [x] Hosted function values compile through normal Moonlift pipeline
- [x] Hosted module values compile through normal Moonlift pipeline
- [x] Jump-first control-region function works inside hosted `func`

### B. Hosted parser correctness

- [ ] Scanner split from compiler wrapper into `host_parse.lua`
- [ ] Splice logic split into `host_splice.lua`
- [ ] Hosted source spans preserved through generated Lua
- [ ] Unterminated forms report source location
- [ ] Malformed antiquote reports source location
- [ ] Comments and strings cannot accidentally start hosted forms
- [ ] Nested Lua `function ... end` around hosted quotes tested
- [ ] Nested Moonlift control/region blocks tested
- [ ] `module` identifier safety tested beyond simple local variable case
- [ ] Generated Lua source can be dumped for debugging

### C. Inline region syntax

- [x] Parser accepts `region -> T ... end`
- [x] Parser accepts `entry name(...)` as entry block syntax
- [x] `region -> T` lowers to `ExprControl(ControlExprRegion)`
- [x] Old `control -> T` still works or has migration tests
- [ ] Typecheck validates region yield type
- [ ] Control facts validate jump graph
- [ ] Backend lowers inline hosted region to flat commands
- [ ] Tests cover loops, branches, multi-block regions

### D. Expression fragments

- [x] Hosted `expr name(params...) -> T ... end` parses
- [x] `ExprFragValue` exists
- [x] `emit expr_frag(args...)` parses in expression position for known hosted fragment values
- [x] `emit expr_frag(args...)` lowers to `ExprUseExprFrag`
- [x] `ExprUseExprFrag` expansion implemented
- [ ] Fragment arg arity validation exists
- [ ] Fragment arg type validation exists
- [ ] Unexpanded expr fragment rejected before backend
- [x] Tests cover expression fragment fusion

### E. Region fragments without continuations

- [x] Hosted `region name(params...) ... end` parses for entry + internal block statement fragments
- [x] `RegionFragValue` exists
- [x] `emit region_frag(args...; cont = block)` parses in statement position for known hosted fragment values; explicit `@{region_frag}` also works
- [x] `emit region_frag(args...; cont = block)` lowers to `StmtUseRegionFrag`
- [x] `StmtUseRegionFrag` expansion implemented for statement fragments and continuation-slot jumps
- [ ] Label rebasing/hygiene implemented
- [ ] Local binding rebasing/hygiene implemented
- [ ] Unexpanded region fragment rejected before backend
- [x] Tests cover simple fused statement/control fragments with continuation slots
- [x] Tests cover fragment entry-parameter initialization and internal block rebasing
### F. Continuation parameters

- [x] Initial ASDL design for continuation parameters/slots/fills chosen (`ContSlot`, `SlotCont`, `SlotValueCont`, `StmtJumpCont`)
- [x] `cont(...)` syntax parses for hosted region fragment continuation params
- [x] Semicolon separates runtime params from continuation/code params in hosted region fragments
- [x] Continuation params are represented as explicit ASDL values
- [x] Continuation fills bind fragment continuation params to block labels
- [x] Missing/duplicate/unknown continuation fill validation implemented at parse/use-site level
- [x] Continuation jump arity validation implemented before expansion
- [x] Continuation jump named-arg validation implemented before expansion
- [ ] Continuation type validation implemented
- [ ] Continuation scope validation implemented
- [x] Fragment expansion rewrites continuation jumps to concrete block labels
- [x] Tests cover hosted `emit @{fragment}(...; hit = found)` continuation fill syntax
- [ ] Tests cover missing continuation fill rejection
- [ ] Tests cover wrong continuation arg name rejection
- [ ] Tests cover wrong continuation arg type rejection

### G. Code value substrate

- [ ] `TypeValue` implemented
- [ ] `ExprValue<T>` implemented
- [ ] `PlaceValue<T>` implemented
- [ ] `BlockValue<params>` implemented
- [ ] `RegionValue<result>` implemented
- [ ] `ExprFragValue` implemented
- [ ] `RegionFragValue` implemented
- [ ] `FuncValue` implemented
- [ ] `ModuleValue` implemented
- [ ] Code values expose ASDL without hidden mutable semantics
- [ ] Hosted syntax can lower to code values/direct ASDL
- [ ] Source-string lowering no longer required for core hosted semantics
- [ ] Equivalence tests compare code-value vs syntax-generated programs

### H. Open expansion / validation

- [ ] `open_expand.lua` expands expression fragments fully
- [x] `open_expand.lua` expands region fragments with continuation-slot jumps
- [x] `open_validate.lua` reports unfilled continuation slots
- [ ] `open_validate.lua` reports unexpanded expr fragments
- [ ] `open_validate.lua` reports unexpanded region fragments
- [ ] `open_rewrite.lua` supports needed rebasing/rewrite facts
- [ ] Expansion produces closed Moon2Tree before typecheck/back lowering
- [ ] No open form reaches backend lowering in successful programs

### I. Runtime/session ergonomics

- [ ] `CompiledFunction` use-after-free guarded
- [ ] Compiled functions retain artifacts for lifetime safety
- [ ] `CompiledModule:get(name)` caches wrappers
- [ ] Void-return functions supported in wrapper signatures
- [ ] Pointer/scalar FFI signature support documented
- [ ] Session object designed
- [ ] Session-local compile cache implemented
- [ ] Optional native userdata/state-aware path designed

### J. Documentation and examples

- [ ] README explains hosted continuation language as the primary metaprogramming model
- [ ] README stops framing the design as merely Terra-like quoting
- [ ] Syntax examples include inline regions and continuation fragments
- [ ] Checklist kept current as implementation changes
- [ ] Design docs describe ASDL mapping for every hosted keyword
- [ ] Examples include `find_byte`
- [ ] Examples include `scan_until` continuation fragment
- [ ] Examples include type-specialized `sum`
- [ ] Examples include parser-combinator-style digit parser

---

## 11. Immediate next implementation target

The next patch after this plan should not expand JSON or add ad hoc domain
syntax.

Recommended next target:

```text
Inline hosted `region -> T` + `entry` syntax
```

Why:

- it moves the hosted language toward the real primitive vocabulary
- it maps cleanly to existing `ControlExprRegion`
- it avoids committing to continuation-param ASDL too early
- it gives immediate user-facing syntax improvement

Concrete target program:

```lua
local find_byte = func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry scan(i: i32 = 0)
        if i >= n then yield -1 end
        if zext<i32>(p[i]) == target then yield i end
        jump scan(i = i + 1)
    end
    end
end
```

Implementation path:

```text
parse.lua:
  add `region` token/keyword
  parse `region -> T` same as current `control -> T`
  add `entry` token/keyword
  parse entry block as alias for first `block`

test_host_quote.lua:
  change hosted find_byte example from `control`/`block` to `region`/`entry`

regression:
  keep current `control` tests passing
```

This establishes the hosted vocabulary before implementing reusable
continuation-parameterized fragments.
