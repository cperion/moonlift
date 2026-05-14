# Error Management Design for Moonlift

## The Problem

Moonlift's error messages are not just bad — they are architecturally
incapable of being good. The current system has:

- Flat strings with line:col — no source context, no underlines
- Parse errors that say "expected X, got Y" with no clue which construct
- Type errors that show internal type names like `ScalarI32`
- Control errors that reference compiler internals, not source concepts
- Backend errors that are meaningless to users writing `.mlua`
- No fix suggestions, no "did you mean?", no structural guidance
- Cascade suppression via `void`-type heuristics instead of root-cause tracking
- `detect_hint()` that only knows Lua/LuaJIT patterns, nothing Moonlift-specific
- A `snippet` field in the diagnostic that nothing ever populates

This is not a string-polishing problem. It is an architecture problem.

## Design Principles

### 1. Errors are first-class authored artifacts

An error message is not a log line. It is a document the compiler writes
for a human. It deserves the same design care as any other user-facing
surface. Every error the compiler emits is a moment of trust — break it
and the user stops believing the compiler has their back.

### 2. Show the code, point at the cause, explain the gap

Every error has three layers:

```
   what you wrote        → source span + visual underline
   what the compiler     → human-readable explanation of the rule
     expected instead
   how to close the gap  → actionable suggestion or "did you mean?"
```

Never show one without the others. A line number without the code is
useless. Code without explanation is noise. Explanation without a
suggestion is a dead end.

### 3. One error per root cause

When a type doesn't resolve, every downstream use of that name cascades.
The user sees 47 errors, but only one matters. The error system must
track root causes and suppress downstream noise. The user should see:

```
error: unresolved name `taape`
  ┌─ experiment.mlua:42:18
  │
42│     let op: i32 = taape[pc]
  │                    ^^^^^
  │
  = note: `taape` is not defined in this scope
  = help: did you mean `tape`?
```

not 47 follow-up "expected i32, got void" errors.

### 4. Speak the language's concepts, not the compiler's internals

Moonlift has a unique conceptual vocabulary — regions, continuations,
emits, block labels, jump arguments, protocol types, splice slots.
Errors must speak this language:

```
error: continuation `bad` is not declared by region `exec_slice`
  ┌─ experiment.mlua:78:36
  │
78│     emit exec_slice(tape, n, pc; next = dispatch, bad = halted)
   │                                    ~~~~~~~~~~~   ^^^
   │
   = note: `exec_slice` declares these continuations:
           `next`, `stop`
   = help: did you mean `stop`?
```

Never say "BackIssueMissingExtern" or "TypeIssueExpected(site=i32, i32, void)".

### 5. Phase-aware but phase-transparent

The compiler has phases (parse → typecheck → host → open → back → link).
Each phase produces its own issues. But the user should never need to
know which phase produced an error. The error system translates internal
phase vocabulary into source-level vocabulary:

| Internal | User sees |
|----------|-----------|
| ParseIssue | syntax error |
| TypeIssueExpected | type mismatch |
| TypeIssueUnresolvedValue | unresolved name |
| ControlRejectUnterminatedBlock | block doesn't exit |
| BackIssueDuplicateBlock | duplicate block label |
| HostIssueDuplicateField | duplicate struct field |

### 6. Structural errors get structural presentations

Moonlift's regions and control flow are structured. Errors about them
should use that structure:

```
error: region `exec_slice` declares continuation `stop(code: i32)`
       but emit site fills it as `stop = halted` with no argument
  ┌─ experiment.mlua:78:5
   │
78│     emit exec_slice(tape, n, pc, tape_len, mem_sum, live, fuel;
   │     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
79│         again = dispatch, stop = halted)
   │         ~~~~~            ~~~~~~~~~~~~~
   │
   = note: continuation `stop` expects: `code: i32`
   = note: `halted` is a block that accepts: `code: i32`
   = help: write `stop(code = ...)` in the continuation fill,
           or fill it with a block that has matching parameters:
               stop = halted    ← fills `code` from block param `code`
```

### 7. The error report is a tree, not a flat list

Related errors form a tree. The root is the primary diagnosis.
Children are notes, suggestions, and sub-diagnostics. This structure
is preserved through rendering — both terminal and LSP.

---

## Architecture

### Overview

```
  Compiler Phases
       │
       ▼
  ┌─────────────────┐
  │  Issue Registry  │   collects raw issues from all phases
  │                  │   assigns root-cause groups
  │  - emit(issue)   │   suppresses cascades
  │  - dedup()       │
  │  - root_groups() │
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │  Error Catalog   │   maps (issue_kind, context) → ErrorTemplate
  │                  │
  │  - code E0xxx    │   each entry: code, severity, template,
  │  - template      │   known suggestions, related-error links
  │  - suggestions   │
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │  Report Builder  │   assembles ErrorReport from issue + catalog
  │                  │
  │  - primary span  │   fetches source lines for visual rendering
  │  - notes         │   resolves "did you mean?" candidates
  │  - suggestions   │   builds the structured report tree
  │  - sub-diagnostics│
  └────────┬────────┘
           │
           ▼
  ┌─────────────────────────────────┐
  │            Presenter             │
  │                                  │
  │  ┌──────────┐ ┌──────┐ ┌─────┐ │
  │  │ Terminal  │ │  LSP │ │JSON │ │
  │  │ (pretty)  │ │diag  │ │API  │ │
  │  └──────────┘ └──────┘ └─────┘ │
  └─────────────────────────────────┘
```

### Component 1: Source Span

A `SourceSpan` replaces bare `(offset, line, col)` throughout the codebase.

```lua
-- A span identifies a range of source text with enough context
-- to render it visually.
local SourceSpan = {
    uri = string,            -- which file
    start_offset = number,   -- byte offset, 0-based
    end_offset = number,     -- byte offset, exclusive
    start_line = number,     -- 1-based
    start_col = number,      -- 1-based, UTF-16 units
    end_line = number,
    end_col = number,
}
```

Every issue produced by every phase carries a `SourceSpan`, not just
a line/column. The parser already has this information (token start/stop);
it just isn't propagated through to the error.

The span also knows how to render itself:

```lua
function SourceSpan:render(source_text, context_lines)
    -- Returns a table:
    -- {
    --   gutter = { "  │", "5 │", "  │", "6 │", "  │" },
    --   lines  = { "", "let x: i32 = \"hello\"", "", "let y = x + true", "" },
    --   underlines = {
    --     { line_idx = 2, start = 12, len = 7, label = "this is `string`" },
    --     { line_idx = 4, start = 8, len = 1, label = "expected `i32`" },
    --   },
    -- }
end
```

Multiple spans can be rendered in a single snippet (primary + secondary
pointers, like Rust's multi-span errors).

### Component 2: Error Catalog

The catalog is the single source of truth for what each error means.
It maps internal issue kinds to human-facing error templates.

```lua
-- Each catalog entry:
local Entry = {
    code = "E0301",          -- stable, searchable error code
    severity = "error",      -- error | warning | info | hint
    phase_label = string,    -- what the compiler was doing

    -- The template is a function, not a static string.
    -- It receives the issue + analysis context and returns
    -- the structured report.
    build = function(issue, analysis)
        return {
            primary = {
                span = issue.span,
                message = "unresolved name `" .. issue.name .. "`",
            },
            notes = {
                {
                    span = nil,  -- no span, just prose
                    message = "`" .. issue.name .. "` is not defined in this scope",
                },
            },
            suggestions = did_you_mean(issue.name, analysis.in_scope_names),
        }
    end,
}
```

The catalog is organized by domain:

```lua
local catalog = {
    -- E0xxx: parse errors
    E0101 = { ... },  -- unexpected token
    E0102 = { ... },  -- unterminated construct
    E0103 = { ... },  -- missing keyword

    -- E02xx: name resolution
    E0201 = { ... },  -- unresolved name
    E0202 = { ... },  -- unresolved path
    E0203 = { ... },  -- duplicate name

    -- E03xx: type mismatches
    E0301 = { ... },  -- type mismatch (expected X, got Y)
    E0302 = { ... },  -- not callable
    E0303 = { ... },  -- not indexable
    E0304 = { ... },  -- invalid operator
    E0305 = { ... },  -- arg count mismatch

    -- E04xx: control flow errors
    E0401 = { ... },  -- unterminated block
    E0402 = { ... },  -- missing jump target
    E0403 = { ... },  -- continuation not filled
    E0404 = { ... },  -- continuation type mismatch
    E0405 = { ... },  -- irreducible control flow
    E0406 = { ... },  -- duplicate block label
    E0407 = { ... },  -- yield outside region

    -- E05xx: host/struct errors
    E0501 = { ... },  -- duplicate field
    E0502 = { ... },  -- duplicate type
    E0503 = { ... },  -- unsealed type
    E0504 = { ... },  -- invalid name

    -- E06xx: backend errors
    E0601 = { ... },  -- mapped to source-level: "block X is used but never defined"

    -- E07xx: splice/metaprogramming errors
    E0701 = { ... },  -- splice produced wrong type
    E0702 = { ... },  -- missing splice fill
}
```

### Component 3: Issue Registry

The registry collects issues from all compiler phases, then applies
two transformations before presentation:

**Root-cause grouping.** When a name doesn't resolve, every downstream
use of that name is a cascade. The registry tracks which names failed
to resolve and groups all `TypeIssueExpected` issues whose `actual` is
void and whose site references an unresolved name. These become children
of the root `TypeIssueUnresolvedValue`, not independent errors.

**Deduplication.** The same issue at the same span from different phases
is reported once, not twice. Two different issues at the same span from
different phases are both reported (they have different root causes).

```lua
local IssueRegistry = {
    issues = {},            -- all issues, in order
    unresolved = {},        -- name → first issue that failed
    span_index = {},        -- span_key → {issue_indices}
    root_groups = {},       -- root_issue_idx → {child_indices}
}

function IssueRegistry:emit(issue, phase, analysis)
    -- 1. Record the issue
    -- 2. If it's a name-resolution failure, register in `unresolved`
    -- 3. If it's a type mismatch involving void, check if it cascades
    --    from a known unresolved name; if so, mark as child
    -- 4. Dedup against span_index
end

function IssueRegistry:reports(catalog, source_index)
    -- For each root group, build an ErrorReport via the catalog
end
```

### Component 4: Error Report

An `ErrorReport` is the structured representation of one error the user
sees. It is NOT a string. It is a tree that can be rendered to terminal,
LSP, JSON, or any future format.

```lua
local ErrorReport = {
    code = "E0301",           -- from catalog
    severity = "error",       -- error | warning | info | hint
    phase_context = string,   -- "while type-checking this function"

    primary = {
        span = SourceSpan,
        label = string,       -- annotation on the underline
        message = string,     -- the main error message
    },

    secondary = {             -- zero or more additional spans to show
        {
            span = SourceSpan,
            label = string,   -- why this span is relevant
        },
    },

    notes = {                 -- zero or more prose notes
        {
            message = string, -- no span, just explanation
        },
    },

    suggestions = {           -- zero or more actionable suggestions
        {
            message = string, -- "did you mean `tape`?"
            replacement = {   -- optional: machine-applicable fix
                span = SourceSpan,
                new_text = string,
            },
        },
    },

    children = {              -- zero or more sub-reports (for cascades
        ErrorReport,          -- that are worth showing, like "also
    },                        -- affected: these 3 other sites")
}
```

### Component 5: Presenters

#### Terminal Presenter

This is what users see in the console. Inspired by Rust, Elm, and Zig:

```
error[E0404]: continuation `bad` is not declared by region `exec_slice`
  ┌─ experiments/tapexmem_lab/product_space_machine.mlua:78:36
  │
76│     block do_exec(pc: i32, tape_len: i32, mem_sum: i32, live: i32, fuel: i32)
77│         emit exec_slice(tape, n, pc, tape_len, mem_sum, live, fuel;
  │              ^^^^^^^^^^                                      ~~~~~
78│             again = dispatch, bad = halted)
  │             ~~~~~            ^^^
  │
  = note: `exec_slice` declares these continuations: `again`, `stop`
  = help: did you mean `stop`?
```

Design rules for terminal output:
- Maximum 6 lines of source context (3 before, 3 after, or fewer)
- Primary underline uses `^^^`, secondary uses `~~~`
- Labels on underlines are right-aligned when possible
- Notes use `= note:` prefix
- Suggestions use `= help:` prefix
- Color: red for errors, yellow for warnings, blue for notes, green for help
  (respects NO_COLOR env var)
- Never more than 3 secondary spans per error

#### LSP Presenter

Maps `ErrorReport` to LSP `Diagnostic`:

```lua
function present_lsp(report)
    return {
        range = span_to_lsp_range(report.primary.span),
        severity = severity_to_lsp(report.severity),
        code = report.code,
        source = "moonlift",
        message = report.primary.message
            .. format_notes(report.notes)
            .. format_suggestions(report.suggestions),
        relatedInformation = map(report.secondary, function(s)
            return {
                location = span_to_lsp_location(s.span),
                message = s.label,
            }
        end),
        data = {              -- for code action providers
            suggestions = report.suggestions,
        },
    }
end
```

---

## Error Catalog: Detailed Design by Domain

### E01xx: Parse Errors

Parse errors are the first thing a new user sees. They must be exceptional.

**E0101: Unexpected token**

Current: `"expected 'end', got end of input"`
Proposed:

```
error[E0101]: unexpected end of input
  ┌─ experiment.mlua:15:1
  │
13│     jump again(pc = pc + 1, fuel = fuel - 1)
14│     end
   │     ───
   │
  = note: this `end` closes the region, but there are still
          open blocks: `do_exec`
  = help: add `end` before this line to close `do_exec`, or
          check if a block is missing its terminator
```

The key improvement: the parser tracks the construct stack
(region, func, block, if, switch) so that "expected X" becomes
"you opened Y on line N and it hasn't been closed."

**E0102: Unterminated construct**

```
error[E0102]: region `check_product_invariants` is not terminated
  ┌─ experiment.mlua:8:1
  │
 8│ region check_product_invariants(...)
   │ ────────────────────────────────────
  │
  = note: every block in a region must end with `jump` or `yield`
  = help: the entry block `start` falls through without a `jump`
          or `yield` — add one before the block ends
```

**E0103: Missing keyword**

```
error[E0103]: expected `do` after `switch` expression
  ┌─ experiment.mlua:22:5
  │
22│     switch op
   │     ^^^^^^ ─
   │             expected `do` here
  │
  = note: `switch` requires `do` before the first `case`:
          `switch expr do case ... end`
  = help: write `switch op do`
```

### E02xx: Name Resolution

**E0201: Unresolved name**

```
error[E0201]: unresolved name `taape`
  ┌─ experiment.mlua:42:18
  │
42│     let op: i32 = taape[pc]
  │                    ^^^^^
  │
  = note: `taape` is not defined in this scope
  = help: did you mean `tape`?
```

The "did you mean" uses Levenshtein distance on all in-scope names.
Threshold: distance ≤ 2 and length ≥ 3.

**E0203: Duplicate name**

```
error[E0203]: duplicate block label `dispatch`
  ┌─ experiment.mlua:56:5
  │
48│     block dispatch(pc: i32, ...)
   │            ^^^^^^^^ first defined here
  │
56│     block dispatch(...)
   │            ^^^^^^^^ redefined here
  │
  = note: block labels must be unique within a region
  = help: rename one of the blocks, e.g. `dispatch_after_gc`
```

### E03xx: Type Mismatches

**E0301: Type mismatch**

Current: `"call expected i32, got bool"` (no source, no spans)
Proposed:

```
error[E0301]: type mismatch
  ┌─ experiment.mlua:14:14
  │
13│     let flag: bool = fuel > 0
   │                     ^^^^^^^ this has type `bool`
14│     let step: i32 = flag + 1
   │                     ^^^^ ── expected `i32` because of this
   │
  = note: cannot add `bool` and `i32`
  = help: to convert a boolean to an integer, use a conditional:
          `select(flag, 1, 0)`
```

**E0302: Not callable**

```
error[E0302]: type `i32` is not callable
  ┌─ experiment.mlua:30:5
  │
30│     let x = 42(y)
   │             ^^ this has type `i32`
   │
  = note: only `func` and `closure` types can be called
  = help: did you mean to index? write `42[y]` for array access
```

**E0304: Invalid operator**

```
error[E0304]: operator `+` is not defined for `bool` and `bool`
  ┌─ experiment.mlua:11:13
  │
11│     let x = a + b
   │             ^ both operands are `bool`
   │
  = note: arithmetic operators require numeric types (i8, i16, i32, ...)
  = help: for boolean logic, use `and` / `or`:
          `a and b` or `a or b`
```

### E04xx: Control Flow Errors

This is where Moonlift's unique features demand unique error design.

**E0401: Unterminated block**

```
error[E0401]: block `exec_slice` doesn't exit
  ┌─ experiment.mlua:20:5
  │
20│     block exec_slice(pc: i32, ...)
   │            ^^^^^^^^^^
  │
  = note: every block must end with `jump` or `yield`
  = help: add a `jump` to another block, or `yield` a value
          from the enclosing region
```

**E0403: Continuation not filled**

```
error[E0403]: continuation `stop` is not filled at this emit site
  ┌─ experiment.mlua:78:5
  │
77│     emit exec_slice(tape, n, pc, tape_len, mem_sum, live, fuel;
   │          ^^^^^^^^^^
78│         again = dispatch)
   │         ~~~~~           ← `again` is filled
   │
  = note: `exec_slice` declares continuations: `again`, `stop`
  = note: `stop` expects arguments: `code: i32`
  = help: add a continuation fill:
          `stop = halted` (where `halted` is a block that
          accepts `code: i32`)
```

**E0404: Continuation type mismatch**

```
error[E0404]: continuation `again` type mismatch
  ┌─ experiment.mlua:78:14
  │
76│     block dispatch(pc: i32, tape_len: i32, mem_sum: i32, ...)
77│         emit exec_slice(tape, n, pc, tape_len, mem_sum, live, fuel;
78│             again = mode_select)
   │             ~~~~~   ^^^^^^^^^^
   │
  = note: continuation `again` expects: `pc: i32, tape_len: i32,
          mem_sum: i32, live: i32, phase: i32, fuel: i32`
  = note: block `mode_select` accepts: `pc: i32, tape_len: i32,
          mem_sum: i32, live: i32, phase: i32, fuel: i32`
  = note: the parameter lists match ✓ — but `mode_select` is
          outside this region's control graph
  = help: move `mode_select` inside this region, or use a
          different block that is reachable from here
```

**E0405: Irreducible control flow**

```
error[E0405]: irreducible control flow in this region
  ┌─ experiment.mlua:60:5
  │
60│     region my_region(...) entry start() ...
   │            ^^^^^^^^^^
   │
  = note: control flow is irreducible when two blocks both
          jump to each other without a common dominator
  = note: blocks `A` and `B` form an irreducible cycle:
          A → B → A
  = help: restructure so one block dominates the other:
          e.g., merge A and B, or add a dispatch block
          that chooses between them
```

**E0407: Yield outside region**

```
error[E0407]: `yield` used outside a region
  ┌─ experiment.mlua:15:5
  │
15│     yield 42
   │     ^^^^^
   │
  = note: `yield` can only be used inside a `region` or a
          `return region -> T` expression
  = help: did you mean `return`? Functions use `return`,
          not `yield`
```

### E05xx: Host/Struct Errors

**E0501: Duplicate field**

```
error[E0501]: duplicate field `mode` in struct `IteratorState`
  ┌─ experiment.mlua:8:5
  │
 5│ local IteratorState = struct
 6│     mode: i32
   │     ^^^^ first definition
  │
 8│     mode: i32
   │     ^^^^ duplicate
  │
  = help: remove or rename the duplicate field
```

### E07xx: Splice/Metaprogramming Errors

```
error[E0701]: splice `@{err_code}` produced type `string`,
              but this position requires `i32`
  ┌─ experiment.mlua:45:38
  │
45│         jump err(pos = pos, code = @{err_code})
   │                                      ^^^^^^^^^
   │
  = note: splice values must match the type expected at their
          position — there is no implicit conversion
  = help: the Lua expression bound to `err_code` must evaluate
          to an `i32` value, not a `string`
```

---

## Implementation Strategy

### Phase 1: SourceSpan propagation

Replace all `(offset, line, col)` with `SourceSpan` throughout the
issue types. Update `ParseIssue`, all `TypeIssue` variants,
`ControlReject` variants, `HostIssue` variants, and `BackIssue`
variants to carry `SourceSpan`.

The parser already has token start/stop positions. The typechecker
has surface nodes with position information. These just need to be
threaded into the issue types instead of being discarded.

**Files to modify:**
- `schema/parse.lua` — ParseIssue gets SourceSpan
- `schema/tree.lua` — TypeIssue variants get SourceSpan
- `schema/editor.lua` — DiagnosticFact uses SourceSpan
- `parse.lua` — Parser.issue() creates SourceSpan from token position
- `tree_typecheck.lua` — type issues carry spans from surface nodes
- `tree_control_facts.lua` — control issues carry region/label spans

### Phase 2: Error Catalog

Create the catalog module. Map each internal issue kind to its catalog
entry. This is where the human-readable templates live.

**New file:**
- `lua/moonlift/error_catalog.lua`

### Phase 3: Issue Registry

Create the registry that collects issues, groups by root cause,
deduplicates, and produces ErrorReport trees.

**New file:**
- `lua/moonlift/issue_registry.lua`

### Phase 4: Report Builder

Create the report builder that takes a raw issue + catalog entry +
source text and produces a fully-resolved ErrorReport with spans,
notes, suggestions, and "did you mean?" candidates.

**New file:**
- `lua/moonlift/error_report.lua`

### Phase 5: Terminal Presenter

Create the pretty-printer for terminal output. This is the visual
identity of the error system — it must look great.

**New file:**
- `lua/moonlift/present_terminal.lua`

### Phase 6: LSP Presenter

Rewrite the LSP diagnostic path to go through ErrorReport → LSP
Diagnostic. This replaces the current `editor_diagnostic_facts.lua`
pipeline for LSP consumers.

**File to modify:**
- `lua/moonlift/editor_diagnostic_facts.lua` — use ErrorReport as input

### Phase 7: "Did you mean?" engine

Levenshtein-based candidate search for:
- Unresolved names → in-scope bindings
- Unknown continuations → declared continuations
- Unknown block labels → existing labels in the region
- Unknown struct fields → declared fields

**New file:**
- `lua/moonlift/suggest_candidates.lua`

---

## What This Replaces

| Current | Replaced By |
|---------|-------------|
| `diagnostic.lua` `render()` | `present_terminal.lua` |
| `diagnostic.lua` `detect_hint()` | `error_catalog.lua` templates |
| `diagnostic.lua` `from_error()` | `issue_registry.lua` + `error_report.lua` |
| `editor_diagnostic_facts.lua` ad-hoc messages | `error_catalog.lua` templates |
| `editor_diagnostic_facts.lua` cascade suppression | `issue_registry.lua` root-cause grouping |
| Bare `(offset, line, col)` in issues | `SourceSpan` |
| `ParseIssue(message, offset, line, col)` | `ParseIssue(message, SourceSpan)` |
| Type errors with no source position | Type errors with spans from surface nodes |

## What This Preserves

- The ASDL schema types for issues (ParseIssue, TypeIssue, ControlReject,
  HostIssue, BackValidationIssue) — these are internal compiler facts and
  remain as-is
- The PVM phase structure — the registry is just a new consumer of phase outputs
- The LSP diagnostic protocol — we just build better diagnostics to send
- The `editor_diagnostic_facts.lua` phase structure — it continues to produce
  DiagnosticFacts, but now from ErrorReports instead of ad-hoc strings

---

## The Contract

This design has one inviolable contract:

> Every error the compiler emits must contain:
> 1. The source code where the error occurs
> 2. A pointer at the exact cause
> 3. A human-readable explanation of what went wrong
> 4. At least one actionable suggestion for how to fix it

If we can't provide all four, we don't emit the error — we log it
internally and emit a generic "internal compiler error" with a request
to file a bug. Never show the user a bare line number with no context.

This is the standard that makes a language feel trustworthy. This is
what separates Rust and Elm from C++ and Java. Moonlift — a language
where control flow is typed, where regions and continuations are
first-class — deserves error messages that are just as thoughtful as
its type system.
