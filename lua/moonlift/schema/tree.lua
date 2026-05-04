-- Clean MoonTree schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonTree" {
        A.sum "ExprHeader" {
            A.variant "ExprSurface",
            A.variant "ExprTyped" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ExprOpen" {
                A.field "ty" "MoonType.Type",
                A.field "open" "MoonOpen.OpenSet",
                A.variant_unique,
            },
            A.variant "ExprSem" {
                A.field "ty" "MoonType.Type",
                A.field "value_class" "MoonSem.ValueClass",
                A.field "const_class" "MoonSem.ConstClass",
                A.variant_unique,
            },
            A.variant "ExprCode" {
                A.field "ty" "MoonType.Type",
                A.field "shape" "MoonSem.CodeShapeClass",
                A.variant_unique,
            },
        },

        A.sum "PlaceHeader" {
            A.variant "PlaceSurface",
            A.variant "PlaceTyped" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "PlaceOpen" {
                A.field "ty" "MoonType.Type",
                A.field "open" "MoonOpen.OpenSet",
                A.variant_unique,
            },
            A.variant "PlaceSem" {
                A.field "ty" "MoonType.Type",
                A.field "address_class" "MoonSem.AddressClass",
                A.variant_unique,
            },
        },

        A.sum "StmtHeader" {
            A.variant "StmtSurface",
            A.variant "StmtTyped",
            A.variant "StmtOpen" {
                A.field "open" "MoonOpen.OpenSet",
                A.variant_unique,
            },
            A.variant "StmtSem" {
                A.field "flow" "MoonSem.FlowClass",
                A.variant_unique,
            },
            A.variant "StmtCode" {
                A.field "flow" "MoonSem.FlowClass",
                A.variant_unique,
            },
        },

        A.product "FieldInit" {
            A.field "name" "string",
            A.field "value" "MoonTree.Expr",
            A.unique,
        },

        A.product "SwitchStmtArm" {
            A.field "key" "MoonSem.SwitchKey",
            A.field "body" (A.many "MoonTree.Stmt"),
            A.unique,
        },

        A.product "SwitchExprArm" {
            A.field "key" "MoonSem.SwitchKey",
            A.field "body" (A.many "MoonTree.Stmt"),
            A.field "result" "MoonTree.Expr",
            A.unique,
        },

        A.sum "View" {
            A.variant "ViewFromExpr" {
                A.field "base" "MoonTree.Expr",
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ViewContiguous" {
                A.field "data" "MoonTree.Expr",
                A.field "elem" "MoonType.Type",
                A.field "len" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ViewStrided" {
                A.field "data" "MoonTree.Expr",
                A.field "elem" "MoonType.Type",
                A.field "len" "MoonTree.Expr",
                A.field "stride" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ViewRestrided" {
                A.field "base" "MoonTree.View",
                A.field "elem" "MoonType.Type",
                A.field "stride" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ViewWindow" {
                A.field "base" "MoonTree.View",
                A.field "start" "MoonTree.Expr",
                A.field "len" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ViewRowBase" {
                A.field "base" "MoonTree.View",
                A.field "row_offset" "MoonTree.Expr",
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ViewInterleaved" {
                A.field "data" "MoonTree.Expr",
                A.field "elem" "MoonType.Type",
                A.field "len" "MoonTree.Expr",
                A.field "stride" "MoonTree.Expr",
                A.field "lane" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ViewInterleavedView" {
                A.field "base" "MoonTree.View",
                A.field "elem" "MoonType.Type",
                A.field "stride" "MoonTree.Expr",
                A.field "lane" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.sum "Domain" {
            A.variant "DomainRange" {
                A.field "stop" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "DomainRange2" {
                A.field "start" "MoonTree.Expr",
                A.field "stop" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "DomainZipEqValues" {
                A.field "values" (A.many "MoonTree.Expr"),
                A.variant_unique,
            },
            A.variant "DomainValue" {
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "DomainView" {
                A.field "view" "MoonTree.View",
                A.variant_unique,
            },
            A.variant "DomainZipEqViews" {
                A.field "views" (A.many "MoonTree.View"),
                A.variant_unique,
            },
            A.variant "DomainSlotValue" {
                A.field "slot" "MoonOpen.DomainSlot",
                A.variant_unique,
            },
        },

        A.sum "IndexBase" {
            A.variant "IndexBaseExpr" {
                A.field "base" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "IndexBasePlace" {
                A.field "base" "MoonTree.Place",
                A.field "elem" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "IndexBaseView" {
                A.field "view" "MoonTree.View",
                A.variant_unique,
            },
        },

        A.sum "Place" {
            A.variant "PlaceRef" {
                A.field "h" "MoonTree.PlaceHeader",
                A.field "ref" "MoonBind.ValueRef",
                A.variant_unique,
            },
            A.variant "PlaceDeref" {
                A.field "h" "MoonTree.PlaceHeader",
                A.field "base" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "PlaceDot" {
                A.field "h" "MoonTree.PlaceHeader",
                A.field "base" "MoonTree.Place",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "PlaceField" {
                A.field "h" "MoonTree.PlaceHeader",
                A.field "base" "MoonTree.Place",
                A.field "field" "MoonSem.FieldRef",
                A.variant_unique,
            },
            A.variant "PlaceIndex" {
                A.field "h" "MoonTree.PlaceHeader",
                A.field "base" "MoonTree.IndexBase",
                A.field "index" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "PlaceSlotValue" {
                A.field "h" "MoonTree.PlaceHeader",
                A.field "slot" "MoonOpen.PlaceSlot",
                A.variant_unique,
            },
        },

        A.product "BlockLabel" {
            A.field "name" "string",
            A.unique,
        },

        A.product "BlockParam" {
            A.field "name" "string",
            A.field "ty" "MoonType.Type",
            A.unique,
        },

        A.product "EntryBlockParam" {
            A.field "name" "string",
            A.field "ty" "MoonType.Type",
            A.field "init" "MoonTree.Expr",
            A.unique,
        },

        A.product "JumpArg" {
            A.field "name" "string",
            A.field "value" "MoonTree.Expr",
            A.unique,
        },

        A.sum "FuncContract" {
            A.variant "ContractBounds" {
                A.field "base" "MoonTree.Expr",
                A.field "len" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractWindowBounds" {
                A.field "base" "MoonTree.Expr",
                A.field "base_len" "MoonTree.Expr",
                A.field "start" "MoonTree.Expr",
                A.field "len" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractDisjoint" {
                A.field "a" "MoonTree.Expr",
                A.field "b" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractSameLen" {
                A.field "a" "MoonTree.Expr",
                A.field "b" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractNoAlias" {
                A.field "base" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractReadonly" {
                A.field "base" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractWriteonly" {
                A.field "base" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.sum "ContractFact" {
            A.variant "ContractFactBounds" {
                A.field "base" "MoonBind.Binding",
                A.field "len" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ContractFactWindowBounds" {
                A.field "base" "MoonBind.Binding",
                A.field "base_len" "MoonTree.Expr",
                A.field "start" "MoonTree.Expr",
                A.field "len" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ContractFactDisjoint" {
                A.field "a" "MoonBind.Binding",
                A.field "b" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ContractFactSameLen" {
                A.field "a" "MoonBind.Binding",
                A.field "b" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ContractFactNoAlias" {
                A.field "base" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ContractFactReadonly" {
                A.field "base" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ContractFactWriteonly" {
                A.field "base" "MoonBind.Binding",
                A.variant_unique,
            },
            A.variant "ContractFactRejected" {
                A.field "issue" "MoonTree.TypeIssue",
                A.variant_unique,
            },
        },

        A.product "ContractFactSet" {
            A.field "facts" (A.many "MoonTree.ContractFact"),
            A.unique,
        },

        A.product "EntryControlBlock" {
            A.field "label" "MoonTree.BlockLabel",
            A.field "params" (A.many "MoonTree.EntryBlockParam"),
            A.field "body" (A.many "MoonTree.Stmt"),
            A.unique,
        },

        A.product "ControlBlock" {
            A.field "label" "MoonTree.BlockLabel",
            A.field "params" (A.many "MoonTree.BlockParam"),
            A.field "body" (A.many "MoonTree.Stmt"),
            A.unique,
        },

        A.product "ControlStmtRegion" {
            A.field "region_id" "string",
            A.field "entry" "MoonTree.EntryControlBlock",
            A.field "blocks" (A.many "MoonTree.ControlBlock"),
            A.unique,
        },

        A.product "ControlExprRegion" {
            A.field "region_id" "string",
            A.field "result_ty" "MoonType.Type",
            A.field "entry" "MoonTree.EntryControlBlock",
            A.field "blocks" (A.many "MoonTree.ControlBlock"),
            A.unique,
        },

        A.sum "ControlFact" {
            A.variant "ControlFactEntryBlock" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlFactBlock" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlFactEntryParam" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "index" "number",
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ControlFactBlockParam" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "index" "number",
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ControlFactJump" {
                A.field "region_id" "string",
                A.field "from_label" "MoonTree.BlockLabel",
                A.field "to_label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlFactJumpArg" {
                A.field "region_id" "string",
                A.field "from_label" "MoonTree.BlockLabel",
                A.field "to_label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ControlFactYieldVoid" {
                A.field "region_id" "string",
                A.field "from_label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlFactYieldValue" {
                A.field "region_id" "string",
                A.field "from_label" "MoonTree.BlockLabel",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ControlFactReturn" {
                A.field "region_id" "string",
                A.field "from_label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlFactBackedge" {
                A.field "region_id" "string",
                A.field "from_label" "MoonTree.BlockLabel",
                A.field "to_label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
        },

        A.product "ControlFactSet" {
            A.field "facts" (A.many "MoonTree.ControlFact"),
            A.unique,
        },

        A.sum "ControlReject" {
            A.variant "ControlRejectDuplicateLabel" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlRejectMissingLabel" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlRejectMissingJumpArg" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ControlRejectExtraJumpArg" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ControlRejectDuplicateJumpArg" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ControlRejectJumpType" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.field "expected" "MoonType.Type",
                A.field "actual" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ControlRejectYieldOutsideRegion" {
                A.field "reason" "string",
                A.variant_unique,
            },
            A.variant "ControlRejectYieldType" {
                A.field "region_id" "string",
                A.field "expected" "MoonType.Type",
                A.field "actual" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ControlRejectUnterminatedBlock" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "ControlRejectIrreducible" {
                A.field "region_id" "string",
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "ControlDecision" {
            A.variant "ControlDecisionReducible" {
                A.field "region_id" "string",
                A.field "facts" (A.many "MoonTree.ControlFact"),
                A.variant_unique,
            },
            A.variant "ControlDecisionIrreducible" {
                A.field "region_id" "string",
                A.field "reject" "MoonTree.ControlReject",
                A.variant_unique,
            },
        },

        A.sum "Expr" {
            A.variant "ExprLit" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "value" "MoonCore.Literal",
                A.variant_unique,
            },
            A.variant "ExprRef" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "ref" "MoonBind.ValueRef",
                A.variant_unique,
            },
            A.variant "ExprDot" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "base" "MoonTree.Expr",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ExprUnary" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.UnaryOp",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprBinary" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.BinaryOp",
                A.field "lhs" "MoonTree.Expr",
                A.field "rhs" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprCompare" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.CmpOp",
                A.field "lhs" "MoonTree.Expr",
                A.field "rhs" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprLogic" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.LogicOp",
                A.field "lhs" "MoonTree.Expr",
                A.field "rhs" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprCast" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.SurfaceCastOp",
                A.field "ty" "MoonType.Type",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprMachineCast" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.MachineCastOp",
                A.field "ty" "MoonType.Type",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprIntrinsic" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "op" "MoonCore.Intrinsic",
                A.field "args" (A.many "MoonTree.Expr"),
                A.variant_unique,
            },
            A.variant "ExprAddrOf" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "place" "MoonTree.Place",
                A.variant_unique,
            },
            A.variant "ExprDeref" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprCall" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "target" "MoonSem.CallTarget",
                A.field "args" (A.many "MoonTree.Expr"),
                A.variant_unique,
            },
            A.variant "ExprLen" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprField" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "base" "MoonTree.Expr",
                A.field "field" "MoonSem.FieldRef",
                A.variant_unique,
            },
            A.variant "ExprIndex" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "base" "MoonTree.IndexBase",
                A.field "index" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprAgg" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "ty" "MoonType.Type",
                A.field "fields" (A.many "MoonTree.FieldInit"),
                A.variant_unique,
            },
            A.variant "ExprArray" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "elem_ty" "MoonType.Type",
                A.field "elems" (A.many "MoonTree.Expr"),
                A.variant_unique,
            },
            A.variant "ExprIf" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "cond" "MoonTree.Expr",
                A.field "then_expr" "MoonTree.Expr",
                A.field "else_expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprSelect" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "cond" "MoonTree.Expr",
                A.field "then_expr" "MoonTree.Expr",
                A.field "else_expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprSwitch" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "value" "MoonTree.Expr",
                A.field "arms" (A.many "MoonTree.SwitchExprArm"),
                A.field "default_expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprControl" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "region" "MoonTree.ControlExprRegion",
                A.variant_unique,
            },
            A.variant "ExprBlock" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "stmts" (A.many "MoonTree.Stmt"),
                A.field "result" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprClosure" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "params" (A.many "MoonType.Param"),
                A.field "result" "MoonType.Type",
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "ExprView" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "view" "MoonTree.View",
                A.variant_unique,
            },
            A.variant "ExprLoad" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "ty" "MoonType.Type",
                A.field "addr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ExprSlotValue" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "slot" "MoonOpen.ExprSlot",
                A.variant_unique,
            },
            A.variant "ExprUseExprFrag" {
                A.field "h" "MoonTree.ExprHeader",
                A.field "use_id" "string",
                A.field "frag_name" "string",
                A.field "args" (A.many "MoonTree.Expr"),
                A.field "fills" (A.many "MoonOpen.SlotBinding"),
                A.variant_unique,
            },
        },

        A.sum "Stmt" {
            A.variant "StmtLet" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "binding" "MoonBind.Binding",
                A.field "init" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtVar" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "binding" "MoonBind.Binding",
                A.field "init" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtSet" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "place" "MoonTree.Place",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtExpr" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "expr" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtAssert" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "cond" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtIf" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "cond" "MoonTree.Expr",
                A.field "then_body" (A.many "MoonTree.Stmt"),
                A.field "else_body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "StmtSwitch" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "value" "MoonTree.Expr",
                A.field "arms" (A.many "MoonTree.SwitchStmtArm"),
                A.field "default_body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "StmtJump" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "target" "MoonTree.BlockLabel",
                A.field "args" (A.many "MoonTree.JumpArg"),
                A.variant_unique,
            },
            A.variant "StmtJumpCont" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "slot" "MoonOpen.ContSlot",
                A.field "args" (A.many "MoonTree.JumpArg"),
                A.variant_unique,
            },
            A.variant "StmtYieldVoid" {
                A.field "h" "MoonTree.StmtHeader",
                A.variant_unique,
            },
            A.variant "StmtYieldValue" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtReturnVoid" {
                A.field "h" "MoonTree.StmtHeader",
                A.variant_unique,
            },
            A.variant "StmtReturnValue" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StmtControl" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "region" "MoonTree.ControlStmtRegion",
                A.variant_unique,
            },
            A.variant "StmtUseRegionSlot" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "slot" "MoonOpen.RegionSlot",
                A.variant_unique,
            },
            A.variant "StmtUseRegionFrag" {
                A.field "h" "MoonTree.StmtHeader",
                A.field "use_id" "string",
                A.field "frag_name" "string",
                A.field "args" (A.many "MoonTree.Expr"),
                A.field "fills" (A.many "MoonOpen.SlotBinding"),
                A.field "cont_fills" (A.many "MoonOpen.ContBinding"),
                A.variant_unique,
            },
        },

        A.sum "Func" {
            A.variant "FuncLocal" {
                A.field "name" "string",
                A.field "params" (A.many "MoonType.Param"),
                A.field "result" "MoonType.Type",
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "FuncExport" {
                A.field "name" "string",
                A.field "params" (A.many "MoonType.Param"),
                A.field "result" "MoonType.Type",
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "FuncLocalContract" {
                A.field "name" "string",
                A.field "params" (A.many "MoonType.Param"),
                A.field "result" "MoonType.Type",
                A.field "contracts" (A.many "MoonTree.FuncContract"),
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "FuncExportContract" {
                A.field "name" "string",
                A.field "params" (A.many "MoonType.Param"),
                A.field "result" "MoonType.Type",
                A.field "contracts" (A.many "MoonTree.FuncContract"),
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
            A.variant "FuncOpen" {
                A.field "sym" "MoonCore.FuncSym",
                A.field "visibility" "MoonCore.Visibility",
                A.field "params" (A.many "MoonOpen.OpenParam"),
                A.field "open" "MoonOpen.OpenSet",
                A.field "result" "MoonType.Type",
                A.field "body" (A.many "MoonTree.Stmt"),
                A.variant_unique,
            },
        },

        A.sum "ExternFunc" {
            A.variant "ExternFunc" {
                A.field "name" "string",
                A.field "symbol" "string",
                A.field "params" (A.many "MoonType.Param"),
                A.field "result" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "ExternFuncOpen" {
                A.field "sym" "MoonCore.ExternSym",
                A.field "params" (A.many "MoonOpen.OpenParam"),
                A.field "result" "MoonType.Type",
                A.variant_unique,
            },
        },

        A.sum "ConstItem" {
            A.variant "ConstItem" {
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "ConstItemOpen" {
                A.field "sym" "MoonCore.ConstSym",
                A.field "open" "MoonOpen.OpenSet",
                A.field "ty" "MoonType.Type",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.sum "StaticItem" {
            A.variant "StaticItem" {
                A.field "name" "string",
                A.field "ty" "MoonType.Type",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
            A.variant "StaticItemOpen" {
                A.field "sym" "MoonCore.StaticSym",
                A.field "open" "MoonOpen.OpenSet",
                A.field "ty" "MoonType.Type",
                A.field "value" "MoonTree.Expr",
                A.variant_unique,
            },
        },

        A.product "ImportItem" {
            A.field "path" "MoonCore.Path",
            A.unique,
        },

        A.sum "TypeDecl" {
            A.variant "TypeDeclStruct" {
                A.field "name" "string",
                A.field "fields" (A.many "MoonType.FieldDecl"),
                A.variant_unique,
            },
            A.variant "TypeDeclUnion" {
                A.field "name" "string",
                A.field "fields" (A.many "MoonType.FieldDecl"),
                A.variant_unique,
            },
            A.variant "TypeDeclEnumSugar" {
                A.field "name" "string",
                A.field "variants" (A.many "MoonCore.Name"),
                A.variant_unique,
            },
            A.variant "TypeDeclTaggedUnionSugar" {
                A.field "name" "string",
                A.field "variants" (A.many "MoonType.VariantDecl"),
                A.variant_unique,
            },
            A.variant "TypeDeclOpenStruct" {
                A.field "sym" "MoonCore.TypeSym",
                A.field "fields" (A.many "MoonType.FieldDecl"),
                A.variant_unique,
            },
            A.variant "TypeDeclOpenUnion" {
                A.field "sym" "MoonCore.TypeSym",
                A.field "fields" (A.many "MoonType.FieldDecl"),
                A.variant_unique,
            },
        },

        A.sum "Item" {
            A.variant "ItemFunc" {
                A.field "func" "MoonTree.Func",
                A.variant_unique,
            },
            A.variant "ItemExtern" {
                A.field "func" "MoonTree.ExternFunc",
                A.variant_unique,
            },
            A.variant "ItemConst" {
                A.field "c" "MoonTree.ConstItem",
                A.variant_unique,
            },
            A.variant "ItemStatic" {
                A.field "s" "MoonTree.StaticItem",
                A.variant_unique,
            },
            A.variant "ItemImport" {
                A.field "imp" "MoonTree.ImportItem",
                A.variant_unique,
            },
            A.variant "ItemType" {
                A.field "t" "MoonTree.TypeDecl",
                A.variant_unique,
            },
            A.variant "ItemUseTypeDeclSlot" {
                A.field "slot" "MoonOpen.TypeDeclSlot",
                A.variant_unique,
            },
            A.variant "ItemUseItemsSlot" {
                A.field "slot" "MoonOpen.ItemsSlot",
                A.variant_unique,
            },
            A.variant "ItemUseModule" {
                A.field "use_id" "string",
                A.field "module" "MoonTree.Module",
                A.field "fills" (A.many "MoonOpen.SlotBinding"),
                A.variant_unique,
            },
            A.variant "ItemUseModuleSlot" {
                A.field "use_id" "string",
                A.field "slot" "MoonOpen.ModuleSlot",
                A.field "fills" (A.many "MoonOpen.SlotBinding"),
                A.variant_unique,
            },
        },

        A.sum "ModuleHeader" {
            A.variant "ModuleSurface",
            A.variant "ModuleTyped" {
                A.field "module_name" "string",
                A.variant_unique,
            },
            A.variant "ModuleOpen" {
                A.field "name" "MoonOpen.ModuleNameFacet",
                A.field "open" "MoonOpen.OpenSet",
                A.variant_unique,
            },
            A.variant "ModuleSem" {
                A.field "module_name" "string",
                A.variant_unique,
            },
            A.variant "ModuleCode" {
                A.field "module_name" "string",
                A.variant_unique,
            },
        },

        A.product "Module" {
            A.field "h" "MoonTree.ModuleHeader",
            A.field "items" (A.many "MoonTree.Item"),
            A.unique,
        },

        A.sum "TypeIssue" {
            A.variant "TypeIssueUnresolvedValue" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "TypeIssueUnresolvedPath" {
                A.field "path" "MoonCore.Path",
                A.variant_unique,
            },
            A.variant "TypeIssueExpected" {
                A.field "site" "string",
                A.field "expected" "MoonType.Type",
                A.field "actual" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueArgCount" {
                A.field "site" "string",
                A.field "expected" "number",
                A.field "actual" "number",
                A.variant_unique,
            },
            A.variant "TypeIssueNotCallable" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueNotIndexable" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueNotPointer" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueInvalidUnary" {
                A.field "op" "string",
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueInvalidBinary" {
                A.field "op" "string",
                A.field "lhs" "MoonType.Type",
                A.field "rhs" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueInvalidCompare" {
                A.field "op" "string",
                A.field "lhs" "MoonType.Type",
                A.field "rhs" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueInvalidLogic" {
                A.field "lhs" "MoonType.Type",
                A.field "rhs" "MoonType.Type",
                A.variant_unique,
            },
            A.variant "TypeIssueMissingJumpTarget" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.variant_unique,
            },
            A.variant "TypeIssueMissingJumpArg" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "TypeIssueExtraJumpArg" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "TypeIssueDuplicateJumpArg" {
                A.field "region_id" "string",
                A.field "label" "MoonTree.BlockLabel",
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "TypeIssueUnexpectedYield" {
                A.field "site" "string",
                A.variant_unique,
            },
            A.variant "TypeIssueInvalidControl" {
                A.field "region_id" "string",
                A.field "reject" "MoonTree.ControlReject",
                A.variant_unique,
            },
        },

        A.sum "TypeYieldMode" {
            A.variant "TypeYieldNone",
            A.variant "TypeYieldVoid",
            A.variant "TypeYieldValue" {
                A.field "ty" "MoonType.Type",
                A.variant_unique,
            },
        },

        A.product "TypeCheckEnv" {
            A.field "env" "MoonBind.Env",
            A.field "return_ty" "MoonType.Type",
            A.field "yield" "MoonTree.TypeYieldMode",
            A.unique,
        },

        A.sum "TypeViewResult" {
            A.variant "TypeViewResult" {
                A.field "view" "MoonTree.View",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeIndexBaseResult" {
            A.variant "TypeIndexBaseResult" {
                A.field "base" "MoonTree.IndexBase",
                A.field "elem" "MoonType.Type",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeControlStmtRegionResult" {
            A.variant "TypeControlStmtRegionResult" {
                A.field "region" "MoonTree.ControlStmtRegion",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeControlExprRegionResult" {
            A.variant "TypeControlExprRegionResult" {
                A.field "region" "MoonTree.ControlExprRegion",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeExprResult" {
            A.variant "TypeExprResult" {
                A.field "expr" "MoonTree.Expr",
                A.field "ty" "MoonType.Type",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypePlaceResult" {
            A.variant "TypePlaceResult" {
                A.field "place" "MoonTree.Place",
                A.field "ty" "MoonType.Type",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeStmtResult" {
            A.variant "TypeStmtResult" {
                A.field "env" "MoonTree.TypeCheckEnv",
                A.field "stmts" (A.many "MoonTree.Stmt"),
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeFuncResult" {
            A.variant "TypeFuncResult" {
                A.field "func" "MoonTree.Func",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeItemResult" {
            A.variant "TypeItemResult" {
                A.field "items" (A.many "MoonTree.Item"),
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TypeModuleResult" {
            A.variant "TypeModuleResult" {
                A.field "module" "MoonTree.Module",
                A.field "issues" (A.many "MoonTree.TypeIssue"),
                A.variant_unique,
            },
        },

        A.sum "TreeBackLocal" {
            A.variant "TreeBackScalarLocal" {
                A.field "binding" "MoonBind.Binding",
                A.field "value" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "TreeBackViewLocal" {
                A.field "binding" "MoonBind.Binding",
                A.field "data" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "TreeBackStridedViewLocal" {
                A.field "binding" "MoonBind.Binding",
                A.field "data" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.field "stride" "MoonBack.BackValId",
                A.variant_unique,
            },
        },

        A.sum "TreeBackReturn" {
            A.variant "TreeBackReturnScalar",
            A.variant "TreeBackReturnView" {
                A.field "out" "MoonBack.BackValId",
                A.variant_unique,
            },
        },

        A.product "TreeBackEnv" {
            A.field "locals" (A.many "MoonTree.TreeBackLocal"),
            A.field "next_value" "number",
            A.field "next_block" "number",
            A.field "ret" "MoonTree.TreeBackReturn",
            A.unique,
        },

        A.sum "TreeBackExprResult" {
            A.variant "TreeBackExprValue" {
                A.field "env" "MoonTree.TreeBackEnv",
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "value" "MoonBack.BackValId",
                A.field "ty" "MoonBack.BackScalar",
                A.variant_unique,
            },
            A.variant "TreeBackExprView" {
                A.field "env" "MoonTree.TreeBackEnv",
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "data" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "TreeBackExprStridedView" {
                A.field "env" "MoonTree.TreeBackEnv",
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "data" "MoonBack.BackValId",
                A.field "len" "MoonBack.BackValId",
                A.field "stride" "MoonBack.BackValId",
                A.variant_unique,
            },
            A.variant "TreeBackExprUnsupported" {
                A.field "env" "MoonTree.TreeBackEnv",
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "TreeBackStmtResult" {
            A.variant "TreeBackStmtResult" {
                A.field "env" "MoonTree.TreeBackEnv",
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.field "flow" "MoonBack.BackFlow",
                A.variant_unique,
            },
        },

        A.sum "TreeBackFuncResult" {
            A.variant "TreeBackFuncResult" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
        },

        A.sum "TreeBackItemResult" {
            A.variant "TreeBackItemResult" {
                A.field "cmds" (A.many "MoonBack.Cmd"),
                A.variant_unique,
            },
        },
    }
end
