# Moonlift Scan/Parse Fusor Design

Status: design proposal.

This document defines a complete parser/lexer/scanner/protocol-decoder fusor for
Moonlift.  It is intentionally broad: the same core model should cover byte
scanners, lexers, parser combinators, JSON/CSV/log projection, binary/protocol
parsers, source-language parsers, diagnostics, recovery, and token/materialization
fusion.

The proposal follows Moonlift/PVM discipline:

```text
Lua staging / builder ergonomics
  -> explicit Moon2Scan ASDL values
  -> PVM fact/validation/decision boundaries
  -> Moon2Open.RegionFrag / Moon2Tree control regions
  -> existing Moonlift type/control/vector/backend phases
  -> flat native parser execution
```

Non-negotiable rule:

```text
If parser meaning affects execution, fusion, diagnostics, recovery, or output,
it must be represented as an ASDL value.
```

No parser semantics may hide in Lua closures, opaque tables, regex strings,
string tags, global registries, or runtime parser objects.

---

## 1. Executive summary

Moonlift should grow a `Moon2Scan` ASDL module and a hosted `moon.scan` builder
surface.  The central abstraction is a **typed input transducer**:

```text
input stream + cursor
  -> ok / miss / fail continuations
  -> typed captures, tokens, AST nodes, projection values, or fact streams
```

Lexers and parsers are not separate systems:

```text
scanner = parser over bytes/codepoints producing typed captures
lexer   = parser over bytes/codepoints producing token facts
parser  = parser over bytes/tokens producing output facts/nodes/projections
fusor   = PVM decision layer deciding which intermediate boundaries remain
```

A parser combinator is a Lua-staged constructor for ASDL parser nodes.  Runtime
execution is not combinator dispatch; it is generated Moonlift control flow.

Example user surface:

```lua
local P = moon.scan

local ident = P.capture_span("name",
  P.seq(
    P.choice(P.alpha(), P.byte("_")),
    P.repeat(P.choice(P.alnum(), P.byte("_")))
  )
)

local assignment = P.node("Assign", {
  name = P.seq(P.literal("let"), P.ws1(), ident),
  value = P.seq(P.ws0(), P.byte("="), P.ws0(), P.u32("value")),
})
```

This constructs ASDL values such as `PSeq`, `PChoice`, `PRepeat`, `PCapture`,
`PByte`, `PLiteral`, and `PNode`.  The fusor may lower the complete parser to one
Moonlift region with byte loads, switches, loops, typed captures, and diagnostic
codes.

---

## 2. Design goals

### 2.1 Performance goals

The system should support:

- parser combinator ergonomics with hand-written C-style execution shape
- zero-copy span/capture outputs
- schema-specialized data parsing
- lexer/parser fusion
- optional token materialization
- optional AST/fact materialization
- direct typed numeric parsing
- switch/trie/DFA lowering for deterministic choices
- specialized scanning loops for literals, classes, delimiters, and comments
- possible vector scan decisions for `take_until`, class runs, and delimiter
  search
- predictable failure and bounded backtracking where declared

### 2.2 Semantic goals

The system should represent explicitly:

- input stream kind
- cursor meaning
- parser algebra
- choice semantics
- repetition semantics
- commitment/cut semantics
- captures and output shapes
- token observability
- diagnostic expectations
- recovery strategy
- recursion strategy
- AST/fact/projection build policy
- fusion decisions

### 2.3 Tooling goals

The same grammar should support:

- fast batch parsing
- LSP/editor parsing
- syntax highlighting
- incremental analysis
- diagnostics and recovery
- source spans and stable node identities
- token/fact streams for downstream phases

### 2.4 Moonlift integration goals

The system should lower into existing Moonlift layers:

```text
Moon2Scan grammar/spec
  -> Moon2Open.RegionFrag / Moon2Tree control region
  -> tree typecheck/control facts
  -> vector facts/decisions where applicable
  -> Moon2Back flat commands
```

It should not require a separate parser VM in Rust or Lua.

---

## 3. Core architecture

### 3.1 Layer stack

```text
moon.scan hosted API
  Lua ergonomic constructors and templates

Moon2Scan ASDL
  parser algebra, token model, output model, diagnostics, recovery, fusion facts

scan_facts
  nullable, consumes, first/follow, output shape, recursion, observability facts

scan_validate
  grammar legality, shape legality, recursion legality, recovery legality

scan_decide
  switch/trie/DFA/vector/materialization/storage/recursion decisions

scan_to_region
  Moon2Scan + decisions -> Moon2Open.RegionFrag / Moon2Tree control regions

existing Moonlift phases
  open expansion, typecheck, control validation, vector decisions, backend
```

These are PVM semantic boundaries.  They are also good implementation module
boundaries, but their primary purpose is to keep meaning explicit and cacheable.

### 3.2 One transducer model

Every parser has the same conceptual execution signature:

```text
(input, cursor) -> ok | miss | fail
```

Runtime lowering uses continuations:

```moonlift
region parse_X(input: view(u8), pos: index;
               ok: cont(next: index, output...),
               miss: cont(pos: index, expected: i32),
               fail: cont(pos: index, error: i32))
```

Meaning:

- `ok`: accepted and produced the declared output shape
- `miss`: ordinary non-match; a choice may try another arm
- `fail`: committed failure; ordinary backtracking should not continue

A richer implementation may include `fatal`, but the semantic distinction between
recoverable miss and committed failure is fundamental.

---

## 4. Existing Moonlift concepts reused

### 4.1 Regions and continuations

`Moon2Open.RegionFrag` already models typed control fragments:

```text
RegionFrag(params, open, entry, blocks)
```

A parser rule lowers naturally to a region fragment.  Parser success/failure are
continuation slots.

### 4.2 Emit and continuation fills

Parser composition maps to region fragment emission:

```moonlift
emit parse_digit(input, pos; ok = got_digit, miss = no_digit, fail = bad)
```

The fusor may inline and merge these graphs, but the semantic model remains
explicit continuation wiring.

### 4.3 Views

Byte input should use Moonlift views:

```moonlift
input: view(u8)
pos: index
```

The ABI can expand `view(u8)` to data/len/stride using the existing view ABI
phases.

### 4.4 Existing control validation

Generated regions should be ordinary Moonlift control regions.  Existing control
facts still apply:

- labels
- jump args
- yields/returns
- backedges
- type mismatches
- unterminated blocks

### 4.5 Existing vector layer

Scanning loops can expose vector candidates:

- class runs
- delimiter search
- literal search
- quote/comment scanning
- newline scanning
- `take_until`

Those should feed the existing `Moon2Vec` fact/decision style rather than use an
ad hoc parser-vector optimizer.

---

## 5. Proposed ASDL module: `Moon2Scan`

This section sketches the complete ASDL shape.  Exact field names can change, but
these semantic nouns should remain explicit.

### 5.1 Identifiers and source positions

```asdl
module Moon2Scan {
    SourceId = (string text) unique
    RuleId = (string text) unique
    TokenKind = (string name, number tag) unique
    CaptureId = (string text) unique
    ExpectId = (string text) unique
    DiagCode = (string key, number code) unique

    Offset = (number value) unique
    Span = (Moon2Scan.SourceId source, Moon2Scan.Offset start, Moon2Scan.Offset stop) unique
}
```

`Offset` is a source coordinate, not necessarily the same as an execution cursor.
A parser over bytes may use byte offsets.  A parser over tokens may use token
indexes.

### 5.2 Input kind and cursor model

```asdl
InputKind = InputBytes
          | InputUtf8Codepoints
          | InputTokens(Moon2Scan.TokenKind* kinds) unique
          | InputRecords(string record_kind) unique

CursorModel = CursorByteOffset
            | CursorUtf8Offset
            | CursorTokenIndex
            | CursorRecordIndex

Encoding = EncodingBytes
         | EncodingAscii
         | EncodingUtf8
```

The input kind is semantic.  A byte parser, UTF-8 parser, and token parser may all
use `index` at runtime, but they do not mean the same thing.

### 5.3 Byte and codepoint predicates

```asdl
ByteClass = ByteDigit
          | ByteAlpha
          | ByteAlnum
          | ByteWhitespace
          | ByteHex
          | ByteAscii
          | ByteAny

BytePred = ByteEq(number byte) unique
         | ByteRange(number lo, number hi) unique
         | ByteSet(number* bytes) unique
         | ByteClassPred(Moon2Scan.ByteClass class) unique
         | ByteNot(Moon2Scan.BytePred pred) unique
         | ByteAnd(Moon2Scan.BytePred* preds) unique
         | ByteOr(Moon2Scan.BytePred* preds) unique

UnicodeClass = UnicodeLetter
             | UnicodeDigit
             | UnicodeWhitespace
             | UnicodeIdentStart
             | UnicodeIdentContinue

CodepointPred = CodepointEq(number cp) unique
              | CodepointRange(number lo, number hi) unique
              | CodepointClass(Moon2Scan.UnicodeClass class) unique
              | CodepointNot(Moon2Scan.CodepointPred pred) unique
              | CodepointAnd(Moon2Scan.CodepointPred* preds) unique
              | CodepointOr(Moon2Scan.CodepointPred* preds) unique
```

Byte predicates support JSON, CSV, logs, protocols, and ASCII source languages.
Codepoint predicates support Unicode-aware source parsing.

### 5.4 Expected values and diagnostics

```asdl
Expected = ExpectedByte(number byte) unique
         | ExpectedRange(number lo, number hi) unique
         | ExpectedClass(Moon2Scan.ByteClass class) unique
         | ExpectedCodepoint(number cp) unique
         | ExpectedLiteral(number* bytes) unique
         | ExpectedRule(Moon2Scan.RuleId rule) unique
         | ExpectedToken(Moon2Scan.TokenKind kind) unique
         | ExpectedNamed(string label) unique

FailKind = ParseMiss
         | ParseCommitted
         | ParseFatal

DiagFact = DiagExpected(Moon2Scan.DiagCode code, Moon2Scan.Expected expected) unique
         | DiagAtRule(Moon2Scan.DiagCode code, Moon2Scan.RuleId rule) unique
         | DiagRecoverable(Moon2Scan.DiagCode code) unique
         | DiagCommitted(Moon2Scan.DiagCode code) unique
         | DiagFatal(Moon2Scan.DiagCode code) unique

ParseError = ParseError(Moon2Scan.DiagCode code, Moon2Scan.Span span, Moon2Scan.FailKind kind) unique
```

Generated parsers may carry only `pos` and `i32 code` at runtime.  Full diagnostic
meaning remains in ASDL facts.

### 5.5 Output shapes

```asdl
OutputShape = OutUnit
            | OutScalar(Moon2Type.Type ty) unique
            | OutSpan
            | OutToken(Moon2Scan.TokenShape token) unique
            | OutTuple(Moon2Scan.OutputField* fields) unique
            | OutVariant(Moon2Scan.OutputVariant* variants) unique
            | OutList(Moon2Scan.OutputShape elem, Moon2Scan.ListPolicy policy) unique
            | OutNode(Moon2Scan.NodeShape node) unique
            | OutFacts(Moon2Scan.FactShape fact) unique
            | OutSink(Moon2Scan.SinkProtocol sink) unique

OutputField = (string name, Moon2Scan.OutputShape shape) unique
OutputVariant = (string name, Moon2Scan.OutputField* fields) unique

ListPolicy = ListDiscard
           | ListCountOnly
           | ListSpan
           | ListEmitEach
           | ListArena
           | ListFixedMax(number max) unique
```

Output shape is the bridge between parser algebra and executable continuation
protocols.

Examples:

- `OutUnit`: whitespace skipper
- `OutScalar(u32)`: decimal integer parser
- `OutSpan`: identifier scanner
- `OutToken(...)`: lexer token
- `OutTuple(...)`: log/CSV projection
- `OutNode(...)`: AST node
- `OutFacts(...)`: compiler/editor fact stream

### 5.6 Captures

```asdl
Capture = CaptureSpan(Moon2Scan.CaptureId id, string name) unique
        | CaptureBytes(Moon2Scan.CaptureId id, string name) unique
        | CaptureScalar(Moon2Scan.CaptureId id, string name, Moon2Type.Type ty) unique
        | CaptureToken(Moon2Scan.CaptureId id, string name, Moon2Scan.TokenShape shape) unique
        | CaptureNode(Moon2Scan.CaptureId id, string name, Moon2Scan.NodeShape shape) unique
```

Captures are parser outputs, not mutable side effects.  Lowering may represent a
span as `(start, len)`, a scalar as a register, or a node as a fact/arena handle.

### 5.7 Tokens and lexer modes

```asdl
TokenShape = TokenUnit(Moon2Scan.TokenKind kind) unique
           | TokenSpan(Moon2Scan.TokenKind kind) unique
           | TokenScalar(Moon2Scan.TokenKind kind, Moon2Type.Type ty) unique
           | TokenFields(Moon2Scan.TokenKind kind, Moon2Scan.OutputField* fields) unique

Channel = ChannelMain
        | ChannelTrivia
        | ChannelComment
        | ChannelError

TokenDecl = TokenDecl(Moon2Scan.TokenKind kind, Moon2Scan.Parser parser, Moon2Scan.Channel channel) unique

LexerMode = (string name) unique

ModeTransition = ModeStay
               | ModePush(Moon2Scan.LexerMode mode) unique
               | ModePop
               | ModeSwitch(Moon2Scan.LexerMode mode) unique

ModeRule = ModeRule(Moon2Scan.LexerMode mode, Moon2Scan.TokenDecl token, Moon2Scan.ModeTransition transition) unique

TokenPred = TokenIs(Moon2Scan.TokenKind kind) unique
          | TokenIn(Moon2Scan.TokenKind* kinds) unique
          | TokenHasField(Moon2Scan.TokenKind kind, string field) unique
```

Lexer modes cover strings, comments, template languages, nested constructs,
indentation modes, and language islands.  Tokens are optional materialized facts,
not a mandatory boundary.

### 5.8 Parser algebra

```asdl
ChoiceMode = ChoiceOrdered
           | ChoiceDisjoint
           | ChoiceLongest
           | ChoicePriority
           | ChoiceCommitted
           | ChoiceAmbiguous

RepeatMode = RepeatZeroMore
           | RepeatOneMore
           | RepeatExact(number n) unique
           | RepeatMin(number min) unique
           | RepeatMinMax(number min, number max) unique
           | RepeatUntil(Moon2Scan.Parser terminator) unique
           | RepeatSeparated(Moon2Scan.Parser sep, Moon2Scan.SepPolicy policy) unique

SepPolicy = SepNoTrailing
          | SepAllowTrailing
          | SepRequireTrailing

Parser = PEmpty
       | PFail(Moon2Scan.Expected expected) unique
       | PByte(Moon2Scan.BytePred pred, Moon2Scan.Expected expected) unique
       | PCodepoint(Moon2Scan.CodepointPred pred, Moon2Scan.Expected expected) unique
       | PToken(Moon2Scan.TokenPred pred, Moon2Scan.Expected expected) unique
       | PLiteral(number* bytes, Moon2Scan.Expected expected) unique
       | PPattern(Moon2Scan.Pattern pattern, Moon2Scan.Expected expected) unique

       | PSeq(Moon2Scan.Parser* parts) unique
       | PChoice(Moon2Scan.ChoiceMode mode, Moon2Scan.Parser* arms) unique
       | PRepeat(Moon2Scan.RepeatMode mode, Moon2Scan.Parser body) unique
       | POptional(Moon2Scan.Parser body) unique
       | PLookahead(Moon2Scan.Parser body) unique
       | PNot(Moon2Scan.Parser body, Moon2Scan.Expected expected) unique
       | PCut(Moon2Scan.Parser body) unique

       | PCapture(Moon2Scan.Capture capture, Moon2Scan.Parser body) unique
       | PMap(Moon2Scan.Action action, Moon2Scan.Parser body) unique
       | PEmit(Moon2Scan.EmitShape emit, Moon2Scan.Parser body) unique

       | PRef(Moon2Scan.RuleId rule) unique
       | PLet(Moon2Scan.ParserBinding* bindings, Moon2Scan.Parser body) unique

       | PRecover(Moon2Scan.RecoveryPolicy policy, Moon2Scan.Parser body) unique
       | PLabel(Moon2Scan.Expected expected, Moon2Scan.Parser body) unique
```

This algebra intentionally includes low-level scanner primitives and high-level
parser constructs.  Fusion decisions decide how much of the structure remains as
runtime boundaries.

### 5.9 Patterns and regular sublanguages

```asdl
RunBound = RunUnbounded
         | RunExact(number n) unique
         | RunMin(number min) unique
         | RunMinMax(number min, number max) unique

EscapePolicy = EscapeNone
             | EscapeBackslash
             | EscapeDoubleQuote
             | EscapeCustom(number byte) unique

Pattern = PatternBytes(number* bytes) unique
        | PatternTrie(number** literals) unique
        | PatternClassRun(Moon2Scan.BytePred pred, Moon2Scan.RunBound bound) unique
        | PatternUntil(Moon2Scan.BytePred terminator, Moon2Scan.EscapePolicy escape) unique
        | PatternRegex(Moon2Scan.RegexAst ast) unique
        | PatternAhoCorasick(number** needles) unique

RegexAst = RegexEmpty
         | RegexByte(Moon2Scan.BytePred pred) unique
         | RegexSeq(Moon2Scan.RegexAst* parts) unique
         | RegexAlt(Moon2Scan.RegexAst* arms) unique
         | RegexRepeat(Moon2Scan.RegexAst body, Moon2Scan.RepeatMode mode) unique
         | RegexCapture(string name, Moon2Scan.RegexAst body) unique
```

Regex-like power is allowed only when the regex is parsed into ASDL.  A regex
string by itself is not meaningful to PVM.

### 5.10 Actions

```asdl
Action = ActionIdentity
       | ActionScalar(Moon2Scan.ActionScalarOp op) unique
       | ActionExprFrag(Moon2Open.ExprFrag frag) unique
       | ActionRegionFrag(Moon2Open.RegionFrag frag) unique
       | ActionConstructNode(Moon2Scan.NodeCtor ctor) unique
       | ActionEmitFact(Moon2Scan.FactCtor ctor) unique

ActionScalarOp = ScalarParseU32Decimal
               | ScalarParseI32Decimal
               | ScalarParseU64Decimal
               | ScalarParseI64Decimal
               | ScalarParseF64Decimal
               | ScalarParseHexU64
               | ScalarParseBoolLiteral
```

No Lua runtime callback is permitted as semantic action.  Custom semantic actions
must be Moonlift expression/region fragments or explicit ASDL constructors.

### 5.11 Nodes, facts, and build policy

```asdl
NodeShape = NodeStruct(string name, Moon2Scan.NodeField* fields) unique
          | NodeVariant(string family, string variant, Moon2Scan.NodeField* fields) unique

NodeField = NodeField(string name, Moon2Scan.OutputShape shape) unique

NodeCtor = NodeCtor(string family, string variant, Moon2Scan.NodeField* fields) unique

FactShape = FactToken
          | FactAstNode
          | FactBinding
          | FactDiagnostic
          | FactCustom(string family) unique

FactCtor = FactCtor(string family, string variant, Moon2Scan.OutputField* fields) unique

BuildPolicy = BuildNone
            | BuildFlatFacts
            | BuildArenaNodes
            | BuildTree
            | BuildProjectionOnly
```

This lets the same grammar produce very different runtime outputs:

- no output, just validation
- selected typed projection fields
- token facts
- AST flat facts
- arena/tree nodes
- diagnostics/recovery facts

### 5.12 Recovery

```asdl
DelimiterPair = DelimiterPair(Moon2Scan.Expected open, Moon2Scan.Expected close) unique

RecoveryStop = RecoveryStopAtExpected(Moon2Scan.Expected expected) unique
             | RecoveryStopAtAny(Moon2Scan.Expected* expected) unique
             | RecoveryStopAtLine
             | RecoveryStopAtEof

RecoveryPolicy = RecoverNone
               | RecoverToByte(Moon2Scan.BytePred pred) unique
               | RecoverToToken(Moon2Scan.TokenKind kind) unique
               | RecoverToAnyToken(Moon2Scan.TokenKind* kinds) unique
               | RecoverBalanced(Moon2Scan.DelimiterPair* pairs, Moon2Scan.RecoveryStop stop) unique
               | RecoverLine
               | RecoverStatement

RecoveryFact = RecoverySkipped(Moon2Scan.Span span, Moon2Scan.RecoveryPolicy policy) unique
             | RecoveryInserted(Moon2Scan.Expected expected, Moon2Scan.Offset at) unique
             | RecoveryResumed(Moon2Scan.Offset at) unique
```

Recovery is required for source-language and LSP use cases.  It must be explicit
so fast batch parsers can choose `RecoverNone` while editor parsers can produce
partial facts.

### 5.13 Grammar and policies

```asdl
ParserBinding = ParserBinding(string name, Moon2Scan.Parser parser) unique

AmbiguityPolicy = AmbiguityReject
                | AmbiguityFirst
                | AmbiguityAll
                | AmbiguityFacts

CommitPolicy = CommitNever
             | CommitOnConsume
             | CommitExplicitCut

GrammarPolicy = GrammarPolicy(
    Moon2Scan.ChoiceMode choice_default,
    Moon2Scan.CommitPolicy commit,
    Moon2Scan.BuildPolicy build,
    Moon2Scan.RecoveryPolicy recovery,
    Moon2Scan.AmbiguityPolicy ambiguity
) unique

Rule = Rule(
    Moon2Scan.RuleId id,
    string name,
    Moon2Scan.InputKind input,
    Moon2Scan.Parser parser,
    Moon2Scan.OutputShape output
) unique

Grammar = Grammar(
    string name,
    Moon2Scan.InputKind input,
    Moon2Scan.Rule* rules,
    Moon2Scan.RuleId entry,
    Moon2Scan.GrammarPolicy policy
) unique
```

A `Grammar` is a named graph.  Recursive grammars must use `PRef`/`RuleId`, not
accidental Lua recursion.

---

## 6. Choice, cut, and backtracking semantics

Choice is one of the main places traditional parser systems become unclear.  The
mode must be explicit.

### 6.1 Ordered choice

```text
ChoiceOrdered(A, B)
```

Meaning:

1. Try `A`.
2. If `A` returns `ok`, accept `A`.
3. If `A` returns `miss`, reset cursor and try `B`.
4. If `A` returns `fail`, propagate failure.

### 6.2 Disjoint choice

```text
ChoiceDisjoint(A, B, C)
```

Meaning:

- arms are semantically expected to have disjoint FIRST sets
- validation may reject overlap
- fusor may lower to switch/trie dispatch

### 6.3 Longest choice

```text
ChoiceLongest(A, B)
```

Meaning:

- evaluate candidates according to longest-match semantics
- diagnostics can still record arm expectations
- useful for lexers where `==` beats `=` and keyword/identifier overlap exists

### 6.4 Committed choice

```text
ChoiceCommitted(A, B)
```

Meaning:

- once an arm consumes or crosses a cut boundary, later arms are not tried
- supports efficient source parsers and better errors

### 6.5 Cut

```text
PCut(body)
```

A cut converts later local misses into committed failures.  Example:

```lua
P.seq(P.literal("let"), P.cut(), ident, P.literal("="), expr)
```

After `let` is recognized, failure to parse an identifier or `=` is a syntax
error for a `let` statement, not a reason to try every other statement parser.

---

## 7. Repetition semantics

Repetition is explicit because it controls termination, output storage, and
fusion.

### 7.1 Progress rule

Any unbounded repeat must prove progress:

```text
RepeatZeroMore(body)
RepeatOneMore(body)
RepeatUntil(...)
RepeatSeparated(...)
```

If `body` can succeed without consuming input, validation must reject or require
an explicit bounded strategy.

### 7.2 Output accumulation

Repetition output uses `ListPolicy`:

- `ListDiscard`: whitespace/comments
- `ListCountOnly`: count parsed items
- `ListSpan`: produce one span covering the repeated region
- `ListEmitEach`: emit token/fact per item
- `ListArena`: materialize list nodes
- `ListFixedMax(n)`: bounded stack/register storage

This avoids forcing all repeats to allocate arrays.

---

## 8. Numeric and scalar parsing

Numeric parsers should be first-class action/parser nodes, not generic string
captures followed by later conversion.

Examples:

```lua
P.u32("count")
P.i64("offset")
P.f64("latency")
P.hex_u64("mask")
```

Semantic lowering:

```text
scan digits
accumulate numeric value
check overflow/range
return typed scalar
```

ASDL representation uses `ActionScalarOp` or dedicated parser nodes if needed.
The important rule is that conversion semantics are visible as ASDL.

---

## 9. Region protocol lowering

### 9.1 General parser fragment protocol

For byte input:

```moonlift
region parse_rule(input: view(u8), pos: index;
                  ok: cont(next: index, out...),
                  miss: cont(pos: index, expected: i32),
                  fail: cont(pos: index, error: i32))
entry start()
    ...
end
end
```

For token input:

```moonlift
region parse_rule(tokens: view(Token), pos: index;
                  ok: cont(next: index, out...),
                  miss: cont(pos: index, expected: i32),
                  fail: cont(pos: index, error: i32))
```

The output continuation shape comes from `OutputShape`.

### 9.2 Byte predicate lowering

`PByte(ByteEq(65))` lowers to:

```moonlift
if pos >= len(input) then jump miss(pos = pos, expected = code_eof) end
let c: i32 = as(i32, input[pos])
if c == 65 then jump ok(next = pos + 1) end
jump miss(pos = pos, expected = code_A)
```

`ByteRange(lo, hi)` lowers to bounds comparisons.
`ByteSet` may lower to a switch, bitset test, or lookup table depending on
`scan_decide`.

### 9.3 Sequence lowering

`PSeq(A, B, C)` lowers by continuation wiring:

```text
A.ok -> B
B.ok -> C
C.ok -> outer ok
A.miss/fail -> outer miss/fail
B.miss/fail -> outer miss/fail
C.miss/fail -> outer miss/fail
```

Intermediate captures become block parameters or locals.  If output shapes can be
elided, they are not materialized.

### 9.4 Choice lowering

Disjoint byte choices lower to switch/trie dispatch:

```moonlift
switch as(i32, input[pos]) do
case 71 then ... -- 'G'
case 80 then ... -- 'P'
default then jump miss(pos = pos, expected = code_choice)
end
```

Ordered choice lowers with explicit checkpoint/reset:

```text
try A at original pos
on A.miss -> try B at original pos
on A.fail -> fail
```

### 9.5 Repeat lowering

`PRepeat(RepeatZeroMore, body)` lowers to a loop:

```moonlift
block loop(pos: index = start, accumulators...)
    emit body(input, pos; ok = got, miss = done, fail = bad)
end
block got(next: index, values...)
    -- progress proof says next > pos
    jump loop(pos = next, accumulators = updated)
end
block done(pos: index)
    jump ok(next = pos, output = accumulators)
end
block bad(pos: index, error: i32)
    jump fail(pos = pos, error = error)
end
```

### 9.6 Capture span lowering

`PCapture(CaptureSpan(name), body)` lowers by saving start position:

```text
start = pos
body.ok(next, ...) -> ok(next, start, next - start, ...)
```

### 9.7 Lookahead and negation

`PLookahead(body)`:

```text
body.ok(next, out) -> ok(original_pos, out)
body.miss/fail -> propagate according to policy
```

`PNot(body)`:

```text
body.ok -> miss/fail expected-not
body.miss -> ok(original_pos)
body.fail -> fail
```

---

## 10. Fusion facts, validation, and decisions

### 10.1 Facts

```asdl
ScanFact = FactNullable(Moon2Scan.Parser parser) unique
         | FactConsumes(Moon2Scan.Parser parser) unique
         | FactCanFail(Moon2Scan.Parser parser) unique
         | FactFirstBytes(Moon2Scan.Parser parser, Moon2Scan.BytePred pred) unique
         | FactFollowBytes(Moon2Scan.Parser parser, Moon2Scan.BytePred pred) unique
         | FactOutputShape(Moon2Scan.Parser parser, Moon2Scan.OutputShape shape) unique
         | FactCapture(Moon2Scan.Parser parser, Moon2Scan.Capture capture) unique
         | FactRegular(Moon2Scan.Parser parser) unique
         | FactDeterministic(Moon2Scan.Parser parser) unique
         | FactBacktrackBound(Moon2Scan.Parser parser, number max) unique
         | FactDelimited(Moon2Scan.Parser parser, Moon2Scan.Expected delimiter) unique
         | FactVectorScanCandidate(Moon2Scan.Parser parser) unique
         | FactTokenBoundary(Moon2Scan.Parser parser) unique
         | FactTokenObservable(Moon2Scan.TokenKind kind, Moon2Scan.TokenUse use) unique
```

### 10.2 Rejects

```asdl
ScanReject = RejectDuplicateRule(Moon2Scan.RuleId rule) unique
           | RejectMissingRule(Moon2Scan.RuleId rule) unique
           | RejectShapeMismatch(Moon2Scan.Parser parser, Moon2Scan.OutputShape expected, Moon2Scan.OutputShape actual) unique
           | RejectNullableRepeat(Moon2Scan.Parser parser) unique
           | RejectUnboundedBacktrack(Moon2Scan.Parser parser) unique
           | RejectAmbiguousChoice(Moon2Scan.Parser parser) unique
           | RejectLeftRecursion(Moon2Scan.RuleId rule) unique
           | RejectInvalidRecovery(Moon2Scan.RecoveryPolicy policy, string reason) unique
           | RejectUnsupportedCapture(Moon2Scan.Capture capture) unique
```

### 10.3 Token observability

```asdl
TokenUse = TokenUseInternal
         | TokenUseDiagnostics
         | TokenUseLsp
         | TokenUsePublicOutput
```

Fusion law:

```text
Internal tokens may be elided.
Diagnostic/LSP/public tokens must be materialized or reconstructible.
```

### 10.4 Decisions

```asdl
FusionDecision = FuseInline(Moon2Scan.Parser parser) unique
               | FuseOutline(Moon2Scan.RuleId rule) unique
               | FuseChoiceSwitch(Moon2Scan.Parser parser) unique
               | FuseChoiceTrie(Moon2Scan.Parser parser) unique
               | FuseChoiceOrdered(Moon2Scan.Parser parser) unique
               | FuseRepeatLoop(Moon2Scan.Parser parser) unique
               | FusePatternDfa(Moon2Scan.Parser parser) unique
               | FuseAhoCorasick(Moon2Scan.Parser parser) unique
               | FuseVectorTakeUntil(Moon2Scan.Parser parser) unique
               | FuseMaterializeToken(Moon2Scan.TokenKind kind) unique
               | FuseElideToken(Moon2Scan.TokenKind kind) unique
               | FuseEmitFacts(Moon2Scan.Parser parser) unique
               | FuseBuildArena(Moon2Scan.Parser parser) unique

FusionPlan = FusionPlan(Moon2Scan.FusionDecision* decisions, Moon2Scan.ScanReject* rejects) unique
```

The important point is that fusion is not hidden optimization code.  It is a set
of explicit decisions over explicit facts.

---

## 11. Recursive grammars and expression parsing

### 11.1 Recursion facts

```asdl
RecursionFact = RecDirect(Moon2Scan.RuleId rule) unique
              | RecIndirect(Moon2Scan.RuleId from, Moon2Scan.RuleId to) unique
              | RecLeft(Moon2Scan.RuleId rule) unique
              | RecRight(Moon2Scan.RuleId rule) unique
              | RecNullableCycle(Moon2Scan.RuleId rule) unique
```

### 11.2 Recursion decisions

```asdl
RecursionDecision = RecLowerAsCalls(Moon2Scan.RuleId rule) unique
                  | RecLowerAsLoop(Moon2Scan.RuleId rule) unique
                  | RecPrattExpression(Moon2Scan.RuleId rule, Moon2Scan.PrattSpec spec) unique
                  | RecPackrat(Moon2Scan.RuleId rule) unique
                  | RecGLR(Moon2Scan.RuleId rule) unique
                  | RecReject(Moon2Scan.RuleId rule, Moon2Scan.ScanReject reject) unique
```

The design allows several strategies.  A deterministic data parser can lower to
regions directly.  A source-language expression grammar may use Pratt.  An
ambiguous grammar may emit ambiguity facts or use a GLR-like decision.

### 11.3 Pratt expression ASDL

```asdl
Precedence = (number level) unique

Assoc = AssocLeft | AssocRight | AssocNonassoc

PrattSpec = PrattSpec(
    Moon2Scan.PrattAtom* atoms,
    Moon2Scan.PrattPrefix* prefixes,
    Moon2Scan.PrattInfix* infixes,
    Moon2Scan.PrattPostfix* postfixes
) unique

PrattAtom = PrattAtom(Moon2Scan.Parser parser, Moon2Scan.NodeCtor ctor) unique
PrattPrefix = PrattPrefix(Moon2Scan.TokenKind op, Moon2Scan.Precedence prec, Moon2Scan.NodeCtor ctor) unique
PrattInfix = PrattInfix(Moon2Scan.TokenKind op, Moon2Scan.Precedence prec, Moon2Scan.Assoc assoc, Moon2Scan.NodeCtor ctor) unique
PrattPostfix = PrattPostfix(Moon2Scan.TokenKind op, Moon2Scan.Precedence prec, Moon2Scan.NodeCtor ctor) unique
```

Expression parsing becomes explicit parser data, not hand-coded helper control.

---

## 12. Hosted builder API proposal

The builder API should mirror ASDL.  All values returned by the API are
ASDL-backed hosted values.

### 12.1 Basic constructors

```lua
local P = moon.scan

P.empty()
P.fail("expected thing")
P.byte("=")
P.byte(61)
P.range("0", "9")
P.set("+-*/")
P.digit()
P.alpha()
P.alnum()
P.ws()
P.literal("Content-Length")
```

### 12.2 Composition

```lua
P.seq(a, b, c)
P.choice(a, b, c)              -- policy default from grammar
P.choice_ordered(a, b, c)
P.choice_disjoint(a, b, c)
P.longest(a, b, c)
P.committed(a, b, c)
P.repeat(p)
P.one_or_more(p)
P.optional(p)
P.lookahead(p)
P.not_(p)
P.cut(p)
```

### 12.3 Captures and values

```lua
P.capture_span("name", ident)
P.capture_bytes("raw", quoted)
P.capture_scalar("value", moon.u32, digits)
P.u32("value")
P.i64("offset")
P.f64("latency")
P.hex_u64("mask")
```

### 12.4 Tokens and lexer modes

```lua
local Ident = P.token_kind("Ident")
local Number = P.token_kind("Number")

P.token(Ident, ident, { channel = P.main })
P.token(Number, P.u64("value"), { channel = P.main })
P.mode("string")
P.mode_rule("string", string_content, P.stay())
P.mode_rule("string", quote, P.pop())
```

### 12.5 Nodes and facts

```lua
P.node("Assign", {
  name = ident,
  value = expr,
})

P.variant("Stmt", "Let", {
  name = ident,
  value = expr,
})

P.fact("Binding", "Local", {
  name = ident,
  span = P.current_span(),
})
```

### 12.6 Grammar

```lua
local G = P.grammar("Mini", {
  input = P.bytes(),
  entry = "stmt",
  policy = P.policy {
    choice = P.choice_ordered,
    commit = P.commit_explicit_cut,
    build = P.build_flat_facts,
    recovery = P.recover_statement,
    ambiguity = P.ambiguity_reject,
  },
})

G:rule("ident", ident, P.out_span())
G:rule("stmt", stmt, P.out_node("Stmt"))
```

### 12.7 Custom actions

Custom actions must be explicit Moonlift fragments:

```lua
local normalize = moon.expr_frag("normalize_digit", {
  moon.param("c", moon.u8),
}, moon.u32, function(e)
  return e.c:as(moon.u32) - moon.int(48)
end)

P.map(P.byte_range("0", "9"), P.action_expr(normalize))
```

No Lua callback action should exist in the semantic path.

---

## 13. Domain designs

### 13.1 JSON projection

Goal:

```text
JSON/JSONL input -> selected typed fields without building a DOM
```

Builder surface:

```lua
local J = moon.scan.json

local parser = J.project {
  user_id = J.path("user.id", J.u64 { required = true }),
  status = J.path("status", J.i32 { required = true }),
  latency = J.path("latency", J.f64 { required = false, default = 0.0 }),
}
```

Semantic ASDL nouns:

```asdl
JsonPath = JsonPath(string* parts) unique
JsonFieldPolicy = FieldRequired
                | FieldOptional
                | FieldDefault(Moon2Sem.ConstValue value) unique
                | FieldFirst
                | FieldLast
                | FieldRejectDuplicate
JsonProjection = JsonProjection(JsonProjectedField* fields) unique
JsonProjectedField = JsonProjectedField(string output_name, Moon2Scan.JsonPath path, Moon2Scan.OutputShape shape, Moon2Scan.JsonFieldPolicy policy) unique
```

Fusion strategy:

- field name matching lowers to trie/switch decisions
- irrelevant fields lower to a `skip_json_value` scanner
- selected numbers parse directly into typed scalars
- strings return spans or decoded buffers depending output policy
- duplicate/missing-field handling is explicit policy

Output protocol:

```text
ok(next, user_id: u64, status: i32, latency: f64)
miss/fail(pos, code)
```

No JSON object tree is required unless `BuildPolicy = BuildTree`.

### 13.2 CSV/schema parser

CSV requires explicit dialect data:

```asdl
CsvDialect = CsvDialect(
    number delimiter,
    number quote,
    Moon2Scan.EscapePolicy escape,
    Moon2Scan.NewlinePolicy newline,
    Moon2Scan.HeaderPolicy header
) unique

CsvColumn = CsvColumn(string name, number index, Moon2Type.Type ty, Moon2Scan.ColumnPolicy policy) unique
CsvSpec = CsvSpec(Moon2Scan.CsvDialect dialect, Moon2Scan.CsvColumn* columns, Moon2Scan.OutputShape output) unique
```

Fusion strategy:

- scan rows with quote/escape/newline states
- skip unneeded columns without materializing fields
- parse selected columns directly into typed scalars
- emit row tuple/facts

### 13.3 Logs and line protocols

Logs often need format-specialized parsers:

```lua
P.seq(
  P.literal("level="), P.enum("level", { "INFO", "WARN", "ERROR" }),
  P.ws1(),
  P.literal("latency="), P.u32("latency"),
  P.literal("ms")
)
```

Fusion strategy:

- literals as byte chains/trie
- enums as disjoint choice
- numbers as direct scalar loops
- whitespace as discard repeat
- line boundaries as chunk policy

### 13.4 Protocol parsers

Protocol parsers need length-dependent input:

```asdl
Parser = ...
       | PBytesLen(Moon2Tree.Expr len) unique
       | PSliceLen(Moon2Tree.Expr len) unique
       | PBounded(Moon2Scan.Parser body, Moon2Tree.Expr max) unique
```

The length expression must be a typed Moonlift expression or capture reference.
It cannot be a Lua callback.

Use cases:

- HTTP headers
- Redis RESP
- FIX
- binary packets
- custom RPC protocols

### 13.5 Source-language parser

Source languages need:

- token modes
- trivia channels
- Pratt expressions
- recovery
- AST facts
- diagnostics
- source spans
- stable node identity

Additional ASDL:

```asdl
NodeIdentity = NodeIdentity(Moon2Scan.RuleId rule, Moon2Scan.Span span, string structural_hash) unique
ParseFact = ParseFactToken(Moon2Scan.TokenKind kind, Moon2Scan.Span span) unique
          | ParseFactNode(string kind, Moon2Scan.Span span, Moon2Scan.NodeIdentity id) unique
          | ParseFactDiagnostic(Moon2Scan.ParseError error) unique
          | ParseFactRecovery(Moon2Scan.RecoveryFact fact) unique
```

The same grammar can produce more tokens/facts for editor mode and fewer
materialized objects for batch compiler mode.

---

## 14. Incremental parsing and editor integration

Incremental parsing should be modeled through source events and pure state
transition, not hidden mutable parser caches.

```asdl
SourceEvent = SourceInsert(Moon2Scan.SourceId source, Moon2Scan.Offset at, string text) unique
            | SourceDelete(Moon2Scan.SourceId source, Moon2Scan.Offset start, Moon2Scan.Offset stop) unique
            | SourceReplace(Moon2Scan.SourceId source, Moon2Scan.Offset start, Moon2Scan.Offset stop, string text) unique

SourceState = SourceState(Moon2Scan.SourceId source, string text, number version) unique
```

State transition:

```text
Apply(SourceState, SourceEvent) -> SourceState
```

Parse facts should carry spans and identities so LSP features consume parser
facts rather than rediscover source semantics.

---

## 15. Chunked and parallel parsing

Some formats have natural chunk boundaries:

- JSONL: newline
- logs: newline
- CSV: row boundary, respecting quotes
- metrics: newline
- fixed-size binary records

```asdl
ChunkPolicy = ChunkNone
            | ChunkByLine
            | ChunkByDelimiter(number* delimiter) unique
            | ChunkBalanced(Moon2Scan.DelimiterPair* pairs) unique
            | ChunkFixedSize(number bytes, Moon2Scan.ResyncPolicy resync) unique

ResyncPolicy = ResyncNone
             | ResyncToDelimiter(number* delimiter) unique
             | ResyncToByte(Moon2Scan.BytePred pred) unique

ChunkFact = ChunkBoundary(Moon2Scan.Offset start, Moon2Scan.Offset stop) unique
          | ChunkResync(Moon2Scan.Offset at, Moon2Scan.ResyncPolicy policy) unique
```

Chunking is not just an optimization.  It affects error recovery, parallelism,
and observable record boundaries, so it must be explicit.

---

## 16. Output storage and ABI

Repeated outputs, AST nodes, and tokens require explicit storage policy.

```asdl
OutputStorage = StorageRegisters
              | StorageStack
              | StorageArena(Moon2Scan.ArenaPolicy policy) unique
              | StorageFactStream
              | StorageCallbackSink(Moon2Type.Type sink_ty) unique

ArenaPolicy = ArenaBump
            | ArenaBounded(number max_bytes) unique
            | ArenaExternal
```

`StorageCallbackSink` is allowed only if the callback is a typed Moonlift/C ABI
surface.  It is not a Lua semantic callback.

---

## 17. PVM phase boundaries

### 17.1 `scan_facts`

Input:

```text
Moon2Scan.Grammar or Moon2Scan.Parser
```

Question:

```text
What structural facts are true about this grammar/parser?
```

Outputs:

- nullable facts
- consumes/progress facts
- can-fail facts
- FIRST/FOLLOW byte/token facts
- output shape facts
- capture facts
- recursion facts
- regular/deterministic facts
- token observability facts
- vector scan candidate facts

Triplet behavior:

```text
phase(grammar) -> stream of ScanFact / RecursionFact
```

### 17.2 `scan_validate`

Input:

```text
Grammar + facts
```

Question:

```text
Is the declared grammar legal under its policies?
```

Outputs:

- explicit `ScanReject` values
- no hidden assertion failures for grammar errors

Reject examples:

- duplicate rules
- missing refs
- nullable unbounded repeat
- shape mismatch across choice arms
- invalid recovery target
- left recursion without a declared strategy
- unsupported capture/action/storage policy

### 17.3 `scan_decide`

Input:

```text
Grammar + facts + rejects + target/policy information
```

Question:

```text
What parsing/fusion/storage strategy should be used?
```

Outputs:

- `FusionPlan`
- recursion decisions
- materialization decisions
- storage decisions
- vector-scan candidate decisions
- explicit rejects for unsupported strategies

### 17.4 `scan_to_region`

Input:

```text
Grammar + FusionPlan
```

Question:

```text
What Moonlift region fragments implement this parser?
```

Outputs:

- `Moon2Open.RegionFrag` values
- optional `Moon2Tree.Func` wrappers
- diagnostic mapping facts
- token/fact emission fragments where requested

### 17.5 Existing Moonlift phases

After `scan_to_region`, the generated regions should use normal Moonlift:

```text
open_expand
open_validate
tree_typecheck
tree_control_facts
tree_control_to_back
tree_to_back
vec_* where applicable
back_validate
backend execution
```

---

## 18. Diagnostics and reports

The runtime parser can return compact failures:

```text
pos: index
code: i32
kind: miss/fail/fatal
```

The diagnostic meaning is ASDL:

```text
DiagFact(code, expected/rule/kind)
```

A report phase can combine:

- source text
- source position index
- parser failure tuple
- diagnostic facts
- recovery facts

into editor/user diagnostics.  Parser execution should not format diagnostic
strings in the hot path.

---

## 19. Design anti-patterns

### 19.1 Hidden Lua actions

Wrong:

```lua
P.map(parser, function(x) return x + 1 end)
```

Right:

```lua
P.map(parser, P.action_expr(expr_frag))
```

### 19.2 Regex as opaque string

Wrong:

```lua
P.regex("[0-9]+")
```

Right:

```lua
P.regex(P.regex_seq(P.regex_class(P.digit()), P.regex_repeat(...)))
```

or a hosted regex parser that immediately produces `RegexAst` ASDL.

### 19.3 String tags for choice mode

Wrong:

```lua
P.choice("ordered", a, b)
```

Right:

```asdl
ChoiceOrdered
ChoiceDisjoint
ChoiceLongest
```

### 19.4 Mandatory token arrays

Wrong:

```text
bytes -> token array -> parser always
```

Right:

```text
token materialization is explicit and may be elided when unobserved
```

### 19.5 Parser VM hidden in Rust

Wrong:

```text
Moon2Scan lowers to a new Rust parser bytecode interpreter
```

Right:

```text
Moon2Scan lowers to Moonlift regions and existing backend commands
```

---

## 20. Worked examples

### 20.1 Decimal `u32`

Builder:

```lua
local u32 = P.u32("value")
```

Semantic shape:

```text
one-or-more digit
accumulate base-10 value
check overflow
capture scalar u32
```

Region outline:

```moonlift
region parse_u32(input: view(u8), pos: index;
                 ok: cont(next: index, value: u32),
                 miss: cont(pos: index, expected: i32),
                 fail: cont(pos: index, error: i32))
entry start()
    if pos >= len(input) then jump miss(pos = pos, expected = code_digit) end
    let c: i32 = as(i32, input[pos])
    if c < 48 then jump miss(pos = pos, expected = code_digit) end
    if c > 57 then jump miss(pos = pos, expected = code_digit) end
    jump loop(pos = pos, acc = 0)
end
block loop(pos: index, acc: u32)
    if pos >= len(input) then jump ok(next = pos, value = acc) end
    let c: i32 = as(i32, input[pos])
    if c < 48 then jump ok(next = pos, value = acc) end
    if c > 57 then jump ok(next = pos, value = acc) end
    -- overflow checks omitted here but represented in generated region
    jump loop(pos = pos + 1, acc = acc * 10 + as(u32, c - 48))
end
end
```

### 20.2 Key/value log line

Builder:

```lua
local log = P.seq(
  P.literal("user="), P.u32("user"),
  P.ws1(),
  P.literal("latency="), P.u32("latency"),
  P.ws1(),
  P.literal("status="), P.u32("status")
)
```

Output:

```text
OutTuple(user: u32, latency: u32, status: u32)
```

Fusion:

- literals inline as byte comparisons
- whitespace as discard loop
- integers as scalar loops
- no token materialization

### 20.3 HTTP method choice

Builder:

```lua
local method = P.choice_disjoint(
  P.literal("GET"),
  P.literal("POST"),
  P.literal("PUT"),
  P.literal("DELETE")
)
```

Facts:

```text
FIRST bytes: G, P, P, D
```

`POST` and `PUT` overlap on first byte, so the fusor may choose a trie:

```text
G -> GET
P -> O -> POST
  -> U -> PUT
D -> DELETE
```

### 20.4 Source statement with cut

Builder:

```lua
local let_stmt = P.seq(
  P.literal("let"),
  P.cut(P.ws1()),
  ident,
  P.ws0(),
  P.literal("="),
  P.ws0(),
  expr
)
```

Semantics:

- if `let` is seen but the rest fails, produce committed syntax error
- do not try other statement alternatives
- diagnostics should report expected identifier or `=` at the failing position

---

## 21. Open design questions

These are not reasons to defer the design; they are explicit areas where final
ASDL details should be chosen carefully.

1. Should `miss`, `fail`, and `fatal` be three continuations, or should `fail`
   carry `FailKind`?
2. Should spans use `(start, stop)` or `(start, len)` in output protocols?
3. Should `RegexAst` live in `Moon2Scan` or a separate `Moon2Regex` module?
4. How should output shape fields reference previous captures in length-dependent
   protocol parsers?
5. Should packrat/GLR decisions be in the initial ASDL even if not implemented
   immediately?
6. What is the canonical storage model for AST arena handles?
7. How should diagnostic code allocation remain deterministic across grammar
   edits?
8. How much of Unicode classification should be ASDL tables versus named
   intrinsic predicates?
9. Should JSON/CSV have first-class ASDL submodules or be libraries built purely
   from generic `Moon2Scan` nodes?

---

# 22. Phased implementation plan

This section is an implementation plan.  The design above is intentionally more
complete than any single implementation slice.

## Phase 0: schema and documentation foundation

Deliverables:

- add `Moon2Scan` ASDL module skeleton
- add constructors for ids, input kind, byte predicates, expected values, parser
  algebra, output shapes, diagnostics, facts, rejects, decisions
- add `SCAN_FUSOR_DESIGN.md` to `moonlift/README.md`
- add implementation checklist entries under a `Moon2Scan` section

Validation:

- ASDL context loads successfully
- constructors intern correctly
- representative parser values can be constructed in tests

PVM boundaries introduced:

```text
scan_facts
scan_validate
scan_decide
scan_to_region
```

They may initially return empty/unsupported reports, but their result shapes
should be real ASDL values.

## Phase 1: hosted builder values

Deliverables:

- `scan_values.lua`
- `scan_host_builders.lua`
- ASDL-backed hosted values for:
  - byte predicates
  - expected labels
  - parser nodes
  - output shapes
  - grammar/rule declarations

Builder coverage:

```lua
P.byte
P.range
P.set
P.digit
P.alpha
P.alnum
P.ws
P.literal
P.seq
P.choice_ordered
P.choice_disjoint
P.repeat
P.one_or_more
P.optional
P.capture_span
P.u32
P.grammar
P.rule
```

Validation:

- no parser builder returns plain domain tables
- all builder outputs expose underlying ASDL values
- tests compare expected ASDL node classes

## Phase 2: structural facts

Deliverables:

- `scan_facts.lua`
- fact gathering for:
  - nullable
  - consumes
  - can fail
  - FIRST byte predicates/sets
  - output shapes
  - captures
  - rule references

Validation:

- facts are deterministic and cacheable
- sequence/choice/repeat facts are covered by tests
- `pvm.report_string` shows stable reuse on repeated grammar analysis

## Phase 3: validation and rejects

Deliverables:

- `scan_validate.lua`
- validation result ASDL
- rejects for:
  - duplicate rules
  - missing refs
  - shape mismatches
  - nullable unbounded repeats
  - disjoint choice overlap
  - unsupported actions/captures

Validation:

- invalid grammars return rejects, not Lua errors
- reject facts carry enough source/grammar identity for diagnostics

## Phase 4: fusion decisions

Deliverables:

- `scan_decide.lua`
- decisions for:
  - inline parser
  - outline rule
  - ordered choice
  - switch/trie choice
  - repeat loop
  - token elision/materialization placeholder
  - scalar numeric parse strategy

Validation:

- decisions are ASDL values
- overlapping and disjoint choices choose different plans
- repeat decisions require progress facts

## Phase 5: region lowering for byte scanners

Deliverables:

- `scan_to_region.lua`
- lowering to `Moon2Open.RegionFrag` for:
  - `PEmpty`
  - `PFail`
  - `PByte`
  - `PLiteral`
  - `PSeq`
  - `PChoiceOrdered`
  - `PChoiceDisjoint`
  - `PRepeat`
  - `POptional`
  - `PCaptureSpan`
  - `P.u32`

Validation:

- generated regions pass existing typecheck/control validation
- generated functions can execute through current backend
- failure path returns deterministic position/code

## Phase 6: diagnostic mapping

Deliverables:

- diagnostic code allocation as ASDL facts
- report adapter from `(pos, code, kind)` to user diagnostic facts
- source span mapping for byte offsets

Validation:

- runtime parser returns compact failures
- report phase reconstructs expected labels/literals/ranges
- no hot-path string formatting

## Phase 7: token model and lexer modes

Deliverables:

- token kinds/shapes/channels
- token declarations
- lexer modes/transitions
- token materialization lowering
- token parser input kind basics

Validation:

- lexer can emit token facts/spans
- trivia/comment channels work
- simple token parser consumes materialized tokens

## Phase 8: lexer/parser fusion

Deliverables:

- token observability facts
- token elision/materialization decisions
- lowering path for byte parser + token parser fusion

Validation:

- internal tokens can be elided
- public/LSP tokens remain materialized or reconstructible
- fused and unfused parsers produce equivalent semantic outputs

## Phase 9: recovery and editor facts

Deliverables:

- recovery policies
- recovery facts
- partial parse facts
- source event/apply model integration
- stable node identities for source parsers

Validation:

- source parser can recover after common syntax errors
- LSP/editor facts consume parse facts instead of reparsing text

## Phase 10: recursive grammars and Pratt expressions

Deliverables:

- recursion facts
- recursion decisions
- Pratt ASDL and builder surface
- Pratt lowering strategy

Validation:

- expression DSL parser with precedence/associativity
- left recursion reject or explicit Pratt strategy
- diagnostics preserve operator expectations

## Phase 11: domain libraries

Deliverables:

- JSON projection library over `Moon2Scan`
- CSV dialect/schema library over `Moon2Scan`
- log-line helpers
- protocol length/slice parsers

Validation:

- JSON projection parses selected fields without DOM construction
- CSV parser skips unneeded columns
- protocol parser handles length-prefixed slices with bounds checks

## Phase 12: vector and advanced scan lowering

Deliverables:

- vector scan candidate facts connected to `Moon2Vec`
- delimiter/class-run vector decisions
- literal/trie/DFA lowering improvements
- Aho-Corasick or multi-needle scan decisions where justified

Validation:

- scalar fallback remains available
- vector decisions are explicit facts/decisions/rejects
- generated backend commands validate through existing backend layer

## Phase 13: full source-language parser integration

Deliverables:

- token modes/trivia/recovery/Pratt/fact output used for a nontrivial language
- LSP semantic tokens/folding/hover/completion consume parser facts where relevant
- grammar edits preserve diagnostic code stability where possible

Validation:

- batch compiler and editor modes use the same grammar
- materialization policy differs by declared outputs, not by separate parser code

---

## 23. Final design statement

Moonlift should provide a typed parser transducer algebra:

```text
Moon2Scan.Parser
```

with explicit ASDL for:

```text
input streams
cursor models
parser algebra
choice/repeat/cut semantics
tokens and lexer modes
captures and output shapes
diagnostics and recovery
recursive grammar strategy
fusion facts/rejects/decisions
region lowering
```

The hosted API should make this feel like parser combinators, but the generated
program should be fused Moonlift control flow.  Lexer/parser fusion is then not a
special trick.  It follows naturally from explicit token observability,
ASDL-visible parser boundaries, and PVM decisions over facts.
