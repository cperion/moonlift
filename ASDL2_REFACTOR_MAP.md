# Moonlift ASDL2 lossless refactor map

Status: design-only map for `moonlift/lua/moonlift/asdl2.lua`.

This document is the preservation map written before the ASDL2 draft.  The goal
is **not** to delete information from the current rich ASDL.  The goal is to
factor the same information into stable spines, explicit phase facets, fact
streams, decision values, and a smaller flat backend command algebra.

The current schema remains authoritative for the working compiler.  ASDL2 is a
coherent redesign draft.

---

## 1. Preservation rule

Every current ASDL constructor must move to one of these homes:

1. stable spine (`Expr`, `Stmt`, `Place`, `Control*Region`, `Item`, `Module`)
2. phase facet/header (`ExprHeader`, `StmtHeader`, control validation facets, etc.)
3. type-class / decision-class value (`BindingClass`, `Residence`, `CallTarget`, `FieldRef`, `SwitchKey`, etc.)
4. fact/proof/reject value (`MetaFact`, `VecLoopFacts`, `VecProof`, etc.)
5. backend command category plus backend op enum (`CmdBinary(BackBinaryOp, ...)`, etc.)
6. explicitly legacy-but-preserved surface form (`ExprDot`, old loop/`next` syntax only through a source-to-control sugar boundary)

No current semantic information is intentionally dropped in this draft.

---

## 2. New ASDL2 organization

ASDL2 uses explicit abstraction/layer modules, organized bottom-up so the lowest executable layer can be developed and covered first:

- `Moon2Core`
  - shared names/ids/scalars/literals/operators/intrinsics
- `Moon2Back`
  - lowest flat executable backend facts
  - old per-op `BackCmd*` variants are collapsed into command categories plus explicit backend op enums
- `Moon2Type`
  - reusable language type spine
- `Moon2Open`
  - slots/imports/open-code facets, fragments, fills, validation, rewrite facts
- `Moon2Bind`
  - bindings, value refs, residence decisions, env facets
- `Moon2Sem`
  - semantic facts/classes/decisions, layout and const values
- `Moon2Tree`
  - common source/typed/open/sem/code recursive spines
  - jump-first `ControlStmtRegion` / `ControlExprRegion` block graphs are the Moonlift control primitive; old structured loop/carry/`next` forms are preserved only as a source-to-control refactor note, not as base ASDL nodes
- `Moon2Vec`
  - vector/code-shape fact gathering, target facts, proofs, decisions, and selected vector IR
  - mostly preserves the current `MoonliftVec` information, but refers to `Moon2Tree` spines/facets

Major collapse axes:

- `SurfIntrinsic` / `ElabIntrinsic` / `MetaIntrinsic` / `SemIntrinsic` -> `Moon2.Intrinsic`
- primitive scalar type atoms -> `Moon2.Scalar`
- per-op expression constructors -> `ExprUnary` / `ExprBinary` / `ExprCompare` / `ExprLogic` / `ExprCast`
- layer-specific expression trees -> common `Expr` spine + `ExprHeader`
- layer-specific statement trees -> common `Stmt` spine + `StmtHeader`
- layer-specific place trees -> common `Place` spine + `PlaceHeader`
- `SemBackBinding` cross-product -> `Binding` + `BindingClass` + `Residence` / `MachineBinding`
- `SemBackSwitch*` -> `SwitchKey` / `SwitchDecision`
- `BackCmdIadd` etc. -> `CmdBinary(BackBinaryOp.BackIadd, ...)`, etc.

---

## 3. Current `MoonliftSurface` -> ASDL2

| Current family | ASDL2 home |
|---|---|
| `SurfName` | `Moon2.Name` |
| `SurfPath` | `Moon2.Path` |
| `SurfIntrinsic` variants `SurfPopcount`, `SurfClz`, `SurfCtz`, `SurfRotl`, `SurfRotr`, `SurfBswap`, `SurfFma`, `SurfSqrt`, `SurfAbs`, `SurfFloor`, `SurfCeil`, `SurfTruncFloat`, `SurfRound`, `SurfTrap`, `SurfAssume` | `Moon2.Intrinsic` variants with the same semantic names |
| `SurfTypeExpr` scalar variants | `Moon2.Type = TScalar(Moon2.Scalar)` |
| `SurfTPtr` | `Moon2.TPtr` |
| `SurfTArray` | `Moon2.TArray(ArrayLenExpr(expr), elem)` |
| `SurfTSlice` | `Moon2.TSlice` |
| `SurfTView` | `Moon2.TView` |
| `SurfTFunc` | `Moon2.TFunc` |
| `SurfTClosure` | `Moon2.TClosure` |
| `SurfTNamed(path)` | `Moon2.TNamed(TypeRefPath(path))` |
| `SurfParam` | `Moon2.Param` |
| `SurfFieldDecl` | `Moon2.FieldDecl` |
| `SurfVariant` | `Moon2.VariantDecl` |
| `SurfFieldInit` | `Moon2.FieldInit` |
| `SurfSwitchStmtArm` | `Moon2.SwitchStmtArm(SwitchKeyExpr(key), body)` |
| `SurfSwitchExprArm` | `Moon2.SwitchExprArm(SwitchKeyExpr(key), body, result)` |
| `SurfLoopCarryInit` | Legacy/sugar only: entry `EntryBlockParam` / ordinary `BlockParam` in a generated control region |
| `SurfLoopUpdate` | Legacy/sugar only: generated named `JumpArg` inside `StmtJump` to the loop header block |
| `SurfPlaceName` | `Moon2.PlaceRef(PlaceSurface, ValueRefName(name))` |
| `SurfPlacePath` | `Moon2.PlaceRef(PlaceSurface, ValueRefPath(path))` |
| `SurfPlaceDeref` | `Moon2.PlaceDeref` |
| `SurfPlaceDot` | `Moon2.PlaceDot` (authored ambiguous dot preserved) |
| `SurfPlaceField` | `Moon2.PlaceField(... FieldByName ...)` |
| `SurfPlaceIndex` | `Moon2.PlaceIndex` |
| `SurfDomainRange` | `Moon2.DomainRange` |
| `SurfDomainRange2` | `Moon2.DomainRange2` |
| `SurfDomainZipEq` | `Moon2.DomainZipEqValues` |
| `SurfDomainValue` | `Moon2.DomainValue` |
| `SurfStmtLoopWhile` | Legacy/sugar only: lower to `Moon2Tree.ControlStmtRegion` with an entry block, explicit block params, and backedge `StmtJump` args |
| `SurfStmtLoopOver` | Legacy/sugar only: lower to `Moon2Tree.ControlStmtRegion`; counted/domain facts are derived later from jumps, not represented as primitive loop nodes |
| `SurfExprLoopWhile` | Legacy/sugar only: lower to `Moon2Tree.ControlExprRegion(result_ty, ...)` with `StmtYieldValue` exits |
| `SurfExprLoopOver` | Legacy/sugar only: lower to `Moon2Tree.ControlExprRegion(result_ty, ...)`; no `next` primitive remains in Moonlift ASDL |
| parser diagnostics | `Moon2Parse.ParseResult(ModuleSurface, ParseIssue*)`; lexer tokens remain an internal fast representation |
| `SurfInt`, `SurfFloat`, `SurfBool`, `SurfNil` | `Moon2.ExprLit(ExprSurface, Literal)` |
| `SurfNameRef` | `Moon2.ExprRef(ExprSurface, ValueRefName(name))` |
| `SurfPathRef` | `Moon2.ExprRef(ExprSurface, ValueRefPath(path))` |
| `SurfExprDot` | `Moon2.ExprDot` (authored ambiguous dot preserved) |
| `SurfExprNeg`, `SurfExprNot`, `SurfExprBNot` | `Moon2.ExprUnary(ExprSurface, UnaryOp, value)` |
| `SurfExprRef` | `Moon2.ExprAddrOf` |
| `SurfExprDeref` | `Moon2.ExprDeref` |
| arithmetic variants `SurfExprAdd/Sub/Mul/Div/Rem` | `Moon2.ExprBinary(... BinaryOp ...)` |
| comparison variants `SurfExprEq/Ne/Lt/Le/Gt/Ge` | `Moon2.ExprCompare(... CmpOp ...)` |
| logical variants `SurfExprAnd/Or` | `Moon2.ExprLogic(... LogicOp ...)` |
| bit/shift variants `SurfExprBitAnd/BitOr/BitXor/Shl/LShr/AShr` | `Moon2.ExprBinary(... BinaryOp ...)` |
| cast variants `SurfExprCastTo/TruncTo/ZExtTo/SExtTo/BitcastTo/SatCastTo` | `Moon2.ExprCast(... SurfaceCastOp ...)` |
| `SurfExprIntrinsicCall` | `Moon2.ExprIntrinsic` |
| `SurfCall` | `Moon2.ExprCall(CallUnresolved(callee), args)` |
| `SurfField` | `Moon2.ExprField(... FieldByName ...)` |
| `SurfIndex` | `Moon2.ExprIndex` |
| `SurfAgg` | `Moon2.ExprAgg` |
| `SurfArrayLit` | `Moon2.ExprArray` |
| `SurfIfExpr` | `Moon2.ExprIf` |
| `SurfSelectExpr` | `Moon2.ExprSelect` |
| `SurfSwitchExpr` | `Moon2.ExprSwitch` |
| `SurfExprLoop` | Legacy/sugar only: `Moon2.ExprControl(ControlExprRegion(...))` |
| `SurfBlockExpr` | `Moon2.ExprBlock` |
| `SurfClosureExpr` | `Moon2.ExprClosure` |
| view constructors `SurfExprView*`, length queries | `Moon2.View*` wrapped by `Moon2.ExprView`; `len(view)` is `Moon2.ExprLen` |
| `SurfLet`, `SurfVar`, `SurfSet`, `SurfExprStmt`, `SurfAssert`, `SurfIf`, `SurfSwitch`, `SurfReturnVoid`, `SurfReturnValue` | same `Moon2.Stmt` spine variants with `StmtSurface` header |
| `SurfBreak`, `SurfBreakValue`, `SurfContinue`, `SurfStmtLoop` | not Moonlift primitives; if imported as legacy sugar, rewrite to `StmtYield*` / `StmtJump` inside explicit `Control*Region` values before entering the normal Moon2Tree pipeline |
| `SurfFuncLocal`, `SurfFuncExport` | `Moon2.Func` with `Visibility`; contract-bearing variants preserve source `requires` clauses and parameter memory modifiers |
| `SurfExternFunc` | `Moon2.ExternFunc` |
| `SurfConst` | `Moon2.ConstItem` |
| `SurfStatic` | `Moon2.StaticItem` |
| `SurfImport` | `Moon2.ImportItem` |
| `SurfStruct`, `SurfEnum`, `SurfTaggedUnion`, `SurfUnion` | `Moon2.TypeDecl` variants, including sugar variants so no authored information is lost |
| `SurfItem*` | `Moon2.Item*` |
| `SurfModule` | `Moon2.Module(ModuleSurface, items)` |

---

## 4. Current `MoonliftElab` -> ASDL2

| Current family | ASDL2 home |
|---|---|
| `ElabIntrinsic` | `Moon2.Intrinsic` |
| `ElabType` scalar/ptr/array/slice/view/func/named | `Moon2.Type` with `TypeRefGlobal` / `TypeRefLocal` where appropriate |
| `ElabBinding` variants | `Moon2.Binding(class = BindingClass...)` |
| `ElabLocalValue` | `BindingClassLocalValue` |
| `ElabLocalCell` | `BindingClassLocalCell` |
| `ElabArg` | `BindingClassArg(index)` |
| `ElabLoopCarry` | Legacy/sugar only: `BindingClassEntryBlockParam` / `BindingClassBlockParam` after loop-to-control rewriting |
| `ElabLoopIndex` | Legacy/sugar only: `BindingClassEntryBlockParam` / `BindingClassBlockParam` after loop-to-control rewriting |
| `ElabGlobalFunc/Const/Static` | corresponding `BindingClassGlobal*` |
| `ElabExtern` | `BindingClassExtern(symbol)` |
| `ElabValueEntry`, `ElabTypeEntry`, `ElabEnv` | `Moon2.ValueEntry`, `TypeEntry`, `Env` |
| `ElabFieldType`, `ElabTypeLayout` | `Moon2.FieldDecl`, `Moon2.TypeLayout` |
| `ElabConstEntry`, `ElabConstEnv` | `Moon2.ConstEntry`, `Moon2.ConstEnv` |
| `ElabStmtEnvEffect` | `Moon2.StmtEnvEffect` |
| `ElabParam`, `ElabFieldInit`, switch arms, control block params, named `JumpArg` values | common `Moon2` product types |
| `ElabPlace*` | common `Moon2.Place` with `PlaceTyped` header |
| `ElabIndexBase*` | `Moon2.IndexBase` |
| `ElabDomain*` | `Moon2.Domain*` |
| `ElabExprExit` | `Moon2.ExprExit` (`ExprEndOrYieldValue` for value-producing control regions) |
| `ElabOperandContext` | `Moon2.OperandContext` |
| `ElabLoop` | Legacy/sugar only: lower to `Moon2Tree.ControlStmtRegion` / `ControlExprRegion` before normal typed control validation |
| `ElabExpr` variants | common `Moon2.Expr` spine with `ExprTyped(type)` header; per-op variants collapse to op values |
| `ElabStmt` variants | common `Moon2.Stmt` spine with `StmtTyped` header |
| `ElabFunc`, `ElabExternFunc`, `ElabConst`, `ElabStatic`, `ElabImport`, `ElabTypeDecl`, `ElabItem`, `ElabModule` | common item/module spine with typed facets |

---

## 5. Current `MoonliftMeta` -> ASDL2

`MoonliftMeta` is not deleted.  It is factored into open facets and slot/use nodes
inside `Moon2`.

| Current family | ASDL2 home |
|---|---|
| `MetaModuleName` | `Moon2.ModuleNameFacet` |
| `MetaIntrinsic` | `Moon2.Intrinsic` |
| `MetaTypeSym`, `MetaFuncSym`, `MetaExternSym`, `MetaConstSym`, `MetaStaticSym` | same symbol product types in `Moon2` |
| all `Meta*Slot` products | same slot product types in `Moon2` |
| `MetaSlot` variants | `Moon2.Slot` variants |
| `MetaParam` | `Moon2.OpenParam` or ordinary `Moon2.Param` depending boundary |
| `MetaValueImport` | `Moon2.ValueImport` |
| `MetaTypeImport` | `Moon2.TypeImport` |
| `MetaFieldType`, `MetaTypeLayout` | `Moon2.FieldDecl`, `Moon2.TypeLayout(LayoutNamed/LayoutLocal)` |
| `MetaOpenSet` | `Moon2.OpenSet` |
| `MetaSourceBinding*`, `MetaSourceTypeEntry`, `MetaSourceEnv` | same source-env products in `Moon2` |
| `MetaParamBinding`, `MetaFillSet`, `MetaExpandEnv`, `MetaSeal*` | same open/expand/seal products in `Moon2` |
| `MetaType` | `Moon2.Type`; `MetaTLocalNamed` -> `TNamed(TypeRefLocal)`, `MetaTSlot` -> `TSlot` |
| `MetaBinding` variants | `Moon2.Binding` + `BindingClass` (`OpenParam`, `Import`, `FuncSym`, `ConstSym`, slots, etc.) |
| `MetaPlace`, `MetaIndexBase`, `MetaDomain` | common spines with `PlaceOpen` / slot variants |
| `MetaExprExit` | `Moon2.ExprExit` (`ExprEndOrYieldValue` where needed) |
| `MetaLoop` | Legacy/sugar only: open control regions use `Moon2Tree.ControlStmtRegion` / `ControlExprRegion` plus slots/fragments |
| `MetaExpr` variants | common `Moon2.Expr` spine with `ExprOpen(type, open)` header; `MetaExprSlotValue` -> `ExprSlotValue`; `MetaExprUseExprFrag` -> `ExprUseExprFrag` |
| `MetaStmt` variants | common `Moon2.Stmt` spine with `StmtOpen(open)` header; region slot/frag uses preserved |
| `MetaExprFrag`, `MetaRegionFrag` | `Moon2.ExprFrag`, `Moon2.RegionFrag` |
| `MetaFunc`, `MetaExternFunc`, `MetaConst`, `MetaStatic`, `MetaImport`, `MetaTypeDecl`, `MetaItem`, `MetaModule` | common item/module spine plus open facets and use/splice variants |
| `MetaSlotValue`, `MetaSlotBinding` | same slot-fill values in `Moon2` |
| `MetaRewriteRule`, `MetaRewriteSet` | same rewrite products in `Moon2`, but target common spines |
| `MetaFact`, `MetaFactSet` | same fact family in `Moon2` |
| `MetaValidationIssue`, `MetaValidationReport` | same issue/report family in `Moon2` |

---

## 6. Current `MoonliftSem` -> ASDL2

| Current family | ASDL2 home |
|---|---|
| `SemType` | `Moon2.Type`; `SemTRawPtr` -> `TScalar(RawPtr)`, `SemTPtrTo` -> `TPtr` |
| `SemIntrinsic` | `Moon2.Intrinsic` |
| `SemParam` | `Moon2.Param` |
| `SemBinding` | `Moon2.Binding` + `BindingClass` |
| `SemResidence`, `SemResidenceEntry`, `SemResidencePlan` | `Moon2.Residence`, `ResidenceDecision`, `ResidencePlan` |
| `SemBackBinding` | `Moon2.MachineBinding(binding, residence)` plus original global/extern binding class |
| `SemView` variants | `Moon2.View` variants |
| `SemDomainRange/Range2/View/ZipEq` | `Moon2.DomainRange/Range2/View/ZipEqViews` |
| `SemIndexBase` | `Moon2.IndexBase` |
| `SemCallTarget` | `Moon2.CallTarget` |
| `SemFieldRef` | `Moon2.FieldRef` |
| `SemFieldType`, `SemFieldLayout`, `SemMemLayout`, `SemTypeLayout`, `SemLayoutEnv` | `Moon2.FieldDecl`, `FieldLayout`, `MemLayout`, `TypeLayout`, `LayoutEnv` |
| `SemConst*` values/env/local/result | `Moon2.Const*` values/env/local/result, including explicit yield/jump statement results for control expressions |
| `SemFieldInit` | `Moon2.FieldInit` |
| `SemSwitch*Arm` | `Moon2.Switch*Arm` |
| `SemBackSwitchKey`, `SemBackSwitch*Arms` | `Moon2.SwitchKey`, `SwitchDecision` |
| `SemCarryPort`, `SemIndexPort`, `SemCarryUpdate` | Legacy/sugar only: block params and named `StmtJump` args are the Moonlift semantic control products |
| `SemPlace` | common `Moon2.Place` with `PlaceSem` header |
| `SemExpr` variants | common `Moon2.Expr` with `ExprSem(type, value_class, const_class)` header; `SemExprLoad` remains `ExprLoad`; `SemExprSelect` remains distinct from `ExprIf` |
| `SemExprExit` | `Moon2.ExprExit` (`ExprEndOrYieldValue`) |
| `SemCastOp` | `Moon2.MachineCastOp` |
| `SemLoop` | Legacy/sugar only: represented as typed/semantic control regions plus control facts/decisions |
| `SemStmt` | common `Moon2.Stmt` with sem facet |
| `SemFunc`, `SemExternFunc`, `SemConst`, `SemStatic`, `SemImport`, `SemTypeDecl`, `SemItem`, `SemModule` | common item/module spine with sem facet |

---

## 7. Current `MoonliftVec` -> ASDL2

`MoonliftVec` is preserved as `Moon2Vec`, because it already has the right
fact/decision/proof shape.  ASDL2 changes its references from `MoonliftSem.*` to
`Moon2.*` and keeps all current information.

| Current family | ASDL2 home |
|---|---|
| `VecExprId`, `VecLoopId`, `VecAccessId`, `VecValueId`, `VecBlockId` | same id products in `Moon2Vec` |
| `VecElem` | `Moon2Vec.VecElem`; scalar correspondence to `Moon2.Scalar` is explicit through facts/lowering |
| `VecShape` | same |
| `VecBinOp`, `VecUnaryOp` | same, but can be derived from `Moon2.BinaryOp/UnaryOp/Intrinsic` where useful |
| `VecReject` | same structured reject family |
| `VecTarget`, `VecTargetFact`, `VecTargetModel` | same target fact input family |
| `VecExprFact`, `VecExprGraph`, `VecExprResult`, `VecLocalFact`, `VecExprEnv`, `VecStmtResult` | same fact/result families, now referencing `Moon2.Expr`, `Moon2.Type`, `Moon2.Binding` |
| `VecRangeFact`, `VecDomain`, `VecInduction`, `VecMemoryBase`, `VecMemoryFact`, `VecAliasFact`, `VecDependenceFact`, `VecReductionFact`, `VecStoreFact` | same analysis facts, with ASDL2 explicitly separating alias facts from dependence facts and preserving whether memory came from raw address, view, or place indexing |
| `VecAccessKind`, `VecAccessPattern`, `VecAlignment`, `VecBounds`, `VecReassoc` | same type-class fact families |
| `VecProof` | same proof family, plus `VecProofAlias` so noalias/disjoint-view facts can justify dependence decisions |
| `VecLoopSource`, `VecLoopFacts` | loop facts are derived from `Control*Region` backedges; `VecLoopSourceControlRegion` preserves the source header/backedge and rejected candidates use `VecLoopSourceRejected(VecReject)` |
| `VecTail`, `VecLoopShape`, `VecShapeScore`, `VecLoopDecision` | same decision/evidence family |
| `FuncContract`, `ContractFact`, `ExprLen`, `VecKernelExpr`, `VecKernelCore`, `VecKernelPlan`, `VecKernelSafetyDecision` | explicit source memory/view contracts (`bounds`, `disjoint`, `same_len`, noalias/access modifiers) plus element-typed source-kernel vectorization planning and safety classification layer before selected vector/backend commands |
| `VecValue`, `VecParam`, `VecCmd`, `VecTerminator`, `VecBlock`, `VecFunc`, `VecModule` | same selected vector IR family, now sitting as `Sem -> Vec-aware Code -> Back` candidate |

---

## 8. Current `MoonliftBack` -> ASDL2

The backend remains flat, but command constructors are categorized.  No operation
identity is lost: old per-op command names become explicit backend op values.

| Current family | ASDL2 home |
|---|---|
| `BackScalar` | `Moon2Back.BackScalar` / maps to `Moon2.Scalar` |
| backend ids `BackSigId`, `BackFuncId`, `BackExternId`, `BackDataId`, `BackBlockId`, `BackValId`, `BackStackSlotId` | same id products in `Moon2Back` |
| `BackSwitchCase` | same |
| `BackVec` | same |
| declarations/control commands | `BackCmdCreateSig`, `BackCmdDeclareData`, `BackCmdDeclareFunc`, etc. become categorized `Cmd*` variants |
| constants `BackCmdConstInt/Float/Bool/Null` | `CmdConst(... BackLiteral ...)` |
| unary commands `Ineg/Fneg/Bnot/BoolNot/Popcount/Clz/Ctz/Bswap/Sqrt/Abs/Floor/Ceil/TruncFloat/Round` | `CmdUnary(BackUnaryOp, ...)` / `CmdIntrinsic(BackIntrinsicOp, ...)` |
| binary commands `Iadd/Isub/Imul/Fadd/Fsub/Fmul/Sdiv/Udiv/Fdiv/Srem/Urem/Band/Bor/Bxor/Ishl/Ushr/Sshr/Rotl/Rotr` | `CmdBinary(BackBinaryOp, ...)` |
| comparison commands signed/unsigned/float | `CmdCompare(BackCompareOp, ...)` |
| cast commands `Bitcast/Ireduce/Sextend/Uextend/Fpromote/Fdemote/SToF/UToF/FToS/FToU` | `CmdCast(BackCastOp, ...)` |
| load/store/memcpy/memset/select/fma | `CmdLoad`, `CmdStore`, `CmdMemcpy`, `CmdMemset`, `CmdSelect`, `CmdFma` |
| vector splat/add/sub/mul/band/bor/bxor/load/store/insert/extract | `CmdVecSplat`, `CmdBinary` with vector shape, `CmdLoad/Store` with vector shape, `CmdVecInsertLane`, `CmdVecExtractLane` |
| vector compare/select/mask commands | `CmdVecCompare(BackVecCompareOp, ...)`, `CmdVecSelect`, and `CmdVecMask(BackVecMaskOp, ...)`; source/vector planning keeps mask expressions explicit as `VecKernelMaskExpr` instead of treating masks as ordinary data vectors |
| call variants direct/extern/indirect value/stmt | `CmdCall(BackCallResult, BackCallTarget, sig, args)` |
| jump/br/switch/return/trap/finalize | same categorized terminator/control commands |
| `BackFlow`, `BackExprLowering`, `BackAddrLowering`, `BackViewLowering`, `BackReturnTarget`, `Back*Plan`, `BackProgram` | same result-shape/planning families, but point to categorized `Cmd*` |

---

## 9. Legacy preservation notes

The clean semantic target keeps these authored/source distinctions losslessly,
but old loop/carry/`next` forms are now preserved only by rewriting them into
jump-first control regions before normal Moonlift phases:

- old expression loops via `ControlExprRegion` plus `StmtYieldValue`
- old statement loops via `ControlStmtRegion` plus `StmtJump` backedges
- old break/break-value/continue only as legacy sugar rewrites to `StmtYield*` / `StmtJump`
- authored ambiguous dot via `ExprDot` / `PlaceDot`
- source enum/tagged-union sugar via `TypeDeclEnumSugar` / `TypeDeclTaggedUnionSugar`
- meta region/expression/module splice uses via explicit use/slot variants

A later cleanup pass can retire legacy sugar rewriting only after an explicit migration decision.
