-- MoonDasm: typed internal schema for the DynASM backend pipeline.
--
-- Design intent:
--   * pvm phases are fact-gathering boundaries.
--   * each lower layer consumes typed facts and produces narrower typed facts.
--   * emission consumes flat, target-shaped facts only.
--
-- This module is the canonical typed lowering surface for the DynASM backend.
-- No backward-compatibility payloads: phases communicate only through these
-- typed products/sums.

return function(A)
    return A.module "MoonDasm" {

        -- ─────────────────────────────────────────────────────────────
        -- Core ids and classes
        -- ─────────────────────────────────────────────────────────────

        A.product "DModuleId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "DBlockId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "DValId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "DLabelId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "DVirtualRegId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "DPhysRegId" {
            A.field "number" "number",
            A.unique,
        },

        A.sum "DRegClass" {
            A.variant "DGpr",
            A.variant "DXmm",
            A.variant "DFlags",
        },

        A.sum "DValueClass" {
            A.variant "DValueGpr" {
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "DValueXmm" {
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "DValueFlags",
            A.variant "DValueVector" {
                A.field "elem" "MoonBack.BackScalar",
                A.field "lanes" "number",
                A.variant_unique,
            },
        },

        -- ─────────────────────────────────────────────────────────────
        -- Module-level declarations and phase carriers
        -- ─────────────────────────────────────────────────────────────

        A.product "DSigEntry" {
            A.field "key" "string",
            A.field "params" (A.many "MoonBack.BackScalar"),
            A.field "results" (A.many "MoonBack.BackScalar"),
            A.unique,
        },

        A.product "DFuncEntry" {
            A.field "key" "string",
            A.field "sig" "string",
            A.field "visibility" "string",
            A.field "body" (A.many "MoonBack.Cmd"),
            A.unique,
        },

        A.product "DExternEntry" {
            A.field "key" "string",
            A.field "symbol" "string",
            A.field "sig" "string",
            A.unique,
        },

        A.product "DDataEntry" {
            A.field "key" "string",
            A.field "buf" "any", -- opaque ffi pointer/buffer owner
            A.field "size" "number",
            A.field "align" "number",
            A.unique,
        },

        A.product "DLabelPair" {
            A.field "key" "string",
            A.field "label" "string",
            A.unique,
        },

        A.product "DLabelMap" {
            A.field "funcs" (A.many "MoonDasm.DLabelPair"),
            A.field "externs" (A.many "MoonDasm.DLabelPair"),
            A.field "datas" (A.many "MoonDasm.DLabelPair"),
            A.unique,
        },

        -- Generic module-level phase payload used between module phases.
        A.product "DPhaseModule" {
            A.field "sigs" (A.many "MoonDasm.DSigEntry"),
            A.field "funcs" (A.many "MoonDasm.DFuncEntry"),
            A.field "externs" (A.many "MoonDasm.DExternEntry"),
            A.field "datas" (A.many "MoonDasm.DDataEntry"),
            A.field "func_order" (A.many "string"),
            A.field "extern_order" (A.many "string"),
            A.field "data_order" (A.many "string"),
            A.field "labels" "MoonDasm.DLabelMap",
            A.unique,
        },

        A.product "DTargetFacts" {
            A.field "target" "MoonBack.BackTargetModel",
            A.field "pointer_bits" "number",
            A.field "index_bits" "number",
            A.field "endianness" "string",
            A.field "features" (A.many "string"),
            A.unique,
        },

        -- ─────────────────────────────────────────────────────────────
        -- Function-level phase carriers
        -- ─────────────────────────────────────────────────────────────

        A.product "DFuncBody" {
            A.field "func" "MoonBack.BackFuncId",
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.unique,
        },

        -- Generic function-level phase payload used between function phases.
        A.product "DPhaseFunc" {
            A.field "func" (A.optional "MoonBack.BackFuncId"),
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.unique,
        },

        A.product "DScalarMapEntry" {
            A.field "key" "string",
            A.field "scalar" "string",
            A.unique,
        },

        A.product "DTypedFunc" {
            A.field "func" "MoonBack.BackFuncId",
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.field "value_scalars" (A.many "MoonDasm.DScalarMapEntry"),
            A.unique,
        },

        -- ─────────────────────────────────────────────────────────────
        -- CFG model (fact gathering over control + value flow)
        -- ─────────────────────────────────────────────────────────────

        A.product "DBlockParam" {
            A.field "value" "MoonBack.BackValId",
            A.field "ty" "MoonBack.BackShape",
            A.unique,
        },

        A.product "DEdgeArg" {
            A.field "src" "MoonBack.BackValId",
            A.field "dst_param" "MoonBack.BackValId",
            A.unique,
        },

        A.product "DSwitchCase" {
            A.field "raw" "string",
            A.field "dest" "MoonBack.BackBlockId",
            A.unique,
        },

        A.sum "DTerminator" {
            A.variant "DTermJump" {
                A.field "dest" "MoonBack.BackBlockId",
                A.field "args" (A.many "MoonDasm.DEdgeArg"),
                A.variant_unique,
            },
            A.variant "DTermBrIf" {
                A.field "cond" "MoonBack.BackValId",
                A.field "then_block" "MoonBack.BackBlockId",
                A.field "then_args" (A.many "MoonDasm.DEdgeArg"),
                A.field "else_block" "MoonBack.BackBlockId",
                A.field "else_args" (A.many "MoonDasm.DEdgeArg"),
                A.variant_unique,
            },
            A.variant "DTermSwitch" {
                A.field "value" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.field "cases" (A.many "MoonDasm.DSwitchCase"),
                A.field "default_dest" "MoonBack.BackBlockId",
                A.variant_unique,
            },
            A.variant "DTermReturnVoid",
            A.variant "DTermReturnValue" {
                A.field "value" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "DTermTrap",
        },

        A.product "DCfgBlock" {
            A.field "id" "MoonBack.BackBlockId",
            A.field "params" (A.many "MoonDasm.DBlockParam"),
            A.field "body" (A.many "MoonBack.Cmd"),
            A.field "term" "MoonDasm.DTerminator",
            A.unique,
        },

        A.product "DFuncCFG" {
            A.field "func" "MoonBack.BackFuncId",
            A.field "sig" "MoonBack.BackSigId",
            A.field "entry" "MoonBack.BackBlockId",
            A.field "blocks" (A.many "MoonDasm.DCfgBlock"),
            A.field "stack_slots" (A.many "MoonBack.BackStackSlotId"),
            A.unique,
        },

        -- ─────────────────────────────────────────────────────────────
        -- Fact gathering payloads (value/control/memory/call facts)
        -- ─────────────────────────────────────────────────────────────

        A.sum "DValueFact" {
            A.variant "DValueShapeFact" {
                A.field "value" "MoonBack.BackValId",
                A.field "shape" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "DValueClassFact" {
                A.field "value" "MoonBack.BackValId",
                A.field "class" "MoonDasm.DValueClass",
                A.variant_unique,
            },
            A.variant "DValueDefFact" {
                A.field "value" "MoonBack.BackValId",
                A.field "block" "MoonBack.BackBlockId",
                A.field "index" "number",
                A.variant_unique,
            },
            A.variant "DValueUseFact" {
                A.field "value" "MoonBack.BackValId",
                A.field "block" "MoonBack.BackBlockId",
                A.field "index" "number",
                A.field "slot" "number",
                A.variant_unique,
            },
            A.variant "DValueConstIntFact" {
                A.field "value" "MoonBack.BackValId",
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "DValueConstFloatFact" {
                A.field "value" "MoonBack.BackValId",
                A.field "raw" "string",
                A.variant_unique,
            },
        },

        A.sum "DEdgeKind" {
            A.variant "DEdgeEntry",
            A.variant "DEdgeJump",
            A.variant "DEdgeThen",
            A.variant "DEdgeElse",
            A.variant "DEdgeSwitchCase",
            A.variant "DEdgeSwitchDefault",
            A.variant "DEdgeCriticalSplit",
        },

        A.product "DEdgeRef" {
            A.field "pred" "MoonBack.BackBlockId",
            A.field "succ" "MoonBack.BackBlockId",
            A.field "kind" "MoonDasm.DEdgeKind",
            A.field "ordinal" "number",
            A.unique,
        },

        A.product "DParallelMove" {
            A.field "dst" "MoonBack.BackValId",
            A.field "src" "MoonBack.BackValId",
            A.field "class" "MoonDasm.DValueClass",
            A.unique,
        },

        A.product "DParallelCopy" {
            A.field "edge" "MoonDasm.DEdgeRef",
            A.field "moves" (A.many "MoonDasm.DParallelMove"),
            A.unique,
        },

        A.sum "DControlFact" {
            A.variant "DControlEdgeFact" {
                A.field "edge" "MoonDasm.DEdgeRef",
                A.field "args" (A.many "MoonDasm.DEdgeArg"),
                A.variant_unique,
            },
            A.variant "DParallelCopyFact" {
                A.field "copy" "MoonDasm.DParallelCopy",
                A.variant_unique,
            },
        },

        A.sum "DMemoryFact" {
            A.variant "DMemoryLoadFact" {
                A.field "dst" "MoonBack.BackValId",
                A.field "addr" "MoonBack.BackAddress",
                A.field "memory" "MoonBack.BackMemoryInfo",
                A.field "ty" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "DMemoryStoreFact" {
                A.field "addr" "MoonBack.BackAddress",
                A.field "value" "MoonBack.BackValId",
                A.field "memory" "MoonBack.BackMemoryInfo",
                A.field "ty" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "DMemoryAliasFact" {
                A.field "fact" "MoonBack.BackAliasFact",
                A.variant_unique,
            },
        },

        A.sum "DCallFact" {
            A.variant "DCallSiteFact" {
                A.field "index" "number",
                A.field "sig" "MoonBack.BackSigId",
                A.field "target" "MoonBack.BackCallTarget",
                A.field "args" (A.many "MoonBack.BackValId"),
                A.field "result" (A.optional "MoonBack.BackCallResult"),
                A.variant_unique,
            },
            A.variant "DCallClobberFact" {
                A.field "index" "number",
                A.field "clobbers" (A.many "MoonDasm.DPhysRegId"),
                A.variant_unique,
            },
        },

        A.product "DFuncFacts" {
            A.field "cfg" "MoonDasm.DFuncCFG",
            A.field "value_facts" (A.many "MoonDasm.DValueFact"),
            A.field "control_facts" (A.many "MoonDasm.DControlFact"),
            A.field "memory_facts" (A.many "MoonDasm.DMemoryFact"),
            A.field "call_facts" (A.many "MoonDasm.DCallFact"),
            A.unique,
        },

        -- Flat MoonBack-command fact set used for family-based instruction
        -- selection. MoonBack remains the source semantics; MoonDasm
        -- captures extracted lowering facts and selected asm shapes.
        A.sum "DConstKind" {
            A.variant "DConstUnknown",
            A.variant "DConstInt" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "DConstFloat" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "DConstBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
            A.variant "DConstNull",
        },

        A.sum "DAddrBaseKind" {
            A.variant "DBaseValue",
            A.variant "DBaseStack",
            A.variant "DBaseData",
            A.variant "DBaseUnknown",
        },

        A.sum "DFamilyKind" {
            A.variant "DFamilyCopy",
            A.variant "DFamilyIntBin",
            A.variant "DFamilyBitBin",
            A.variant "DFamilyShiftRotate",
            A.variant "DFamilyCompareBranch",
            A.variant "DFamilyLoadStore",
            A.variant "DFamilyAddress",
            A.variant "DFamilyCall",
            A.variant "DFamilyControl",
            A.variant "DFamilyReturn",
            A.variant "DFamilyOther",
        },

        A.sum "DFamilyKey" {
            A.variant "DKeyCopy" {
                A.field "class" "MoonDasm.DValueClass",
                A.field "src_const" "MoonDasm.DConstKind",
                A.field "same_value" "boolean",
                A.variant_unique,
            },
            A.variant "DKeyIntBin" {
                A.field "op" "string",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "lhs_const" "MoonDasm.DConstKind",
                A.field "rhs_const" "MoonDasm.DConstKind",
                A.field "commutative" "boolean",
                A.field "rhs_pow2" "boolean",
                A.variant_unique,
            },
            A.variant "DKeyBitBin" {
                A.field "op" "string",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "rhs_const" "MoonDasm.DConstKind",
                A.variant_unique,
            },
            A.variant "DKeyShiftRotate" {
                A.field "op" "string",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "rhs_const" "MoonDasm.DConstKind",
                A.field "rhs_small_imm" "boolean",
                A.variant_unique,
            },
            A.variant "DKeyCompareBranch" {
                A.field "op" "string",
                A.field "scalar" "MoonBack.BackScalar",
                A.field "rhs_const" "MoonDasm.DConstKind",
                A.field "fused_branch" "boolean",
                A.field "rhs_is_zero" "boolean",
                A.variant_unique,
            },
            A.variant "DKeyLoadStore" {
                A.field "is_load" "boolean",
                A.field "shape" "MoonBack.BackShape",
                A.field "base_kind" "MoonDasm.DAddrBaseKind",
                A.field "has_index" "boolean",
                A.field "const_disp" "boolean",
                A.field "align_bytes" "number",
                A.field "trap_kind" "string",
                A.variant_unique,
            },
            A.variant "DKeyAddress" {
                A.field "base_kind" "MoonDasm.DAddrBaseKind",
                A.field "elem_size" "number",
                A.field "const_offset" "number",
                A.variant_unique,
            },
            A.variant "DKeyCall" {
                A.field "target_kind" "string",
                A.field "argc" "number",
                A.field "has_result" "boolean",
                A.field "result_class" "MoonDasm.DValueClass",
                A.variant_unique,
            },
            A.variant "DKeyControl" {
                A.field "kind" "string",
                A.variant_unique,
            },
            A.variant "DKeyReturn" {
                A.field "has_value" "boolean",
                A.field "class" "MoonDasm.DValueClass",
                A.variant_unique,
            },
            A.variant "DKeyOther" {
                A.field "kind" "string",
                A.variant_unique,
            },
        },

        A.product "DFamilyInstance" {
            A.field "cmd_index" "number",
            A.field "block" (A.optional "MoonBack.BackBlockId"),
            A.field "family" "MoonDasm.DFamilyKind",
            A.field "key" "MoonDasm.DFamilyKey",
            A.unique,
        },

        A.sum "DFactAtom" {
            A.variant "DFactCmdKind" {
                A.field "cmd_index" "number",
                A.field "kind" "string",
                A.variant_unique,
            },
            A.variant "DFactValueShape" {
                A.field "value" "MoonBack.BackValId",
                A.field "shape" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "DFactValueClass" {
                A.field "value" "MoonBack.BackValId",
                A.field "class" "MoonDasm.DValueClass",
                A.variant_unique,
            },
            A.variant "DFactValueConst" {
                A.field "value" "MoonBack.BackValId",
                A.field "const_kind" "MoonDasm.DConstKind",
                A.variant_unique,
            },
            A.variant "DFactUse" {
                A.field "value" "MoonBack.BackValId",
                A.field "cmd_index" "number",
                A.field "slot" "number",
                A.variant_unique,
            },
            A.variant "DFactDef" {
                A.field "value" "MoonBack.BackValId",
                A.field "cmd_index" "number",
                A.variant_unique,
            },
            A.variant "DFactBlockAt" {
                A.field "cmd_index" "number",
                A.field "block" "MoonBack.BackBlockId",
                A.variant_unique,
            },
        },

        A.product "DFactSet" {
            A.field "func" (A.optional "MoonBack.BackFuncId"),
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.field "atoms" (A.many "MoonDasm.DFactAtom"),
            A.field "families" (A.many "MoonDasm.DFamilyInstance"),
            A.unique,
        },

        A.product "DLowerDecision" {
            A.field "cmd_index" "number",
            A.field "rule" "string",
            A.field "cost" "number",
            A.field "shape" "MoonDasm.DAsmShape",
            A.unique,
        },

        A.product "DLoweredFunc" {
            A.field "func" (A.optional "MoonBack.BackFuncId"),
            A.field "cmds" (A.many "MoonBack.Cmd"),
            A.field "facts" "MoonDasm.DFactSet",
            A.field "decisions" (A.many "MoonDasm.DLowerDecision"),
            A.field "asm" "MoonDasm.DAsmFunc",
            A.unique,
        },

        -- ─────────────────────────────────────────────────────────────
        -- Target-shaped asm facts
        -- ─────────────────────────────────────────────────────────────

        A.product "DAddress" {
            A.field "base" (A.optional "MoonDasm.DPhysRegId"),
            A.field "index" (A.optional "MoonDasm.DPhysRegId"),
            A.field "scale" "number",
            A.field "disp" "number",
            A.unique,
        },

        A.sum "DOperand" {
            A.variant "DOpVReg" {
                A.field "vreg" "MoonDasm.DVirtualRegId",
                A.variant_unique,
            },
            A.variant "DOpPReg" {
                A.field "preg" "MoonDasm.DPhysRegId",
                A.variant_unique,
            },
            A.variant "DOpImmI64" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "DOpLabel" {
                A.field "label" "MoonDasm.DLabelId",
                A.variant_unique,
            },
            A.variant "DOpMem" {
                A.field "addr" "MoonDasm.DAddress",
                A.variant_unique,
            },
        },

        A.sum "DCondCode" {
            A.variant "DccE",  A.variant "DccNE",
            A.variant "DccL",  A.variant "DccLE",
            A.variant "DccG",  A.variant "DccGE",
            A.variant "DccB",  A.variant "DccBE",
            A.variant "DccA",  A.variant "DccAE",
            A.variant "DccP",  A.variant "DccNP",
        },

        A.sum "DAsmShape" {
            A.variant "DAsmLabel" {
                A.field "label" "MoonDasm.DLabelId",
                A.variant_unique,
            },
            A.variant "DAsmMove" {
                A.field "dst" "MoonDasm.DOperand",
                A.field "src" "MoonDasm.DOperand",
                A.field "class" "MoonDasm.DValueClass",
                A.variant_unique,
            },
            A.variant "DAsmUnary" {
                A.field "op" "string",
                A.field "dst" "MoonDasm.DOperand",
                A.field "src" "MoonDasm.DOperand",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "DAsmBinary" {
                A.field "op" "string",
                A.field "dst" "MoonDasm.DOperand",
                A.field "lhs" "MoonDasm.DOperand",
                A.field "rhs" "MoonDasm.DOperand",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "DAsmCompareSet" {
                A.field "cc" "MoonDasm.DCondCode",
                A.field "dst" "MoonDasm.DOperand",
                A.field "lhs" "MoonDasm.DOperand",
                A.field "rhs" "MoonDasm.DOperand",
                A.field "scalar" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "DAsmLoad" {
                A.field "dst" "MoonDasm.DOperand",
                A.field "addr" "MoonDasm.DOperand",
                A.field "ty" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "DAsmStore" {
                A.field "addr" "MoonDasm.DOperand",
                A.field "value" "MoonDasm.DOperand",
                A.field "ty" "MoonBack.BackShape",
                A.variant_unique,
            },
            A.variant "DAsmLea" {
                A.field "dst" "MoonDasm.DOperand",
                A.field "addr" "MoonDasm.DOperand",
                A.variant_unique,
            },
            A.variant "DAsmJump" {
                A.field "dest" "MoonDasm.DLabelId",
                A.variant_unique,
            },
            A.variant "DAsmBrIf" {
                A.field "cond" "MoonDasm.DOperand",
                A.field "then_label" "MoonDasm.DLabelId",
                A.field "else_label" "MoonDasm.DLabelId",
                A.variant_unique,
            },
            A.variant "DAsmCall" {
                A.field "target" "MoonDasm.DOperand",
                A.field "args" (A.many "MoonDasm.DOperand"),
                A.field "result" (A.optional "MoonDasm.DOperand"),
                A.variant_unique,
            },
            A.variant "DAsmRetVoid",
            A.variant "DAsmRetValue" {
                A.field "value" "MoonDasm.DOperand",
                A.variant_unique,
            },
            A.variant "DAsmPrologue",
            A.variant "DAsmEpilogue",
            A.variant "DAsmTrap",
            A.variant "DAsmComment" {
                A.field "text" "string",
                A.variant_unique,
            },
        },

        A.product "DAsmInst" {
            A.field "shape" "MoonDasm.DAsmShape",
            A.field "defs" (A.many "MoonDasm.DVirtualRegId"),
            A.field "uses" (A.many "MoonDasm.DVirtualRegId"),
            A.field "clobbers" (A.many "MoonDasm.DPhysRegId"),
            A.unique,
        },

        A.product "DAsmBlock" {
            A.field "id" "MoonBack.BackBlockId",
            A.field "insts" (A.many "MoonDasm.DAsmInst"),
            A.unique,
        },

        A.product "DAsmFunc" {
            A.field "func" "MoonBack.BackFuncId",
            A.field "blocks" (A.many "MoonDasm.DAsmBlock"),
            A.unique,
        },

        -- ─────────────────────────────────────────────────────────────
        -- Allocation + frame facts
        -- ─────────────────────────────────────────────────────────────

        A.sum "DAllocLoc" {
            A.variant "DLocReg" {
                A.field "preg" "MoonDasm.DPhysRegId",
                A.variant_unique,
            },
            A.variant "DLocStack" {
                A.field "offset" "number",
                A.field "size" "number",
                A.field "align" "number",
                A.variant_unique,
            },
        },

        A.product "DValueAlloc" {
            A.field "vreg" "MoonDasm.DVirtualRegId",
            A.field "loc" "MoonDasm.DAllocLoc",
            A.field "class" "MoonDasm.DValueClass",
            A.unique,
        },

        A.product "DBankedRegalloc" {
            A.field "allocs" (A.many "MoonDasm.DValueAlloc"),
            A.field "used_callee_saved" (A.many "MoonDasm.DPhysRegId"),
            A.field "spill_size" "number",
            A.unique,
        },

        A.product "DFrameSlot" {
            A.field "slot" "MoonBack.BackStackSlotId",
            A.field "offset" "number",
            A.field "size" "number",
            A.field "align" "number",
            A.unique,
        },

        A.product "DFramePlan" {
            A.field "stack_size" "number",
            A.field "spill_size" "number",
            A.field "slot_size" "number",
            A.field "callee_saved" (A.many "MoonDasm.DPhysRegId"),
            A.field "slots" (A.many "MoonDasm.DFrameSlot"),
            A.unique,
        },

        -- ─────────────────────────────────────────────────────────────
        -- Emit/link facts
        -- ─────────────────────────────────────────────────────────────

        A.product "DFragment" {
            A.field "offset" "number",
            A.field "args" (A.many "number"),
            A.field "bytes" "string",
            A.unique,
        },

        A.product "DFragmentBundle" {
            A.field "fragments" (A.many "MoonDasm.DFragment"),
            A.unique,
        },

        A.product "DGlobalEntry" {
            A.field "kind" "string", -- "func" | "extern" | "data"
            A.field "key" "string",
            A.field "label" "string",
            A.field "slot_index" "number",
            A.unique,
        },

        A.product "DFuncPtrEntry" {
            A.field "func" "MoonBack.BackFuncId",
            A.field "global_slot" "number",
            A.unique,
        },

        A.product "DEmitPlan" {
            A.field "globals" (A.many "MoonDasm.DGlobalEntry"),
            A.field "fragments" (A.many "MoonDasm.DFragment"),
            A.field "func_ptrs" (A.many "MoonDasm.DFuncPtrEntry"),
            A.field "code_size_hint" "number",
            A.unique,
        },
    }
end
