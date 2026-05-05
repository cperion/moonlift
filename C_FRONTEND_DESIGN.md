# Moonlift C Frontend — Target Architecture

**Status:** target design. This document is normative for the C-to-MoonTree
compiler.

**Goal:** accept C99 source (preprocessed or with preprocessor directives) and
lower it to MoonTree ASDL facts, making C a first-class source language in the
Moonlift pipeline. C and Moonlift share one type system, one optimizer, one
backend.

---

## Table of Contents

1. [Philosophy & Motivation](#1-philosophy--motivation)
2. [Scope and Non-Goals](#2-scope-and-non-goals)
3. [Pipeline Architecture](#3-pipeline-architecture)
4. [Tokenizer](#4-tokenizer)
5. [Preprocessor — `cpp_expand` PVM Phase](#5-preprocessor--cpp_expand-pvm-phase)
6. [C Parser](#6-c-parser)
7. [C Type System](#7-c-type-system)
8. [C AST → MoonTree Lowering](#8-c-ast--moontree-lowering)
9. [Integration with the Moonlift Module System](#9-integration-with-the-moonlift-module-system)
10. [Diagnostics](#10-diagnostics)
11. [Implementation Phases](#11-implementation-phases)
12. [Test Strategy](#12-test-strategy)
13. [Complete Examples](#13-complete-examples)
14. [Design Decisions](#14-design-decisions)
15. [Appendix: Operator Precedence Table](#15-appendix-operator-precedence-table)

---

## 1. Philosophy & Motivation

### 1.1 Why a C frontend

Moonlift is lower-level than C. Every C construct decomposes into explicit
Moonlift operations. The C abstract machine has layers of implicit behavior that
Moonlift makes explicit:

| C | Hidden semantics | Moonlift equivalent |
|---|---|---|
| `x + y` on `int` | Signed overflow is UB | `x + y` with wrapping (or trapped) |
| `a[i]` | Pointer decay, scale by `sizeof`, no bounds | `*(a + as(index, i))` or view indexing |
| `struct { char a; int b; }` | Padding, platform-dependent | `CLayoutFact` with explicit field offsets |
| `for (int i = 0; i < n; i++)` | Implicit loop shape | `block` + `jump` + `yield` with named labels |
| `x = y` (struct) | Implicit `memcpy` | Explicit `memcpy` with known size |
| `f(a, b, c)` | Argument promotion, default conversions | `as()` conversions at every site |
| `switch` fallthrough | Implicit control transfer | Explicit `jump` between case blocks |

Lowering C to MoonTree isn't translation between peers — it's **decompilation of
the C abstract machine into explicit lower-level operations.** Every C construct
becomes an explicit MoonTree fact (block, jump, yield, var, let, switch).
The MoonTree then passes through typecheck, lower, and validate like any
hand-written Moonlift code. There is no boundary.

### 1.2 One pipeline, two surface syntaxes

```
.mlua source ──→ MoonTree ──┐
C source ──────→ MoonTree ──┤
                             ├──→ typecheck ──→ lower ──→ BackCmd ──→ Cranelift
                             └──→ validate ──→ LSP facts ──→ editor
```

- **Parse:** C parser produces a C-specific AST (`CAst`)
- **cpp_expand:** PVM phase that expands macros, includes files, evaluates conditionals
- **cimport:** PVM phase that registers types with `ffi.cdef` and queries layout
- **lower_c:** PVM phase that walks the C AST and emits MoonTree facts

After lowering, the module contains ordinary MoonTree nodes alongside any
hand-written Moonlift islands. The typechecker, validator, optimizer, and
emphasis emit don't know — and don't care — that the MoonTree came from C.

### 1.3 Design Principles

1. **C semantics are decompiled, not emulated.** The lowering pass makes every
   implicit C behavior explicit. When in doubt about what the C abstract machine
   does, emit the explicit operation rather than hoping the optimizer infers it.

2. **MoonTree is the universal IR.** C and `.mlua` produce the same kind of
   facts. No separate C type system, no separate lowering path, no separate
   optimizer.

3. **The preprocessor is a PVM phase.** `#define`, `#include`, `#if` are
   first-class AST nodes consumed by `cpp_expand`. Spans are preserved.
   Diagnostics reference original source, not preprocessed output.

4. **The parser is separate from the preprocessor.** The parser produces a
   directive-aware AST. The preprocessor phase expands it. This separation
   makes both components testable independently.

5. **`ffi.cdef` is the C type authority (unchanged).** The C frontend reuses the
   same type registration and layout queries already designed for `import c`.

6. **Lua is the staging language, not the compiler host.** The C frontend is
   written in Lua and runs as PVM phases. It is not a separate binary or a
   Rust module.

---

## 2. Scope and Non-Goals

### 2.1 In scope

- C99 source language with the following additions:
  - GNU statement expressions `({ ... })`
  - Designated initializers (C99 standard)
  - Compound literals (C99 standard)
  - `//` comments (C99 standard)
  - `inline` keyword (C99, semantics as C99 — not GNU inline)
  - Mixed declarations and statements (C99)
  - `long long` (C99 standard)
  - `_Bool` (C99 standard)
  - Flexible array members (C99 standard)
- Full C preprocessor:
  - Object-like and function-like `#define` / `#undef`
  - `#include` with cycle and missing-file detection
  - `#if` / `#ifdef` / `#ifndef` / `#elif` / `#else` / `#endif`
  - `##` token pasting
  - `#` stringification
  - Built-in macros: `__FILE__`, `__LINE__`, `__DATE__`, `__TIME__`, `__STDC__`
  - `#pragma` (parsed and recorded; pragmas may be selectively implemented)
  - `#error`
- Post-preprocessing C declarations mirroring `import c` coverage:
  - Typedefs, structs, unions, enums, function prototypes, pointers, arrays,
    function pointers, bitfields, qualifiers (`const`, `restrict`)
- Complete C statement and expression grammar for bodies of imported functions:
  - Functions with bodies (`import c "int f(int x) { return x + 1; }"`)
  - Static and inline functions
  - `if`/`else`, `for`, `while`, `do`/`while`, `switch`/`case`/`default`,
    `goto`, `break`, `continue`, `return`
  - All C operators with correct precedence and associativity
- Production of MoonTree ASDL from lowered C bodies
- Integration with the existing Moonlift typecheck, lower, validate, emit pipeline
- Cross-language LSP: go-to-definition from Moonlift into C, hover on C
  expressions showing lowered MoonTree, rename across both languages

### 2.2 Explicitly out of scope

| Feature | Reason |
|---------|--------|
| C11 `_Generic` | Rarely used; deferred |
| C11 `_Alignas`, `_Alignof`, `_Static_assert` | Can be mapped later; low priority |
| C11 `_Atomic` and `_Thread_local` | No Cranelift backend support for atomics/thread-locals |
| C11 `_Noreturn` | Extern functions can simply not return; low priority |
| VLAs (variable-length arrays) | Cranelift supports dynamic stack slots, but ABI implications are complex. Deferred. |
| `long double` (80/128-bit float) | Cranelift has no f128 type. Deferred. |
| `_Complex` | Cranelift has no complex type. Not supported. |
| `alloca` | Equivalent to VLAs. Deferred. |
| Computed goto (GNU labels-as-values) | Requires runtime label-to-address mapping. Not supported. |
| Nested functions (GNU) | Requires trampolines or static chain. Not supported. |
| Inline assembly | Backend-specific. Not supported. |
| `setjmp`/`longjmp` | Runtime library call. Extern only. |
| C++ (any version) | Separate language. Not supported. |
| K&R function definitions | Pre-standard. Not supported. |
| Trigraphs | Not supported. |
| `#pragma` beyond recording | Selective implementation only. |

### 2.3 Target surface

The C frontend targets the **C99 standard plus the GNU extensions commonly used
in well-formed library headers:** `({...})`, designated initializers, and
`__attribute__((packed))` (passed through to `ffi.cdef` for layout). The goal
is to cover the TCC-accepted surface: code that compiles with `tcc` should
compile with the Moonlift C frontend, modulo the explicit exclusions above.

---

## 3. Pipeline Architecture

### 3.1 Full pipeline

```
C source text
     │
     ▼
┌────────────┐
│  c_lexer   │  Tokenize: keywords, identifiers, numbers, strings,
│            │  punctuators, preprocessor directives
└─────┬──────┘
      │ token stream
      ▼
┌────────────┐
│  c_parse   │  Parse into CAst: declarations, definitions, expressions,
│            │  statements, preprocessor directive nodes
└─────┬──────┘
      │ CAst ASDL
      ▼
┌────────────┐
│ cpp_expand │  PVM phase: expand macros, include files, evaluate
│            │  conditionals, prune dead branches
└─────┬──────┘
      │ expanded CAst (no preprocessor directives)
      ▼
┌────────────┐
│  cimport   │  PVM phase: register C types via ffi.cdef, query layout
│            │  facts (size, align, offsets, bitfields)
└─────┬──────┘
      │ CAst + CLayoutFact + CTypeFact + CExternFunc facts
      ▼
┌────────────┐
│ lower_c    │  PVM phase: walk CAst function bodies, emit MoonTree
│            │  function/block/stmt/expr facts
└─────┬──────┘
      │ MoonTree facts + C layout facts
      ▼
┌────────────┐
│  typecheck │  Existing Moonlift typechecker (unchanged)
└─────┬──────┘
      │
      ▼
   (lower → validate → emit, all unchanged)
```

### 3.2 Phase responsibilities

| Phase | Input | Output | Side effects |
|-------|-------|--------|-------------|
| `c_lexer` | C source string | Token stream | None |
| `c_parse` | Token stream | `CAst.TranslationUnit` | None |
| `cpp_expand` | `CAst.TranslationUnit` | `CAst.TranslationUnit` (no directives) | Macro table, include paths |
| `cimport` | `CAst.TranslationUnit` | `CTypeFact`, `CLayoutFact`, `CExternFunc`, `CLibrary` | `ffi.cdef`, `ffi.typeof`, `ffi.sizeof`, `ffi.alignof`, `ffi.offsetof` |
| `lower_c` | Expanded `CAst` + C facts | `MoonTree` functions, blocks, statements, expressions | Populates module's function and type tables. Uses `CAbiPlan` facts from cimport for extern call lowering. |
| `typecheck` | `MoonTree` + `MoonType` | Validated MoonTree | Existing, unchanged |

### 3.3 Integration with `.mlua` hosted pipeline

The `import c` declaration in `.mlua` source already carries a cdef string. The
extension is that the string may now contain function bodies and preprocessor
directives:

```moonlift
import c [[
    #define CLAMP(x, lo, hi) ((x) < (lo) ? (lo) : (x) > (hi) ? (hi) : (x))

    static inline int clamp(int x, int lo, int hi) {
        return CLAMP(x, lo, hi);
    }
]]
```

The hosted pipeline's cimport phase detects whether the cdef string contains
function bodies or preprocessor directives. If it does, it routes through the C
frontend pipeline; if it's pure declarations, it uses the declaration-only
parser (`lib/c_decl_parse.lua`).

The C frontend can also accept whole C files. This is a distinct grammar
form from the inline cdef string — the argument is a file path, not C source:

```text
import_c_file ::= "import" "c" string_lit   -- when string ends in .c or .h
```

```moonlift
import c "lib/sqlite3.c"      -- entire C file, parsed and lowered
import c "lib/sqlite3.h"      -- header file, declarations only
```

Disambiguation: if the string argument ends in `.c` or `.h`, it is treated as
a file path. Otherwise it is treated as inline C source. When `from "lib"`
is present before the cdef string, it names a shared library for extern
symbol resolution and link facts.

---

## 4. Tokenizer

### 4.1 Token types

```lua
A.sum "CToken" {
    A.variant "CTokIdent"       { A.field "name" "string" },
    A.variant "CTokKeyword"     { A.field "kw" "CKeyword" },
    A.variant "CTokIntLiteral"  { A.field "raw" "string", A.field "suffix" "string" },
    A.variant "CTokFloatLiteral"{ A.field "raw" "string", A.field "suffix" "string" },
    A.variant "CTokCharLiteral" { A.field "raw" "string" },
    A.variant "CTokStringLiteral"{ A.field "raw" "string", A.field "prefix" "string" },
    A.variant "CTokPunct"       { A.field "text" "string" },
    A.variant "CTokDirective"   { A.field "kind" "CDirectiveKind" },
    A.variant "CTokNewline"     {},
    A.variant "CTokEOF"         {},
}
```

### 4.2 Keywords

```lua
A.sum "CKeyword" {
    A.variant "CKwAuto",      A.variant "CKwBreak",     A.variant "CKwCase",
    A.variant "CKwChar",      A.variant "CKwConst",     A.variant "CKwContinue",
    A.variant "CKwDefault",   A.variant "CKwDo",        A.variant "CKwDouble",
    A.variant "CKwElse",      A.variant "CKwEnum",      A.variant "CKwExtern",
    A.variant "CKwFloat",     A.variant "CKwFor",       A.variant "CKwGoto",
    A.variant "CKwIf",        A.variant "CKwInline",    A.variant "CKwInt",
    A.variant "CKwLong",      A.variant "CKwRegister",  A.variant "CKwRestrict",
    A.variant "CKwReturn",    A.variant "CKwShort",     A.variant "CKwSigned",
    A.variant "CKwSizeof",    A.variant "CKwStatic",    A.variant "CKwStruct",
    A.variant "CKwSwitch",    A.variant "CKwTypedef",   A.variant "CKwUnion",
    A.variant "CKwUnsigned",  A.variant "CKwVoid",      A.variant "CKwVolatile",
    A.variant "CKwWhile",
    A.variant "CKwBool",        -- _Bool (C99)
    A.variant "CKwComplex",     -- _Complex (C99, recognized but rejected)
    A.variant "CKwInline2",     -- __inline (alternate spelling)
    A.variant "CKwRestrict2",   -- __restrict (alternate spelling)
}
```

All keywords are reserved. They cannot be used as identifiers. `_Complex` is
recognized as a keyword so that its use produces a clear `c_complex_unsupported`
diagnostic rather than a confusing parse error.

### 4.3 Preprocessor directives

Directives are recognized at the start of a logical line (after optional
whitespace and after line continuations `\` are resolved). Multi-line
directives use `\` continuation:

```c
#define LONG_MACRO(a, b) \
    do { \
        something(a); \
        something_else(b); \
    } while (0)
```

The tokenizer handles `\` line continuation by treating `\\\n` as whitespace.
The resulting `CTokDirective` carries the full body tokens.

```lua
A.sum "CDirectiveKind" {
    A.variant "CDirDefine",   A.variant "CDirUndef",
    A.variant "CDirInclude",  A.variant "CDirIf",
    A.variant "CDirIfdef",    A.variant "CDirIfndef",
    A.variant "CDirElif",     A.variant "CDirElse",
    A.variant "CDirEndif",    A.variant "CDirError",
    A.variant "CDirPragma",   A.variant "CDirLine",
}
```

### 4.4 Tokenizer rules

- Identifiers: `[a-zA-Z_][a-zA-Z0-9_]*`, checked against keyword set
- Integer literals: decimal, hex (`0x`), octal (`0`). Suffixes: `u`, `l`, `ll`, `ul`, `ull` (case-insensitive). No size computation — raw string preserved.
- Float literals: decimal with optional exponent, hex floats. Suffixes: `f`, `l`.
- Character literals: `'c'`, `'\n'`, `'\x41'`, `'\0'`. Multi-byte character constants are accepted and preserved as raw integers.
- String literals: `"hello"`, `L"wide"`. Adjacent string literals are concatenated at the parser level.
- Comments: `/* ... */` (nesting not supported per C99), `// ...` (to end of line). Replaced by single space.
- Punctuators: all C99 punctuators, including multi-character (`->`, `++`, `+=`, `<<=`, `...`).

### 4.5 Error recovery

The tokenizer attempts to produce a token stream even for malformed input.
Unrecognized characters produce a `c_unrecognized_character` diagnostic and
are treated as whitespace. Unclosed comments and strings produce diagnostics
and terminate at end of line or end of file.

---

## 5. Preprocessor — `cpp_expand` PVM Phase

### 5.1 Architecture

The preprocessor is a PVM phase. It consumes a `CAst.TranslationUnit` with
interleaved directive and declaration nodes, and produces a
`CAst.TranslationUnit` with only declaration nodes (no directives).

```
cpp_expand(translation_unit) → expanded_translation_unit
```

It is pure: given the same input and the same include file contents, it produces
the same output. File system access for `#include` goes through a virtual file
system provider injected into the phase context.

### 5.2 Macro table

The preprocessor maintains a macro table keyed by macro name:

```lua
A.product "CMacro" {
    A.field "name" "string",
    A.field "kind" "CMacroKind",
    A.field "body" (A.many "CAst.CToken"),  -- token sequence
    A.field "location" "MoonSource.SourceRange",   -- #define location
    A.unique,
}

A.sum "CMacroKind" {
    A.variant "CObjectLike",
    A.variant "CFunctionLike" {
        A.field "params" (A.many "string"),
        A.field "variadic" "boolean",           -- ... parameter
    },
}
```

**Initial state:** Standard predefined macros are registered before expansion
begins:

| Macro | Value |
|-------|-------|
| `__STDC__` | `1` |
| `__STDC_VERSION__` | `199901L` (C99) |
| `__FILE__` | Dynamic (current file) |
| `__LINE__` | Dynamic (current line) |
| `__DATE__` | `"Mmm dd yyyy"` (build date) |
| `__TIME__` | `"hh:mm:ss"` (build time) |
| `__moonlift__` | `1` |
| `__MOONLIFT_C_VERSION__` | `199901L` |

### 5.3 Expansion algorithm

Expansion is a recursive token replacement process:

1. **Scan tokens** in the current expansion context.
2. **If the token is a macro name** that is currently *not* marked as
   "disabled for expansion" (to prevent recursive expansion):
   - **Object-like macro:** replace the token with the macro's body tokens.
     Mark the macro name as disabled. Re-scan the replacement tokens.
   - **Function-like macro:** if the next non-whitespace token is `(`, collect
     the argument list (comma-separated, respecting nested parentheses).
     Substitute each parameter in the body with the corresponding argument
     tokens (after expanding the arguments). Mark the macro name as disabled.
     Re-scan the result.
3. **`#` operator in function-like macro body:** stringify the next parameter
   token. The argument's tokens (after expansion but before re-scan) are turned
   into a single string literal with escapes for `"` and `\`.
4. **`##` operator in function-like macro body:** concatenate the token before
   `##` with the token after `##`. Both tokens come from the argument
   substitution. The result is a single token. If either operand is a
   placeholder (empty argument), the other token is used unchanged.
5. **`#undef`:** removes the macro from the table. Undefining a non-existent
   macro is silently ignored (C99 behavior).
6. **Expansion stops** when no more macro replacements occur.

### 5.4 `#include` processing

```
#include <stdio.h>     -- system include, search system paths
#include "mylib.h"     -- local include, search relative to current file first
```

The preprocessor resolves the include path:

1. For `"..."` includes, resolve relative to the directory of the including file.
2. For `<...>` includes, search a configurable system include path list.
3. If found, read the file, parse it into a `CAst.TranslationUnit`, recursively
   expand it, and replace the `#include` directive with the resulting AST.
4. If not found, emit `c_include_not_found` diagnostic.

**Cycle detection:** A file already in the current include stack is silently
skipped (standard C behavior). The include stack prevents infinite recursion.

**Guards:** Standard `#ifndef` / `#define` include guards are handled naturally
by the macro table and conditional evaluation. No special guard optimization is
required for correctness, but the macro table ensures the body is expanded only
once.

### 5.5 Conditional compilation

```
#if constant_expression
#if defined(MACRO_NAME)    -- equivalent to #ifdef
#if defined MACRO_NAME     -- alternate form
#elif constant_expression
#else
#endif
```

The preprocessor evaluates `constant_expression` using a minimal C integer
constant expression evaluator:

- All macros in the expression are expanded first
- After expansion, remaining identifiers are replaced with `0`
- The resulting expression is an integer constant expression with standard C
  operators: `+`, `-`, `*`, `/`, `%`, `<<`, `>>`, `&`, `|`, `^`, `&&`, `||`,
  `!`, `~`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `?:`, parentheses, integer
  literals
- The `defined` operator returns `1` if the macro name is defined, `0` otherwise
- Evaluation uses 64-bit signed integer arithmetic (matching typical C
  preprocessor behavior)
- Non-constant subexpressions (e.g., `sizeof`, casts) are rejected with
  `c_if_expression_not_constant`

Exactly one branch is kept; all others are discarded.

### 5.6 `#pragma` and `#error`

- `#pragma` is parsed and recorded as a `CPragma` node in the AST. Specific
  pragmas may be handled by downstream phases (e.g., `#pragma once` can be
  treated as an include guard). Unrecognized pragmas are silently ignored
  (standard C behavior).
- `#error` produces a `c_error_directive` diagnostic with the directive's
  message string and stops further processing of that translation unit.

### 5.7 Built-in macros

| Macro | Expansion |
|-------|-----------|
| `__FILE__` | String literal of the current source file path |
| `__LINE__` | Integer literal of the current source line (1-based) |
| `__DATE__` | String literal `"Mmm dd yyyy"` of compilation date |
| `__TIME__` | String literal `"hh:mm:ss"` of compilation time |
| `__STDC__` | Integer literal `1` |
| `__STDC_VERSION__` | Integer literal `199901L` |
| `__moonlift__` | Integer literal `1` |
| `__MOONLIFT_C_VERSION__` | Integer literal `199901L` |
| `__COUNTER__` | Integer literal, increments by 1 each expansion (GNU extension) |
| `__VA_ARGS__` | Variable arguments in variadic function-like macros (C99) |

`__FILE__` and `__LINE__` are not macros in the macro table — they are resolved
dynamically by the expander at each use site based on the current token location.

### 5.8 Diagnostics from `cpp_expand`

| Diagnostic | Meaning |
|-----------|---------|
| `c_include_not_found` | `#include` could not resolve the file |
| `c_if_expression_not_constant` | `#if` expression contains non-constant tokens |
| `c_error_directive` | `#error` directive encountered |
| `c_macro_redefined` | `#define` with different body than prior definition |
| `c_macro_params_mismatch` | Function-like macro called with wrong argument count |
| `c_paste_invalid_token` | `##` produced an invalid token |
| `c_unterminated_directive` | `\` at end of file in multi-line directive |

### 5.9 Phase properties

- **Pure:** no side effects on the filesystem beyond the injected VFS provider.
- **Incremental:** macro table can be cached per translation unit. Only
  re-expand when a `#define`/`#undef` changes or an included file changes.
- **Debuggable:** pre- and post-expansion AST are inspectable as ASDL facts.
  The `--dump-cpp` flag produces the expanded token stream for debugging.

---

## 6. C Parser

### 6.1 AST structure

The parser produces a `CAst.TranslationUnit`:

```lua
A.product "CAst.TranslationUnit" {
    A.field "items" (A.many "CAst.TopLevelItem"),
    A.unique,
}

A.sum "CAst.TopLevelItem" {
    A.variant "CATopDecl"    { A.field "decl" "CAst.Decl" },
    A.variant "CATopFuncDef" { A.field "func" "CAst.FuncDef" },
    A.variant "CATopCpp"     { A.field "directive" "CAst.CppDirective" },
}
```

### 6.2 Declarations

```lua
A.product "CAst.Decl" {
    -- typedef:    typedef int my_int;
    -- variable:   int x;
    -- function:   int f(int a, double b);
    -- struct:     struct point { int x, y; };
    -- union:      union val { int i; float f; };
    -- enum:       enum color { RED, GREEN, BLUE };
    A.field "storage" (A.optional "CAst.StorageClass"),
    A.field "qualifiers" (A.many "CAst.Qualifier"), -- const, restrict, inline
    A.field "type_spec" "CAst.TypeSpec",
    A.field "declarators" (A.many "CAst.Declarator"),
    A.unique,
}

A.sum "CAst.StorageClass" {
    A.variant "CStorageTypedef",
    A.variant "CStorageExtern",
    A.variant "CStorageStatic",
    A.variant "CStorageAuto",
    A.variant "CStorageRegister",
}

A.sum "CAst.Qualifier" {
    A.variant "CQualConst",
    A.variant "CQualRestrict",
    A.variant "CQualVolatile",
    A.variant "CQualInline",
}

A.sum "CAst.TypeSpec" {
    A.variant "CTyVoid",
    A.variant "CTyChar",
    A.variant "CTyShort",
    A.variant "CTyInt",
    A.variant "CTyLong",
    A.variant "CTyLongLong",
    A.variant "CTyFloat",
    A.variant "CTyDouble",
    A.variant "CTyLongDouble",
    A.variant "CTySigned",
    A.variant "CTyUnsigned",
    A.variant "CTyBool",                   -- _Bool
    A.variant "CTyComplex",                -- _Complex (parsed for diagnostics; rejected by cimport)
    A.variant "CTyStructOrUnion" {
        A.field "kind" "CAst.StructKind",  -- "struct" or "union"
        A.field "name" (A.optional "string"),  -- tag (optional)
        A.field "members" (A.optional (A.many "CAst.FieldDecl")),  -- body (optional for forward decl)
    },
    A.variant "CTyEnum" {
        A.field "name" (A.optional "string"),
        A.field "enumerators" (A.optional (A.many "CAst.Enumerator")),
    },
    A.variant "CTyNamed" { A.field "name" "string" },  -- typedef reference
    A.variant "CTyTypeof" { A.field "expr" "CAst.Expr" },  -- GCC typeof
}
```

Type specifiers combine according to C rules: `long long`, `unsigned int`,
`long double`, etc. The parser records the individual specifier tokens; the
semantic analysis in `cimport` determines the ultimate type.

### 6.3 Declarators

The C declarator grammar is the hardest part of the parser. It maps a name
through a series of type constructors: pointers, arrays, function parameters.

```lua
A.product "CAst.Declarator" {
    A.field "name" (A.optional "string"),  -- nil for abstract declarators
    A.field "derived" (A.many "CAst.DerivedType"),
    A.field "initializer" (A.optional "CAst.Initializer"),
    A.unique,
}

A.product "CAst.FieldDecl" {
    A.field "type_spec" "CAst.TypeSpec",
    A.field "declarators" (A.many "CAst.FieldDeclarator"),
    A.unique,
}

A.product "CAst.FieldDeclarator" {
    A.field "declarator" (A.optional "CAst.Declarator"),  -- nil for unnamed bitfield
    A.field "bit_width" (A.optional "CAst.Expr"),         -- nil for non-bitfield
    A.unique,
}

A.sum "CAst.DerivedType" {
    A.variant "CDerivedPointer" {
        A.field "qualifiers" (A.many "CAst.Qualifier"),  -- const, restrict, volatile
    },
    A.variant "CDerivedArray" {
        A.field "size" (A.optional "CAst.Expr"),  -- nil for []
    },
    A.variant "CDerivedFunction" {
        A.field "params" (A.many "CAst.ParamDecl"),
        A.field "variadic" "boolean",    -- true if ... present
    },
}
```

**Parsing approach:** recursive-descent with `declarator()` consuming the
"inside-out" C declaration style. The parser maintains a stack of derived types
and applies them left-to-right after the name is parsed:

```
int (*f[10])(void)

Parse:  type_spec: int
Declarator: name="f"
  Derived: array[10]
  Derived: pointer
  Derived: function(void)
 → f is array[10] of pointer to function(void) returning int
```

This is a standard C declarator parser. Reference: K&R Appendix A, or the
C99 standard §6.7.5.

Referenced types that complete the AST:

```lua
A.sum "CAst.StructKind" {
    A.variant "CStructKindStruct",
    A.variant "CStructKindUnion",
}

A.product "CAst.Enumerator" {
    A.field "name" "string",
    A.field "value" (A.optional "CAst.Expr"),  -- explicit = expr, or nil for auto
    A.unique,
}

A.product "CAst.ParamDecl" {
    A.field "type_spec" "CAst.TypeSpec",
    A.field "qualifiers" (A.many "CAst.Qualifier"),
    A.field "declarator" (A.optional "CAst.Declarator"),  -- nil for abstract params
    A.unique,
}

A.product "CAst.FuncDef" {
    A.field "storage" (A.optional "CAst.StorageClass"),
    A.field "qualifiers" (A.many "CAst.Qualifier"),  -- inline, etc.
    A.field "type_spec" "CAst.TypeSpec",              -- return type specifier
    A.field "declarator" "CAst.Declarator",           -- function name + params via DerivedFunction
    A.field "body" "CAst.Stmt",                       -- compound statement
    A.unique,
}

A.sum "CAst.CppDirective" {
    A.variant "CCppDefine" {
        A.field "macro" "CAst.CMacro",
    },
    A.variant "CCppUndef" {
        A.field "name" "string",
    },
    A.variant "CCppInclude" {
        A.field "kind" "CAst.CIncludeKind",  -- angle-bracket or quoted
        A.field "path" "string",
    },
    A.variant "CCppIf" {
        A.field "tokens" (A.many "CAst.CToken"),  -- condition tokens
    },
    A.variant "CCppIfdef"  { A.field "name" "string" },
    A.variant "CCppIfndef" { A.field "name" "string" },
    A.variant "CCppElif" {
        A.field "tokens" (A.many "CAst.CToken"),
    },
    A.variant "CCppElse",
    A.variant "CCppEndif",
    A.variant "CCppError" { A.field "message" "string" },
    A.variant "CCppPragma" { A.field "tokens" (A.many "CAst.CToken") },
    A.variant "CCppLine" {
        A.field "line" "number",
        A.field "file" (A.optional "string"),
    },
}

A.sum "CAst.CIncludeKind" {
    A.variant "CIncludeAngle",   -- <file.h>
    A.variant "CIncludeQuoted",  -- "file.h"
}
```

A **type name** is a type specifier plus an abstract declarator (no name).
It appears in `sizeof(type)`, casts `(type)expr`, and compound literals
`(type){init}`:

```lua
A.product "CAst.TypeName" {
    A.field "type_spec" "CAst.TypeSpec",
    A.field "derived" (A.many "CAst.DerivedType"),  -- abstract declarator
    A.unique,
}
```

This allows `sizeof(int (*)(void))` and `(int[3]){1,2,3}` to be represented.

### 6.4 Expressions

Full C expression grammar with all operators. The parser uses precedence-based
recursive descent with the standard C precedence table (see Appendix).

```lua
A.sum "CAst.Expr" {
    -- Literals
    A.variant "CEIntLit"    { A.field "raw" "string", A.field "suffix" "string" },
    A.variant "CEFloatLit"  { A.field "raw" "string", A.field "suffix" "string" },
    A.variant "CECharLit"   { A.field "raw" "string" },
    A.variant "CEStrLit"    { A.field "raw" "string" },
    A.variant "CEBoolLit"   { A.field "value" "boolean" },

    -- Primary
    A.variant "CEIdent"     { A.field "name" "string" },
    A.variant "CEParen"     { A.field "expr" "CAst.Expr" },

    -- Unary
    A.variant "CEPreInc"    { A.field "operand" "CAst.Expr" },  -- ++x
    A.variant "CEPreDec"    { A.field "operand" "CAst.Expr" },  -- --x
    A.variant "CEPostInc"   { A.field "operand" "CAst.Expr" },  -- x++
    A.variant "CEPostDec"   { A.field "operand" "CAst.Expr" },  -- x--
    A.variant "CEAddrOf"    { A.field "operand" "CAst.Expr" },  -- &x
    A.variant "CEDeref"     { A.field "operand" "CAst.Expr" },  -- *p
    A.variant "CEPlus"      { A.field "operand" "CAst.Expr" },  -- +x
    A.variant "CEMinus"     { A.field "operand" "CAst.Expr" },  -- -x
    A.variant "CEBitNot"    { A.field "operand" "CAst.Expr" },  -- ~x
    A.variant "CENot"       { A.field "operand" "CAst.Expr" },  -- !x
    A.variant "CESizeofExpr" { A.field "expr" "CAst.Expr" },     -- sizeof expr
    A.variant "CESizeofType" { A.field "type_name" "CAst.TypeName" }, -- sizeof(type)
    A.variant "CECast"      { A.field "type_name" "CAst.TypeName", A.field "expr" "CAst.Expr" },

    -- Binary
    A.variant "CEBinary" {
        A.field "op" "CAst.BinaryOp",
        A.field "left" "CAst.Expr",
        A.field "right" "CAst.Expr",
    },

    -- Ternary
    A.variant "CETernary" {
        A.field "cond" "CAst.Expr",
        A.field "then_expr" "CAst.Expr",
        A.field "else_expr" "CAst.Expr",
    },

    -- Assignment
    A.variant "CEAssign" {
        A.field "op" "CAst.AssignOp",
        A.field "left" "CAst.Expr",
        A.field "right" "CAst.Expr",
    },

    -- Member access
    A.variant "CEDot"       { A.field "base" "CAst.Expr", A.field "field" "string" },
    A.variant "CEArrow"     { A.field "base" "CAst.Expr", A.field "field" "string" },

    -- Subscript & call
    A.variant "CESubscript" { A.field "base" "CAst.Expr", A.field "index" "CAst.Expr" },
    A.variant "CECall"      { A.field "callee" "CAst.Expr", A.field "args" (A.many "CAst.Expr") },

    -- Compound literal
    A.variant "CECompoundLit" {
        A.field "type_name" "CAst.TypeName",
        A.field "initializer" "CAst.Initializer",
    },

    -- GNU statement expression
    A.variant "CEStmtExpr"  {
        A.field "items" (A.many "CAst.BlockItem"),
        A.field "result" "CAst.Expr",  -- the final expression whose value is returned
    },

    -- Comma operator
    A.variant "CEComma"     { A.field "left" "CAst.Expr", A.field "right" "CAst.Expr" },
}
```

```lua
A.sum "CAst.BinaryOp" {
    A.variant "CBinAdd",
    A.variant "CBinSub",
    A.variant "CBinMul",
    A.variant "CBinDiv",
    A.variant "CBinMod",
    A.variant "CBinShl",       -- <<
    A.variant "CBinShr",       -- >>
    A.variant "CBinLt",
    A.variant "CBinLe",
    A.variant "CBinGt",
    A.variant "CBinGe",
    A.variant "CBinEq",
    A.variant "CBinNe",
    A.variant "CBinBitAnd",
    A.variant "CBinBitXor",
    A.variant "CBinBitOr",
    A.variant "CBinLogAnd",
    A.variant "CBinLogOr",
}

A.sum "CAst.AssignOp" {
    A.variant "CAssign",        -- =
    A.variant "CAddAssign",     -- +=
    A.variant "CSubAssign",     -- -=
    A.variant "CMulAssign",     -- *=
    A.variant "CDivAssign",     -- /=
    A.variant "CModAssign",     -- %=
    A.variant "CShlAssign",     -- <<=
    A.variant "CShrAssign",     -- >>=
    A.variant "CAndAssign",     -- &=
    A.variant "CXorAssign",     -- ^=
    A.variant "COrAssign",      -- |=
}
```

### 6.5 Statements

```lua
A.sum "CAst.Stmt" {
    A.variant "CSLabeled"   { A.field "label" "string", A.field "stmt" "CAst.Stmt" },
    A.variant "CSCase"      { A.field "value" "CAst.Expr", A.field "stmt" "CAst.Stmt" },
    A.variant "CSDefault"   { A.field "stmt" "CAst.Stmt" },
    A.variant "CSExpr"      { A.field "expr" (A.optional "CAst.Expr") },  -- expr; or ;
    A.variant "CSCompound"  {
        A.field "items" (A.many "CAst.BlockItem"),  -- interleaved decls and stmts (C99)
    },
    A.variant "CSIf"        {
        A.field "cond" "CAst.Expr",
        A.field "then_stmt" "CAst.Stmt",
        A.field "else_stmt" (A.optional "CAst.Stmt"),
    },
    A.variant "CSSwitch"    {
        A.field "cond" "CAst.Expr",
        A.field "body" "CAst.Stmt",   -- the compound statement
    },
    A.variant "CSWhile"     { A.field "cond" "CAst.Expr", A.field "body" "CAst.Stmt" },
    A.variant "CSDoWhile"   { A.field "body" "CAst.Stmt", A.field "cond" "CAst.Expr" },
    A.variant "CSFor"       {
        A.field "init" (A.optional "CAst.ForInit"),
        A.field "cond" (A.optional "CAst.Expr"),
        A.field "incr" (A.optional "CAst.Expr"),
        A.field "body" "CAst.Stmt",
    },
    A.variant "CSGoto"      { A.field "label" "string" },
    A.variant "CSContinue"  {},
    A.variant "CSBreak"     {},
    A.variant "CSReturn"    { A.field "expr" (A.optional "CAst.Expr") },
}

A.sum "CAst.ForInit" {
    A.variant "CFInitExpr"  { A.field "expr" "CAst.Expr" },
    A.variant "CFInitDecl"  { A.field "decl" "CAst.Decl" },
}

A.sum "CAst.BlockItem" {
    A.variant "CBlockDecl"  { A.field "decl" "CAst.Decl" },
    A.variant "CBlockStmt"  { A.field "stmt" "CAst.Stmt" },
}
```

### 6.6 Initializers

```lua
A.sum "CAst.Initializer" {
    A.variant "CInitExpr"   { A.field "expr" "CAst.Expr" },
    A.variant "CInitList"   {
        A.field "items" (A.many "CAst.InitItem"),
    },
}

A.product "CAst.InitItem" {
    A.field "designator" (A.optional (A.many "CAst.Designator")),
    A.field "value" "CAst.Initializer",
}

A.sum "CAst.Designator" {
    A.variant "CDesigField"     { A.field "name" "string" },     -- .fieldname
    A.variant "CDesigIndex"     { A.field "index" "CAst.Expr" },  -- [index]
    A.variant "CDesigRange"     { A.field "lo" "CAst.Expr", A.field "hi" "CAst.Expr" },  -- [lo...hi] (GNU)
}
```

### 6.7 Parser architecture

The parser is a hand-written recursive-descent parser. It does not use parser
generators. The structure follows standard C parsing techniques:

- **`c_decl.lua`:** type specifiers, declarators, declarations
- **`c_expr.lua`:** expressions, operator precedence (see Appendix)
- **`c_stmt.lua`:** statements, including labeled statements and switch

The three modules call each other: declarations appear in compound statements,
expressions appear in statements, type names appear in expressions (casts,
`sizeof`, compound literals).

---

## 7. C Type System

### 7.1 Type specifier combination

C type specifiers combine according to rules that the parser records as a list
of specifier tokens. The `cimport` phase resolves the combination:

| Specifiers | Result type |
|-----------|------------|
| `int` | signed int (i32) |
| `unsigned int` | unsigned int (u32) |
| `long` | signed long; width from `ffi.sizeof("long")`: i32 on LLP64 (Windows), i64 on LP64 (Linux/macOS) |
| `long int` | same as `long` |
| `long long` | signed long long (i64) |
| `unsigned long long` | u64 |
| `float` | f32 |
| `double` | f64 |
| `long double` | (deferred; not supported) |
| `char` | platform-dependent (i8 or u8) |
| `signed char` | i8 |
| `unsigned char` | u8 |
| `short` | i16 |
| `unsigned short` | u16 |
| `void` | void (return only) |
| `_Bool` | bool |
| `struct name` | C struct type |
| `union name` | C union type |
| `enum name` | integer type (i32 or platform width) |
| typedef name | resolved type |

The mapping follows LuaJIT FFI type rules. Sizes are queried through `ffi.sizeof`
and signedness through `ffi.typeof` at cimport time.

### 7.2 Type compatibility

The `cimport` phase determines type compatibility using `ffi.typeof`. Two type
specifications are compatible if `ffi.typeof` reports them as the same type.
This is used for:

- Function redeclaration checking
- Assignment compatibility
- Conditional expression type balancing
- Return type checking

### 7.3 Usual arithmetic conversions

C's usual arithmetic conversions (applied to binary operators) are implemented
in the lowering phase as explicit `as()` insertions:

1. If either operand is `long double` → convert both to `long double` (deferred)
2. If either operand is `double` → convert both to `double`
3. If either operand is `float` → convert both to `float`
4. Integer promotions on both operands
5. If both operands have the same signedness → convert to the wider type
6. If unsigned is wider or same width → convert to unsigned
7. Otherwise → convert to signed

Every implicit conversion becomes an `as(target_type, value)` MoonTree
expression. No implicit conversion ever survives lowering.

### 7.4 Default argument promotions

Calls to functions without prototypes (K&R style — not supported) would apply
default argument promotions: `float` → `double`, integer types narrower than
`int` → `int`. Since K&R definitions are out of scope, these are not
implemented. Calls to prototyped functions use `as()` based on parameter types.

### 7.5 C type and layout facts (cimport phase output)

The `cimport` phase produces these facts from the expanded CAst. They are
consumed by `lower_c` and by the typechecker.

```lua
A.product "CTypeId" {
    A.field "module_name" "string",
    A.field "spelling" "string",
    A.unique,
}

A.sum "CTypeKind" {
    A.variant "CVoid",
    A.variant "CScalar"     { A.field "scalar" "MoonBack.BackScalar" },
    A.variant "CPointer"    { A.field "pointee" "MoonC.CTypeId" },
    A.variant "CEnum"       { A.field "scalar" "MoonBack.BackScalar" },
    A.variant "CArray"      { A.field "elem" "MoonC.CTypeId", A.field "count" "number" },
    A.variant "CStruct",
    A.variant "CUnion",
    A.variant "COpaque",
    A.variant "CFuncPtr"    { A.field "sig" "MoonC.CFuncSigId" },
}

A.product "CTypeFact" {
    A.field "id" "MoonC.CTypeId",
    A.field "kind" "MoonC.CTypeKind",
    A.field "complete" "boolean",
    A.field "size" (A.optional "number"),
    A.field "align" (A.optional "number"),
    A.unique,
}

A.product "CFieldLayout" {
    A.field "owner" "MoonC.CTypeId",
    A.field "name" "string",
    A.field "type" "MoonC.CTypeId",
    A.field "offset" "number",
    A.field "size" "number",
    A.field "align" "number",
    A.field "bit_offset" (A.optional "number"),
    A.field "bit_width" (A.optional "number"),
    A.unique,
}

A.product "CLayoutFact" {
    A.field "type" "MoonC.CTypeId",
    A.field "size" "number",
    A.field "align" "number",
    A.field "fields" (A.many "MoonC.CFieldLayout"),
    A.unique,
}

A.product "CFuncSigId"     { A.field "text" "string", A.unique }

A.product "CFuncSig" {
    A.field "id" "MoonC.CFuncSigId",
    A.field "params" (A.many "MoonC.CTypeId"),
    A.field "result" "MoonC.CTypeId",
    A.unique,
}

A.product "CExternFunc" {
    A.field "moon_name" "string",
    A.field "symbol" "string",
    A.field "sig" "MoonC.CFuncSigId",
    A.field "library" (A.optional "string"),
    A.unique,
}

A.product "CLibrary" {
    A.field "name" "string",
    A.field "link_name" (A.optional "string"),
    A.field "path" (A.optional "string"),
    A.field "symbols" (A.many "string"),
    A.unique,
}
```

Moonlift type schema adds:

```lua
A.variant "TCType" {
    A.field "id" "MoonC.CTypeId",
    A.variant_unique,
}

A.variant "TCFuncPtr" {
    A.field "sig" "MoonC.CFuncSigId",
    A.variant_unique,
}
```

## 8. C AST → MoonTree Lowering

### 8.1 Lowering context

The `lower_c` PVM phase walks the expanded `CAst.TranslationUnit` and emits
MoonTree facts. It maintains a lowering context:

```lua
local LowerCtx = {
    module,             -- target Moonlift module
    ctype_registry,     -- CTypeFact table from cimport (CTypeId → CTypeFact)
    layout_facts,       -- CLayoutFact table from cimport
    abi_plans,          -- CAbiPlan table (CFuncSigId → CAbiPlan)
    extern_funcs,       -- CExternFunc table (moon_name → {symbol, sig, library})
    function_table,     -- CAst function name → MoonTree FuncId
    label_table,        -- current function's C labels → MoonTree BlockId
    break_target,       -- current break target BlockId
    continue_target,    -- current continue target BlockId
    switch_cases,       -- current switch case values → BlockId
    switch_default,     -- current switch default BlockId
    enclosing_func,     -- current MoonTree FuncId
}
```

### 8.2 Function lowering

A C function definition:

```c
int sum(const int* xs, int n) {
    int acc = 0;
    for (int i = 0; i < n; i++) {
        acc += xs[i];
    }
    return acc;
}
```

Lowers to MoonTree:

```moonlift
export func sum(xs: ptr(i32), n: i32) -> i32
    var acc: i32 = 0
    block for_loop(i: i32 = 0)
        if i >= n then yield acc end
        let _t1: i32 = *(xs + as(index, i))
        acc = acc + _t1
        jump for_loop(i = i + 1)
    end
end
```

Note: `i` is a block parameter (SSA-like); it cannot be mutated with
assignment. The increment is passed directly as a jump argument.

Lowering rules:

| C construct | MoonTree lowering |
|------------|------------------|
| `return expr;` | `return expr` |
| `return;` | `return` (void return) |
| `{ decls; stmts; }` | Sequential emits. Declarations become `let`/`var`. |
| `if (cond) a; else b;` | `block then: if cond→block/else, else→block/then, end` |
| `for (init; cond; incr) body` | init; `block loop(vars): if !cond→yield; body; jump loop(incr-applied-vars)` |
| `while (cond) body` | `block loop(): if !cond→yield; body; jump loop` |
| `do body while (cond);` | `block loop(): body; if !cond→yield; jump loop` |
| `switch (expr) { cases }` | `block dispatch: switch expr { cases→blocks }` |
| `goto label;` | `jump label_block(args)` |
| `break;` | `jump break_target()` |
| `continue;` | `jump continue_target()` |

### 8.3 Variable address-of analysis

The lowerer must detect which C locals have their address taken (`&x` anywhere
in the function scope). Those variables are emitted as Moonlift `var` (stack
allocation). Variables whose address is never taken may be emitted as `let`
(SSA-like, register-candidate).

This is a standard escape analysis: a single pass over the function AST collects
the set of locals referenced by `&` or by array-to-pointer decay (arrays always
have an address). The result determines the Moonlift binding kind.

### 8.4 Expression lowering

| C expression | MoonTree lowering |
|-------------|------------------|
| `x` (local) | `x` (Moonlift name reference) |
| `x` (global/static) | global variable access (address-of + load) |
| `42`, `3.14`, `'a'`, `"hello"` | literal, with `as()` if needed for type |
| `a + b` | `a + b` (with usual arithmetic conversion `as()` inserted) |
| `a - b`, `a * b`, `a / b`, `a % b` | corresponding Moonlift operator |
| `-a`, `+a`, `~a`, `!a` | corresponding Moonlift unary operator |
| `a << b`, `a >> b` | `a << b`, `a >>> b` (unsigned) or `a >> b` (signed) |
| `a & b`, `a \| b`, `a ^ b` | corresponding Moonlift bitwise operator |
| `a && b` | Short-circuit: `if a ~= 0 then (b ~= 0) else false end`. Must not evaluate `b` when `a` is zero. Cannot use `select` (evaluates both arms). |
| `a \|\| b` | Short-circuit: `if a ~= 0 then true else (b ~= 0) end`. Must not evaluate `b` when `a` is nonzero. Cannot use `select`. |
| `a == b`, `a != b`, `a < b`, `a <= b`, `a > b`, `a >= b` | corresponding Moonlift comparison |
| `a ? b : c` | Short-circuit: `if a ~= 0 then b else c end`. Cannot use `select` (Cranelift cmove evaluates both arms; `?:` must not). |
| `a = b` | `a = b` (store to var or through pointer) |
| `a += b` | `a = a + b` |
| `*p` | `*p` (Moonlift dereference) |
| `&x` | `&x` (Moonlift address-of) |
| `p->field` | `(*p).field` or `p.field` (Moonlift handles pointer field access) |
| `a.field` | `a.field` (struct field access via offset) |
| `a[i]` | `*(a + as(index, i))` or view indexing |
| `f(a, b)` | `f(a, b)` (call to Moonlift function or extern) |
| `(type)expr` | `as(target_type, expr)` |
| `sizeof(expr)` | `csizeof("type_name")` (compile-time constant) |
| `++x` | `x = x + 1; result = x` (requires `x` to be `var`; see §8.3 address-of analysis) |
| `x++` | `let tmp = x; x = x + 1; tmp` (requires `x` to be `var`) |
| `a, b` | `b` (evaluate `a` for side effects, result is `b`) |
| `"str1" "str2"` | Concatenated string literal |
| `(type){init}` | Stack slot + field stores, or struct literal |
| `({ stmts; expr })` | `block gnu_expr(): stmts; yield expr end` (GNU statement expression; `items` may include interleaved decls) |

### 8.5 Assignment lowering

C assignment is an expression that returns the assigned value. Moonlift
assignment is a statement. The lowerer decomposes C assignment expressions:

```c
if ((x = f()) > 0) { ... }
```
→
```moonlift
x = f()
if x > 0 then ... end
```

Assignment operators (`+=`, `<<=`, etc.) are decomposed into their read-modify-write
form:

```c
x += 5;
```
→
```moonlift
x = x + 5
```

### 8.6 `switch` lowering

C `switch` with fallthrough requires explicit block-to-block jumps. The
lowerer:

1. Creates a dispatch block with a Moonlift `switch` over the condition.
2. Each `case` arm becomes a labeled block.
3. Absence of `break` at end of a case arm → emit `jump next_case()` to
   chain fallthrough.
4. `break` → `jump after_switch()`.
5. `default` → default arm of the Moonlift `switch`.

```c
switch (x) {
case 1: a(); break;
case 2: b();   // fallthrough
case 3: c(); break;
default: d();
}
```
→ MoonTree (conceptual — actual output is MoonTree ASDL facts):

```moonlift
block case_1()
    a()
    jump after_switch()
end
block case_2()
    b()
    jump case_3()           -- C fallthrough
end
block case_3()
    c()
    jump after_switch()
end
block case_default()
    d()
    jump after_switch()
end
switch x do
    case 1 then jump case_1() end
    case 2 then jump case_2() end
    case 3 then jump case_3() end
    default then jump case_default() end
end
block after_switch()
    -- continue after switch
end
```

The key point: C fallthrough becomes an explicit `jump`. Moonlift source
`switch` has no fallthrough; each case arm is a `jump` to the appropriate
block. This MoonTree is then typechecked and lowered to BackCmd by the
existing pipeline.

The key point: C fallthrough between `case 2` and `case 3` becomes an
explicit `jump` from block_case_2 to block_case_3. Moonlift's source-level
`switch` has no fallthrough; the lowering produces block/jump IR directly.

### 8.7 `goto` lowering

C `goto label;` maps to Moonlift `jump label_block(args)`. The lowerer:

1. Creates a labeled block for each C label.
2. Determines the live variables at each `goto` site and passes them as block
   arguments.
3. Each label block receives those variables as parameters.

```c
if (x > 0) goto done;
x = 0;
done:
return x;
```
→
```moonlift
block done(x_val: i32)
    return x_val
end
if x > 0 then jump done(x_val = x) end
x = 0
jump done(x_val = x)
```

If the label has no `goto` that reaches it with different sets of live
variables, the block can be parameter-less.

### 8.8 Static and global variables

C `static` variables at file scope lower to Moonlift `static` declarations.
C global variables (`extern` at file scope, or defined without `static`) lower
to Moonlift `static` with `export` linkage.

```c
static int counter = 0;
int global_flag = 1;
```
→
```moonlift
static counter: i32 = 0
export static global_flag: i32 = 1
```

Initializers for statics must be constant expressions; the lowerer evaluates
them at compile time. String literals used as initializers generate data
objects in the Moonlift module.

### 8.9 String literals

C string literals become MoonTree data items — named blobs of initialized
bytes with type `ptr(u8)`. The MoonTree schema needs a `DataItem` type
(analogous to `ConstItem` and `StaticItem`):

```lua
A.product "DataItem" {
    A.field "id" "MoonCore.DataId",
    A.field "size" "number",           -- byte length including null terminator
    A.field "align" "number",          -- alignment (1 for char strings)
    A.field "bytes" "string",          -- raw byte content
    A.unique,
}

-- In the Item sum:
A.variant "ItemData" {
    A.field "data" "MoonTree.DataItem",
    A.variant_unique,
}
```

For `"Hello"`, the `lower_c` phase emits:
```
ItemData { id = d0, size = 6, align = 1, bytes = "Hello\0" }
```

An `ExprLit` with a pointer to the data object is then used wherever the
string literal appears in an expression:
```
ExprLit { h = typed(ptr(u8)), value = LitDataAddr(d0) }
```

The existing `lower` phase maps `ItemData` facts to `CmdDeclareData` /
`CmdDataInitInt` commands. `LitDataAddr` maps to `CmdDataAddr`.

Multiple uses of the same string literal share one data object (deduplicated
by byte content).

### 8.10 Loop lowering — fact-based state promotion

C loops (`while`, `do`/`while`, `for`) carry state through mutable local
variables. Moonlift control regions carry state through **block parameters
and jump arguments.** The C lowerer must gather loop facts, promote
loop-carried variables to block parameters, and rewrite assignments to
jump argument updates.

#### 8.10.1 ASDL facts for loop analysis

```lua
-- A variable that is mutated inside a loop body.
A.product "CLoopCarriedVar" {
    A.field "name" "string",
    A.field "ty" "MoonType.Type",
    A.field "init" "MoonTree.Expr",      -- initial value before the loop
    A.field "live_out" "boolean",         -- true if the variable is read after the loop
    A.unique,
}

-- A variable read but never written inside the loop body.
A.product "CLoopInvariantVar" {
    A.field "name" "string",
    A.unique,
}

-- The complete analysis for one loop.
A.product "CLoopAnalysis" {
    A.field "carried_vars" (A.many "MoonC.CLoopCarriedVar"),
    A.field "invariant_vars" (A.many "MoonC.CLoopInvariantVar"),
    A.field "has_break" "boolean",
    A.field "has_continue" "boolean",
    A.unique,
}
```

#### 8.10.2 Gathering loop facts

Before lowering a loop body, the lowerer scans all statements and expressions
within it to classify variables. The scan is a single recursive walk:

| Usage pattern | Classification |
|---------------|---------------|
| Variable appears on LHS of `=`, `+=`, `++`, `--`, or as operand of `&` | Loop-carried (written in loop) |
| Variable appears only in RHS position (read, never written) | Loop-invariant |
| Variable declared inside the loop body | Loop-local (not lifted) |
| Loop-carried variable referenced after the loop in the enclosing function | `live_out = true` |

Example — for the C loop:
```c
int acc = 0;
int i = 0;
while (i < n) {
    acc = acc + xs[i];
    i = i + 1;
}
return acc;
```

The analysis produces:
```lua
{
    carried_vars = {
        { name = "i",   ty = I32, init = lit_int("0"), live_out = false },
        { name = "acc", ty = I32, init = lit_int("0"), live_out = true  },
    },
    invariant_vars = {
        { name = "n" },
        { name = "xs" },
    },
}
```

#### 8.10.3 Lowering with block-parameter state

Given a `CLoopAnalysis`, the lowerer produces a single-block control
expression. The entry block carries the loop-carried variables as parameters
with initializers. Assignments to those variables inside the body are
rewritten to expressions whose values become jump arguments.

**Structure:**
```
{carried_var_decls}
let {yield_vars...} = block {label}(p1: T1 = init1, p2: T2 = init2, ...) -> (T_yield...)
    if not {cond} then yield {live_out_vars...} end
    ... body with {carried_var} reads coming from block params ...
    ... assignments to {carried_var} replaced by computed values ...
    jump {label}(p1 = new1, p2 = new2, ...)
end
```

**Concrete MoonTree for the while-loop example:**
```lua
-- Before the control region: only invariant vars declared, if any
-- (In this example, n and xs are parameters, not locals, so nothing here)

-- Control expression
local entry_params = {
    Tr.EntryBlockParam("i",   Ty.TScalar(C.ScalarI32), lit_int("0")),
    Tr.EntryBlockParam("acc", Ty.TScalar(C.ScalarI32), lit_int("0")),
}

local cond = Tr.ExprCompare(Tr.ExprSurface, C.CmpGe,  -- i >= n → exit
    Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("i")),
    Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("n")))

-- Body: acc + xs[i], i + 1
local acc_update = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd,
    Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("acc")),
    Tr.ExprIndex(Tr.ExprSurface,
        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("xs")),
        Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("i"))))

local i_update = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd,
    Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("i")),
    lit_int("1"))

-- Build the entry block body: if i >= n → yield acc; else continue
local entry_body = {
    Tr.StmtIf(Tr.StmtSurface, cond,
        { Tr.StmtYieldValue(Tr.StmtSurface,
            Tr.ExprRef(Tr.ExprSurface, Bind.ValueRefName("acc"))) },
        {}  -- fall through to the jump
    )
}

-- Append the jump
entry_body[#entry_body + 1] = Tr.StmtJump(Tr.StmtSurface, loop_label, {
    Tr.JumpArg("i", i_update),
    Tr.JumpArg("acc", acc_update),
})

local entry = Tr.EntryControlBlock(loop_label, entry_params, entry_body)

-- Region with a single block
local region = Tr.ControlExprRegion(region_id,
    Ty.TScalar(C.ScalarI32),  -- yield type (acc)
    entry, {})

-- The whole thing is an expression that yields acc
local control_expr = Tr.ExprControl(Tr.ExprSurface, region)
```

The result: `control_expr` evaluates to the final value of `acc` after the
loop exits. It can be used as the return value or assigned to a local.

#### 8.10.4 Multi-block loops

For more complex loops (those with `break`/`continue` in C), the analysis
is the same, but the lowering uses additional blocks:

- `continue` → `jump` to the loop header block with current state
- `break` → `jump` to the exit block carrying live-out values
- The exit block `yield`s the live-out variables

#### 8.10.5 Explicit decision point

This is a **fact-gathering decision**, not a syntax-to-syntax translation.
The lowerer must:

1. Scan the loop body to classify variables (carried vs invariant vs local).
2. Determine which carried variables are live-out (used after the loop).
3. Build block parameters for all carried variables.
4. Rewrite assignments to computed values passed as jump arguments.
5. Use `ControlExprRegion` (not `ControlStmtRegion`) when live-out values
exist, so the yielded values flow to subsequent code.

No mutable `StmtVar` cells remain inside the lowered loop. All state is
carried through block parameters and jump arguments.

## 9. Integration with the Moonlift Module System

### 9.1 `import c` with bodies

A single `.mlua` declaration covers all C interop:

```moonlift
import c [[
    #include header material (or just declarations inline)

    static inline int clamp(int x, int lo, int hi) {
        return x < lo ? lo : x > hi ? hi : x;
    }
]]
```

The hosted pipeline detects that the cdef string contains function bodies or
preprocessor directives and routes through the full C frontend. Pure-declaration
cdef strings use the existing fast path.

The lowered MoonTree functions are added to the module and are callable from
Moonlift code in the same module as if they were written in Moonlift:

```moonlift
import c [[ static inline int add(int a, int b) { return a + b; } ]]

export func use_c() -> i32
    return add(10, 20)    -- add was lowered from C to MoonTree
end
```

### 9.2 Compilation strategy

Functions lowered from C are compiled by the existing Moonlift pipeline:
typecheck → lower → validate → emit. They participate in optimization,
inlining, and vectorization exactly like hand-written Moonlift functions.

The only difference is that C functions carry C ABI calling convention facts
when they are exported for C interop. Internal functions (those with `static`
or `inline` linkage, or those not referenced by exported C symbols) use
Moonlift's internal calling convention and can be optimized freely.

### 9.3 Linkage

| C linkage | Moonlift lowering |
|-----------|------------------|
| `static` function | Module-local function (not exported) |
| `extern` / default function | `export func` with C ABI |
| `inline` function | Module-local function; may be inlined at call sites |
| `static inline` | Module-local function; inlined aggressively |
| `extern inline` (C99) | Extern function with inline hint |
| `static` variable | Moonlift `static` |
| `extern` / default variable | Moonlift `export static` |

### 9.4 Cross-module C compilation

C source files imported into different Moonlift modules are compiled
independently (like separate compilation units). A C global in one module can
be referenced from another via `extern` declaration:

```moonlift
-- module_a.mlua
import c [[ int shared_counter; ]]

-- module_b.mlua
import c [[ extern int shared_counter; ]]
```

The symbol `shared_counter` is resolved at link time (JIT or object emission).

---

## 10. Diagnostics

### 10.1 Preprocessor diagnostics

| Diagnostic | Phase | Meaning |
|-----------|-------|---------|
| `c_include_not_found` | cpp_expand | `#include` file not found |
| `c_if_expression_not_constant` | cpp_expand | `#if` expression is not a constant integer |
| `c_error_directive` | cpp_expand | `#error "message"` encountered |
| `c_macro_redefined` | cpp_expand | `#define` redefines existing macro differently |
| `c_macro_params_mismatch` | cpp_expand | Function-like macro called with wrong number of arguments |
| `c_paste_invalid_token` | cpp_expand | `##` produced an invalid token |
| `c_unterminated_directive` | cpp_expand | Backslash-newline at end of file in directive |

### 10.2 Parser diagnostics

| Diagnostic | Phase | Meaning |
|-----------|-------|---------|
| `c_unexpected_token` | parse | Token not expected at this position |
| `c_expected_token` | parse | Expected a specific token but found something else |
| `c_expected_expression` | parse | Expected an expression |
| `c_expected_statement` | parse | Expected a statement |
| `c_expected_declaration` | parse | Expected a declaration |
| `c_duplicate_field` | parse | Duplicate field name in struct/union |
| `c_duplicate_enumerator` | parse | Duplicate enumerator name |
| `c_duplicate_label` | parse | Duplicate `case` value or label name |
| `c_too_many_initializers` | parse | More initializers than aggregate elements |
| `c_unknown_type` | parse | Type name not found in typedef registry |

### 10.3 Lowering diagnostics

| Diagnostic | Phase | Meaning |
|-----------|-------|---------|
| `c_undefined_function` | lower_c | Call to undeclared function |
| `c_undefined_variable` | lower_c | Reference to undeclared variable |
| `c_incompatible_types` | lower_c | Type mismatch in assignment, return, or binary operation |
| `c_invalid_lvalue` | lower_c | Expression is not an lvalue where one is required |
| `c_break_not_in_loop_or_switch` | lower_c | `break` outside of loop or switch |
| `c_continue_not_in_loop` | lower_c | `continue` outside of loop |
| `c_goto_undefined_label` | lower_c | `goto` references unknown label |
| `c_return_type_mismatch` | lower_c | Return expression type doesn't match function return type |
| `c_non_void_return_in_void_func` | lower_c | `return expr;` in void function |
| `c_missing_return` | lower_c | Non-void function may reach end without return |

### 10.4 Span preservation

All diagnostics carry source spans that reference the original C source, not
preprocessed output. The `cpp_expand` phase preserves location information on
every token it emits by carrying the originating `#define` location or
`#include` chain. This means:

- Errors in macro expansions point at both the macro *use* site (where the
  expansion occurred) and the macro *definition* site (where the `#define` is).
- Errors in included files point at the included file and the `#include` line.
- The LSP can navigate from expanded tokens back to their definition.

---

## 11. Implementation Phases

### Phase 1 — Tokenizer

- Implement `c_lexer.lua`: C99 tokenizer with directives, comments, line
  continuations
- Output: `CToken` stream
- Tests: tokenize C99 test files, verify token types and positions

### Phase 2 — Preprocessor

- Implement `cpp_expand` PVM phase
- Object-like and function-like `#define` / `#undef`
- `#include` with VFS provider
- `#if` / `#ifdef` / `#ifndef` / `#elif` / `#else` / `#endif`
- Constant expression evaluator for `#if`
- `##` token pasting, `#` stringification
- Built-in macros
- `#pragma`, `#error`
- Tests: standard preprocessor test cases, edge cases (self-referential macros,
  recursive expansion blocking, variadic macros, token paste edge cases)

### Phase 3 — Declaration Parser

- Implement `c_decl.lua`: type specifiers, declarators, declarations
- Struct, union, enum parsing with `FieldDecl`/`FieldDeclarator` for bitfields
- Typedef handling
- Function prototype parsing
- Tests: parse various C headers, verify declaration structure

### Phase 4 — Expression & Statement Parser

- Implement `c_expr.lua`: full C expression grammar with correct precedence
- Implement `c_stmt.lua`: all C statements with `BlockItem` for C99 mixed
  declarations
- Integration with declaration parser
- Tests: parse C source files, verify AST structure

### Phase 5 — C Type Integration

- Implement `cimport` PVM phase for frontend-produced AST
- Integrate with existing `ffi.cdef` type registration
- Type specifier combination resolution
- Layout querying via `ffi.sizeof` / `ffi.offsetof` / `ffi.alignof`
- Tests: verify type facts against LuaJIT FFI queries

### Phase 6 — Lowering to MoonTree

- Implement `lower_c` PVM phase
- Function lowering
- Expression lowering (with usual arithmetic conversions)
- Statement lowering (if, for, while, do, switch, goto)
- Short-circuit `&&`/`||` lowering as block/jump control flow
- Address-of analysis for local variables (determines `let` vs `var`)
- String literal data object generation
- Static/global variable lowering
- Tests: compile simple C functions, verify MoonTree output, execute at runtime

### Phase 7 — Integration & LSP

- Hosted pipeline integration (`import c` with bodies and file paths)
- Cross-module compilation
- LSP support: go-to-definition, hover, diagnostics
- End-to-end tests: compile real C libraries, call from Moonlift

---

## 12. Test Strategy

### 12.1 Tokens

- All C99 keywords, punctuators, literal forms
- Preprocessor directive recognition
- Line continuation handling
- Comment handling (single-line, multi-line, edge cases)
- Error recovery: unclosed comments, unrecognized characters

### 12.2 Preprocessor

- Object-like macro expansion (simple, recursive, self-referential)
- Function-like macro expansion (argument substitution, stringification, pasting)
- Variadic macros
- Conditional inclusion (true/false branches, `defined()` operator)
- Include file resolution and cycle detection
- Built-in macros (`__FILE__`, `__LINE__`, `__COUNTER__`)
- Error cases: missing includes, malformed directives, redefinitions

### 12.3 Parser

- C99 declaration torture tests (complex declarators)
- Full C expression grammar (all operators, all precedences)
- Operator associativity (left-to-right for most, right-to-left for assignment)
- Struct/union/enum definitions
- Initializers (scalar, aggregate, nested, designated)
- Compound literals
- Statement expressions
- Switch/case/default with fallthrough
- Error recovery: missing semicolons, unmatched braces, invalid syntax

### 12.4 Lowering

- Simple functions: arithmetic, control flow, returns
- Loops: for, while, do/while
- Switch with fallthrough
- Goto with variable passing
- String literals → data objects
- Static/global variables
- Address-of analysis: verify `&x` triggers var emission
- Usual arithmetic conversions: verify `as()` insertions
- Function calls (direct, indirect via function pointers)

### 12.5 End-to-end

- Compile C functions, call from Moonlift, verify numeric results
- Compile C library (e.g., a small math library), use from Moonlift
- Compare Moonlift-compiled C output with gcc/clang-compiled output
- Verify inline functions are inlined through MoonTree optimization
- Verify LSP features span across C and Moonlift code

### 12.6 Conformance suite

A set of C source files that exercise the full C99 surface (minus the explicit
exclusions). Output verified against a reference C compiler.

---

## 13. Complete Examples

### 13.1 Simple function

```moonlift
import c [[
    int factorial(int n) {
        if (n <= 1) return 1;
        return n * factorial(n - 1);
    }
]]

export func test_factorial() -> i32
    return factorial(5)    -- lowered from C, compiled, called directly
end
```

### 13.2 Inline function from C called in Moonlift loop

```moonlift
import c [[
    static inline int clamp(int x, int lo, int hi) {
        return x < lo ? lo : x > hi ? hi : x;
    }
]]

export func normalize(pixel: ptr(u8), n: index)
    block loop(i: index = 0)
        if i >= n then return end
        let val: i32 = as(i32, pixel[i])
        pixel[i] = as(u8, clamp(val, 0, 255))   -- inline, zero overhead
        jump loop(i = i + 1)
    end
end
```

### 13.3 C library imported as source

```moonlift
import c "vendor/vec_math.h"    -- struct vec3, function prototypes
import c "vendor/vec_math.c"    -- function implementations

export func compute(v: c("vec3_t")) -> f64
    let a: c("vec3_t") = vec3_add(v, vec3_one())
    return vec3_length(a)
end
```

### 13.4 Macro-driven code generation

```moonlift
import c [[
    #define DEFINE_GETTER(T, name, member) \\
        static inline T get_##name(void* p) { \\
            return ((struct entity*)p)->member; \\
        }

    struct entity { int x; int y; int z; };

    DEFINE_GETTER(int, x, x)
    DEFINE_GETTER(int, y, y)
    DEFINE_GETTER(int, z, z)
]]

export func sum_coords(e: ptr(u8)) -> i32
    return get_x(e) + get_y(e) + get_z(e)
end
```

### 13.5 Switch with fallthrough

```c
// In import c block:
int classify(int x) {
    int result = 0;
    switch (x) {
    case 1:
    case 2:  result = 10; break;
    case 3:  result += 5;  // fallthrough intentional
    case 4:  result += 1; break;
    default: result = -1;
    }
    return result;
}
```

Lowers to MoonTree with explicit fallthrough jumps between case blocks.

---

## 14. Design Decisions

### 14.1 Rationale for a separate C AST (not direct to MoonTree)

The C AST (`CAst`) is a representation of C syntax, not C semantics. It captures
what the programmer wrote including preprocessor structure. MoonTree captures
lowered, typechecked, monomorphic semantics. The separation means:

- The preprocessor can be tested as a source-to-source transformation
- The parser can be tested against C source and produce inspectable AST
- Lowering can be tested as a transformation from CAst → MoonTree
- Each phase has a single responsibility

The AST is not a long-lived artifact. After `lower_c`, the CAst facts can be
discarded; only MoonTree facts persist in the module.

### 14.2 Why not Clang or libclang

- Clang is a 20M+ LOC C++ dependency. Moonlift's build is a single Rust binary.
- libclang provides a C API to Clang's AST, but that AST is specific to LLVM's
  representation. Translating it to MoonTree would be a separate complex
  lowering pass.
- The preprocessor-as-PVM-phase design means macros, includes, and conditionals
  are first-class fact-producing phases with perfect span preservation.
  `gcc -E` loses this.
- A ~10k-line Lua frontend is maintainable, debuggable, and fits Moonlift's
  "single build dependency" philosophy.

### 14.3 Why C99 (not C11 or C17)

C99 is the sweet spot:
- It covers the vast majority of existing C code
- It includes `//` comments, mixed declarations, `inline`, designated
  initializers, `_Bool`
- It avoids C11 features (`_Generic`, `_Atomic`, `_Thread_local`) that have
  no Cranelift backend support or are rarely used
- TCC targets C99, providing a useful conformance benchmark

C11 features can be added incrementally when needed.

### 14.4 Why no VLAs

Variable-length arrays require runtime stack manipulation. Cranelift supports
dynamic stack slots, but VLA semantics interact with `sizeof`, typedefs, and
struct layout in ways that complicate the type system. This is a deferred
feature.

### 14.5 Why `lower_c` produces MoonTree (not direct BackCmd)

Producing MoonTree lets the existing typechecker validate the lowered code.
Producing BackCmd directly would bypass typechecking and risk emitting
invalid backend commands. The MoonTree path also enables LSP facts — hover,
go-to-definition, references — on the lowered C code without special-casing.

### 14.6 Reserved words

The C keywords (`int`, `if`, `for`, `return`, `struct`, etc.) are reserved
only inside `import c` blocks. They do not affect Moonlift source outside
those blocks. Moonlift keywords (`func`, `export`, `jump`, `block`, etc.)
are not reserved in C source; the C parser owns its keyword set.

### 14.7 File size estimates

| Module | Estimated LOC (Lua) |
|--------|---------------------|
| `c_lexer.lua` | ~500 |
| `cpp_expand.lua` (phase) | ~1400 |
| `c_decl.lua` (declaration parser) | ~900 |
| `c_expr.lua` (expression parser) | ~700 |
| `c_stmt.lua` (statement parser) | ~600 |
| `c_type.lua` (type resolution) | ~400 |
| `cimport.lua` (extended for AST) | ~400 |
| `lower_c.lua` (C → MoonTree phase) | ~1500 |
| Integration (`host_quote.lua` changes) | ~300 |
| Tests | ~3000 |
| **Total** | **~9700** |

These estimates account for C's declarator grammar complexity, the
preprocessor's token pasting and variadic macro edge cases, and the
`lower_c` phase handling `goto`, `switch` fallthrough, address-of analysis,
usual arithmetic conversions, and compound literal materialization.

---

## 15. Appendix: Operator Precedence Table

C operator precedence from lowest to highest. The parser uses this table to
structure its recursive descent.

| Precedence | Operators | Associativity |
|-----------|-----------|:---:|
| 1 | `,` (comma) | L→R |
| 2 | `=` `+=` `-=` `*=` `/=` `%=` `<<=` `>>=` `&=` `^=` `\|=` | R→L |
| 3 | `?:` (ternary) | R→L |
| 4 | `\|\|` | L→R |
| 5 | `&&` | L→R |
| 6 | `\|` | L→R |
| 7 | `^` | L→R |
| 8 | `&` | L→R |
| 9 | `==` `!=` | L→R |
| 10 | `<` `<=` `>` `>=` | L→R |
| 11 | `<<` `>>` | L→R |
| 12 | `+` `-` (binary) | L→R |
| 13 | `*` `/` `%` | L→R |
| 14 | `!` `~` `+` `-` `++` `--` `*` `&` `sizeof` `(type)` (unary) | R→L |
| 15 | `[]` `.` `->` `()` (postfix) | L→R |

The parser groups levels into named functions: `comma_expr`, `assign_expr`,
`ternary_expr`, `log_or_expr`, `log_and_expr`, `bit_or_expr`, `bit_xor_expr`,
`bit_and_expr`, `equality_expr`, `relational_expr`, `shift_expr`,
`additive_expr`, `multiplicative_expr`, `cast_expr`, `unary_expr`,
`postfix_expr`, `primary_expr`.

---

*This document describes the target architecture for the Moonlift C frontend.
It is a design document, not an implementation status report. Implementation
should follow the phased order described in §11.*
