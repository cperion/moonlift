# Moonlift Jump-First Source Grammar

Status: design grammar for the Moonlift authored language.

Moonlift does **not** inherit Moonlift's older loop surface syntax.  The base
language is jump-first:

```text
typed blocks + explicit jump arguments + yield/return exits
```

There is no `for`, no `while`, no `loop`, no `next`, no `break`, and no
`continue` in the base grammar.  Those may be added later only as explicit sugar
that lowers into the block/jump core.

The initial parser now exists in `lua/moonlift/parse.lua`.  This document remains
the grammar contract for expanding that implementation, and the ASDL is designed
to represent these control-flow nouns directly. Hosted `.mlua` declaration
islands add end-delimited `struct` / name-first `expose Name: subject ... end`
syntax on top of this object grammar. The complete hosted language surface lives
in `LANGUAGE_REFERENCE.md`.

Companion docs:

- `LANGUAGE_REFERENCE.md` — complete single-file language reference
- `README.md` — repository overview and common commands
- `PVM_GUIDE.md` — ASDL/PVM framework guide

The current command-line artifact path consumes `.mlua` files through this same
object grammar for functions/modules, then lowers through `Moon2Back` and the
`Moon2Link` ASDL linker layer for `.o` / shared-library emission. Artifact
packaging is deliberately outside the source grammar: source declares object
code; `Moon2Link.LinkPlan` declares how compiled objects are linked.

The Lua constructor counterpart to this grammar is `require("moonlift.ast")`.
Its LuaLS-documented functions construct the same source ASDL nodes described
here (`Moon2Core`, `Moon2Type`, and `Moon2Tree` surface values), so the
constructor tables double as a field-by-field language reference for hosted Lua
generation. The constructor layer is not a new semantic extension point; it
builds existing ASDL values for the normal PVM phases.

---

## 1. Core control-flow choice

Old Moonlift statement loops were shaped around carries and `next`:

```moonlift
for i in 0..n with acc: i32 = 0 do
    next acc = acc + xs[i]
end
```

Moonlift's base spelling is a typed block with explicit recursive jumps:

```moonlift
block loop(i: index = 0, acc: i32 = 0) -> i32
    if i >= n then
        yield acc
    end

    jump loop(i = i + 1, acc = acc + xs[i])
end
```

For function-tail loops, `return` can be used directly:

```moonlift
func sum(xs: view(i32), n: index) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end

        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

For multi-block local control graphs:

```moonlift
let result: i32 = control -> i32
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then
        yield acc
    end
    if xs[i] < 0 then
        jump fail()
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end

block fail()
    yield -1
end
end
```

The explicit `done(value)` block is not required.  `yield value` is the anonymous
exit continuation for a value-producing control expression.  Bare `yield` exits a
void/statement control region.

---

## 2. Lexical layer

### 2.1 Whitespace and newlines

Whitespace separates tokens.  Newlines matter for item and statement separation.

```text
nl ::= one or more newline tokens
```

### 2.2 Comments

```text
line_comment  ::= "--" ... end_of_line
block_comment ::= "--[[" ... "]]"
```

### 2.3 Identifiers

```text
ident ::= [A-Za-z_][A-Za-z0-9_]*
path  ::= ident { "." ident }
```

### 2.4 Literals

```text
int_lit   ::= decimal_int | hex_int
float_lit ::= decimal_float [ exponent ]
bool_lit  ::= "true" | "false"
nil_lit   ::= "nil"
```

Numeric literal raw spelling is preserved in the source ASDL.  Numeric meaning is
decided by later typed phases.

### 2.5 Reserved words

Core reserved words:

```text
export extern func fn closure const static import type
struct enum union view
noalias readonly writeonly requires bounds window_bounds disjoint same_len len
let var if then elseif else switch case default do end
block control jump yield return
true false nil and or not
as
```

Scalar type words are reserved in type position:

```text
void bool
i8 i16 i32 i64
u8 u16 u32 u64
f32 f64
index
```

Intrinsic names are reserved in intrinsic-call position:

```text
popcount clz ctz rotl rotr bswap
fma sqrt abs floor ceil trunc_float round
trap assume
```

Intentionally not base-language keywords:

```text
for while loop next break continue over range zip zip_eq
```

Those names may be ordinary identifiers in the base parser. The `.mlua` source-normalize layer now reserves only the explicit end-delimited `loop counted ... end` sugar pattern and lowers it to the block/jump core before parsing.

---

## 3. Modules and items

```text
module ::= { item }

item ::= func_item
       | extern_func_item
       | const_item
       | static_item
       | import_item
       | type_item
```

### 3.1 Functions

```text
func_item ::= [ "export" ] "func" ident "(" [ param_list ] ")" [ "->" type ] nl
              { requires_clause nl }
              stmt_block
              "end"

param_list      ::= param { "," param }
param           ::= { param_modifier } ident ":" type
param_modifier  ::= "noalias" | "readonly" | "writeonly"
requires_clause ::= "requires" contract_predicate
contract_predicate ::= "bounds" "(" expr "," expr ")"
                     | "window_bounds" "(" expr "," expr "," expr "," expr ")"
                     | "disjoint" "(" expr "," expr ")"
                     | "same_len" "(" expr "," expr ")"
                     | "noalias" "(" expr ")"
                     | "readonly" "(" expr ")"
                     | "writeonly" "(" expr ")"

view_expr   ::= "view" "(" expr "," expr [ "," expr ] ")"
length_expr ::= "len" "(" expr ")"
```

`view` lengths, `view_window` starts/lengths, and `len(view)` are typed as `index` in the current executable ABI.

Rules:

- missing result type means `void`
- `export func` is visible to importing modules
- plain `func` is module-local
- parameter modifiers and `requires` clauses are source contracts; typechecking resolves them to binding-backed contract facts

Examples:

```moonlift
export func add1(x: i32) -> i32
    return x + 1
end

func fill(dst: view(i32), n: index)
    block loop(i: index = 0)
        if i >= n then
            yield
        end
        dst[i] = 0
        jump loop(i = i + 1)
    end
end
```

### 3.2 Extern functions

```text
extern_func_item ::= "extern" "func" ident "(" [ param_list ] ")" [ "->" type ]
```

The local item name is also the default external symbol name unless a later ABI
surface adds explicit symbol spelling.

### 3.3 Constants, statics, and imports

```text
const_item  ::= "const" ident ":" type "=" expr
static_item ::= "static" ident ":" type "=" expr
import_item ::= "import" path
```

Rules:

- `const` is a pure compile-time value
- `static` is addressable runtime storage
- imports introduce qualified namespaces only

### 3.4 Type items

```text
type_item ::= "type" ident "=" type_decl

type_decl ::= struct_decl
            | enum_decl
            | union_decl
            | tagged_union_decl

struct_decl ::= "struct" nl type_field_list "end"
union_decl  ::= "union"  nl type_field_list "end"

type_field_list ::= { type_field [ "," ] nl }
type_field      ::= ident ":" type

enum_decl ::= "enum" nl enum_variant_list "end"
enum_variant_list ::= { ident [ "," ] nl }

tagged_union_decl ::= tagged_variant { "|" tagged_variant }
tagged_variant     ::= ident [ "(" type ")" ]
```

Examples:

```moonlift
type Pair = struct
    left: i32
    right: i32
end

type Color = enum
    red
    green
    blue
end

type Bits = union
    i: i32
    f: f32
end

type Result = ok(i32) | err(i32)
```

Enums, tagged unions, and untagged unions are surface sugar over explicit consts
and layouts in later phases.

---

## 4. Types

```text
type ::= scalar_type
       | named_type
       | ptr_type
       | array_type
       | slice_type
       | view_type
       | func_type
       | closure_type

scalar_type ::= "void" | "bool"
              | "i8" | "i16" | "i32" | "i64"
              | "u8" | "u16" | "u32" | "u64"
              | "f32" | "f64"
              | "index"

named_type   ::= path
ptr_type     ::= "&" type
array_type   ::= "[" expr "]" type
slice_type   ::= "[]" type
view_type    ::= "view" "(" type ")"
func_type    ::= "func" "(" [ type_list ] ")" "->" type
closure_type ::= "closure" "(" [ type_list ] ")" "->" type

type_list ::= type { "," type }
```

Examples:

```moonlift
&i32
[4]i32
[N + 1]u8
[]f32
view(i32)
func(i32, i32) -> i32
closure(i32) -> i32
Demo.Pair
```

---

## 5. Blocks, control regions, jumps, and yields

This is the central Moonlift grammar.

### 5.1 Block parameters

There are two parameter forms:

```text
block_param       ::= ident ":" type
entry_block_param ::= ident ":" type "=" expr
```

A block parameter without `=` describes a target signature.  An entry block
parameter with `=` describes both the target signature and the initial argument
used to enter the region.

### 5.2 Single-block control expression

```text
single_block_expr ::= "block" ident "(" [ entry_block_param_list ] ")" "->" type nl
                      control_stmt_block
                      "end"

entry_block_param_list ::= entry_block_param { "," entry_block_param }
```

Example:

```moonlift
let total: i32 = block loop(i: index = 0, acc: i32 = 0) -> i32
    if i >= n then
        yield acc
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end
```

### 5.3 Single-block control statement

```text
single_block_stmt ::= "block" ident "(" [ entry_block_param_list ] ")" nl
                      control_stmt_block
                      "end"
```

Example:

```moonlift
block loop(i: index = 0)
    if i >= n then
        yield
    end
    dst[i] = 0
    jump loop(i = i + 1)
end
```

A void `yield` exits the block statement and continues after it.

### 5.4 Multi-block control expression

```text
control_expr ::= "control" "->" type nl
                 entry_control_block
                 { control_block }
                 "end"
```

### 5.5 Multi-block control statement

```text
control_stmt ::= "control" nl
                 entry_control_block
                 { control_block }
                 "end"
```

### 5.6 Control blocks

```text
entry_control_block ::= "block" ident "(" [ entry_block_param_list ] ")" nl
                        control_stmt_block
                        "end"

control_block ::= "block" ident "(" [ block_param_list ] ")" nl
                  control_stmt_block
                  "end"

block_param_list ::= block_param { "," block_param }
```

Rules:

- the first block in a `control` region is the entry block
- the entry block's params either all have initializers or the block has no params
- non-entry blocks use ordinary block params without initializers
- block labels are scoped to the nearest single-block or multi-block region
- duplicate labels in one region are rejected

Example:

```moonlift
let out: i32 = control -> i32
block loop(i: index = 0, acc: i32 = 0)
    if i >= n then
        yield acc
    end
    if xs[i] < 0 then
        jump fail()
    end
    jump loop(i = i + 1, acc = acc + xs[i])
end

block fail()
    yield -1
end
end
```

### 5.7 Jump statements

```text
jump_stmt ::= "jump" ident "(" [ jump_arg_list ] ")"
jump_arg_list ::= jump_arg { "," jump_arg } [ "," ]
jump_arg ::= ident "=" expr
```

Rules:

- target must be a block label in the current control region
- jump arguments are named, not positional
- argument names must match target block parameter names exactly
- argument types must match target block parameter types
- `jump` terminates the current path; there is no fallthrough after it

### 5.8 Yield statements

```text
yield_stmt ::= "yield" [ expr ]
```

Rules:

- `yield expr` exits the nearest value-producing control region
- bare `yield` exits the nearest void/statement control region
- `yield` is rejected outside a control region
- a control expression's yielded values must match its declared result type

### 5.9 Return statements

```text
return_stmt ::= "return" [ expr ]
```

Rules:

- `return` exits the enclosing function, not merely the control region
- `return expr` must match the function result type
- `return` with no value requires a `void` function result

### 5.10 Required explicit termination

A control block path must terminate with one of:

- `jump ...`
- `yield ...`
- `return ...`
- a semantic terminating intrinsic such as `trap()`
- an `if` / `switch` whose possible paths all terminate

No implicit fallthrough from one block to the next exists.

---

## 6. Statements

```text
stmt ::= let_stmt
       | var_stmt
       | set_stmt
       | if_stmt
       | switch_stmt
       | jump_stmt
       | yield_stmt
       | return_stmt
       | single_block_stmt
       | control_stmt
       | expr_stmt

stmt_block         ::= { stmt }
control_stmt_block ::= { stmt }
```

Parser note:

- the parser may parse `jump` and `yield` wherever `stmt` is accepted
- later validation rejects them outside valid control-region positions

### 6.1 Let / var

```text
let_stmt ::= "let" ident ":" type "=" expr
var_stmt ::= "var" ident ":" type "=" expr
```

`let` is an immutable value binding.  `var` is a mutable cell binding.

### 6.2 Assignment

```text
set_stmt ::= place "=" expr
```

### 6.3 If statement

```text
if_stmt ::= "if" expr "then" nl
            stmt_block
            { "elseif" expr "then" nl stmt_block }
            [ "else" nl stmt_block ]
            "end"
```

`elseif` may parse as nested `if` in the else branch.

### 6.4 Switch statement

```text
switch_stmt ::= "switch" expr "do" nl
                switch_stmt_arm+
                default_stmt_arm
                "end"

switch_stmt_arm  ::= "case" expr "then" nl stmt_block
default_stmt_arm ::= "default" "then" nl stmt_block
```

There is no fallthrough.

### 6.5 Expression statement

```text
expr_stmt ::= expr
```

Expression statements are mainly useful for calls and void/control intrinsics
such as `assume(cond)` or `trap()`.

---

## 7. Places / lvalues

```text
place        ::= place_atom { place_suffix }
place_atom   ::= ident
               | path
               | "*" expr
place_suffix ::= "." ident
               | "[" expr "]"
```

Examples:

```moonlift
x
Demo.G
*p
p.left
xs[i]
(*p).field
```

Parser target rule:

- assignment and address-of parse through place syntax
- authored dotted places are preserved first and resolved later

---

## 8. Expressions

```text
expr ::= if_expr
       | switch_expr
       | block_expr
       | single_block_expr
       | control_expr
       | select_expr
       | binary_expr
```

### 8.1 If expression

```text
if_expr ::= "if" expr "then" expr "else" expr "end"
```

### 8.2 Select expression

```text
select_expr ::= "select" "(" expr "," expr "," expr ")"
```

`select` is a dataflow choose form, distinct from control-flow `if`.

### 8.3 Switch expression

```text
switch_expr ::= "switch" expr "do" nl
                switch_expr_arm+
                default_expr_arm
                "end"

switch_expr_arm  ::= "case" expr "then" nl expr_block
default_expr_arm ::= "default" "then" nl expr_block
```

An expression arm is a statement list followed by a required result expression.

### 8.4 Ordinary block expression

```text
block_expr ::= "do" nl expr_block "end"
expr_block ::= { stmt } expr
```

This is not a control region.  It has an ordinary final expression and does not
introduce block labels.

### 8.5 Closure expression

```text
closure_expr ::= "fn" "(" [ param_list ] ")" [ "->" type ] nl
                 stmt_block
                 "end"
```

Closures are surface sugar over a function pointer plus context descriptor.

### 8.6 View construction expressions

These parse as special expression forms or reserved intrinsic-like constructors:

```text
view_expr ::= "view" "(" expr "," expr [ "," expr ] ")"
            | "view_window" "(" expr "," expr "," expr ")"
            | "view_from_ptr" "(" expr "," expr ")"
            | "view_from_ptr" "(" expr "," expr "," expr ")"
            | "view_strided" "(" expr "," expr ")"
            | "view_interleaved" "(" expr "," expr "," expr ")"
```

### 8.7 Aggregate literals

```text
agg_expr ::= type_like "{" [ field_init_list ] "}"
field_init_list ::= field_init { "," field_init } [ "," ]
field_init      ::= ident "=" expr
```

Example:

```moonlift
Pair { left = 1, right = 2 }
```

### 8.8 Array literals

```text
array_lit_expr ::= "[]" type "{" [ expr_list ] "}"
```

Example:

```moonlift
[]i32 { 1, 2, 3 }
```

---

## 9. Ordinary precedence grammar

After special forms are handled, ordinary expressions use precedence parsing.

### 9.1 Precedence table

Lowest to highest:

1. `or`
2. `and`
3. comparisons: `== ~= < <= > >=`
4. bitwise or: `|`
5. bitwise xor: `~`
6. bitwise and: `&`
7. shifts: `<< >> >>>`
8. additive: `+ -`
9. multiplicative: `* / %`
10. prefix unary: `- not ~ & *`
11. postfix: call, field, index

### 9.2 Prefix expressions

```text
prefix_expr ::= literal
              | name_expr
              | as_expr
              | intrinsic_expr
              | closure_expr
              | view_expr
              | array_lit_expr
              | "(" expr ")"
              | unary_expr

literal ::= int_lit | float_lit | bool_lit | nil_lit
name_expr ::= path
```

### 9.3 Semantic conversion expressions

```text
as_expr ::= "as" "(" type "," expr ")"
```

`as(T, value)` is the only source-level conversion spelling. It is a semantic
conversion request, not a generic call and not an explicit machine operation.
The typed/lowering phases choose the concrete machine cast (`extend`, `truncate`,
float conversion, bitcast, or identity) from the source and target types.

Moonlift source intentionally has no angle-bracket type-argument syntax. Use
Lua-hosted generation for genericity and `as(T, value)` for monomorphic
conversions.

### 9.4 Intrinsic calls

```text
intrinsic_expr ::= intrinsic_name "(" [ expr_list ] ")"
expr_list      ::= expr { "," expr }
```

### 9.5 Unary expressions

```text
unary_expr ::= "-" expr
             | "not" expr
             | "~" expr
             | "&" place
             | "*" expr
```

### 9.6 Postfix expressions

```text
postfix_expr   ::= prefix_expr { postfix_suffix }
postfix_suffix ::= call_suffix | field_suffix | index_suffix
call_suffix    ::= "(" [ expr_list ] ")"
field_suffix   ::= "." ident
index_suffix   ::= "[" expr "]"
```

Authored dotted value syntax is preserved first and resolved later as either a
qualified binding path or a field projection.

---

## 10. Static validation rules for control regions

The parser builds syntax.  Later ASDL/PVM phases must answer these questions
explicitly:

1. **Label validation**
   - every jump target exists in the nearest control region
   - labels are unique within a region
   - labels do not leak outside their region

2. **Signature validation**
   - jump argument count matches target block parameter count
   - jump argument types match target block parameter types
   - entry initializers match entry block parameter types

3. **Exit validation**
   - `yield` appears only in a control region
   - yielded values match the region result type
   - bare `yield` is allowed only for void statement regions
   - `return` matches the function result type

4. **Termination validation**
   - every control-block path terminates explicitly
   - no implicit block fallthrough exists
   - unreachable code after a terminating statement is diagnosed or ignored by an explicit unreachable-code policy

5. **Shape facts for optimization**
   - backedges are gathered as facts
   - reducible/irreducible graph decisions are explicit
   - counted-loop/induction facts are derived from block params and jump args
   - vectorization consumes facts/proofs/rejects, not parser guesses

---

## 11. ASDL implications

The Moonlift ASDL now represents jump-first control directly.  The old
`LoopWhile` / `LoopFor` / `CarryUpdate` shape is no longer the base source model.

The tree/control families include:

```text
BlockLabel
BlockParam
EntryBlockParam
JumpArg
EntryControlBlock
ControlBlock
ControlStmtRegion
ControlExprRegion
ControlFact
ControlDecision
ControlReject
```

Surface-level terminating statements are explicit ASDL variants:

```text
JumpArg(name, value)
StmtJump(label, named_args)
StmtYieldVoid
StmtYieldValue(expr)
StmtReturnVoid
StmtReturnValue(expr)
```

A conditional can remain a structured statement at the surface, but a later
control-lowering/validation phase may emit explicit branch terminators or facts:

```text
TermBrIf(cond, then_label, then_named_args, else_label, else_named_args)
```

The backend already has the right flat primitives:

```text
Moon2Back.CmdJump
Moon2Back.CmdBrIf
Moon2Back.CmdReturnVoid
Moon2Back.CmdReturnValue
Moon2Back.CmdTrap
```

So the source/middle ASDL should feed those commands without reintroducing hidden
`next` semantics.

---

## 12. Complete examples

### 12.1 Scalar sum as value expression

```moonlift
export func sum(xs: view(i32), n: index) -> i32
    let total: i32 = block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= n then
            yield acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end

    return total
end
```

### 12.2 Scalar sum in function-tail position

```moonlift
export func sum_tail(xs: view(i32), n: index) -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            return acc
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
```

### 12.3 Side-effect loop then continue

```moonlift
func zero(dst: view(i32), n: index)
    block loop(i: index = 0)
        if i >= n then
            yield
        end
        dst[i] = 0
        jump loop(i = i + 1)
    end

    return
end
```

### 12.4 Multi-block control expression

```moonlift
func checked_sum(xs: view(i32), n: index) -> i32
    return control -> i32
    block loop(i: index = 0, acc: i32 = 0)
        if i >= n then
            yield acc
        end
        if xs[i] < 0 then
            jump fail()
        end
        jump loop(i = i + 1, acc = acc + xs[i])
    end

    block fail()
        yield -1
    end
    end
end
```

### 12.5 State machine

```moonlift
func scan(p: &u8, n: index) -> index
    return control -> index
    block read(i: index = 0)
        if i >= n then
            yield n
        end
        if p[i] == 10 then
            jump found(i = i)
        end
        jump read(i = i + 1)
    end

    block found(i: index)
        yield i
    end
    end
end
```

---

## 13. Summary

Moonlift's source grammar keeps Moonlift's typed, explicit, Lua-like surface for
items, types, expressions, statements, aggregates, views, and intrinsics, but
replaces the older structured loop/`next` family with a smaller primitive:

```text
block params + jump args + yield/return exits
```

This is slightly more explicit than the old `for ... with ... next` surface for
trivial counted loops, but it is cleaner as the language core and maps directly
to the existing flat backend command layer.  Structured loop syntax can always be
added later as sugar if the language wants it; it should not be the primitive.
