-- MOM Precompiled Manifest
-- Ordered source list for building precompiled native MOM object

local M = {}

M.schema_sources = {
    "lua/moonlift/mom/schema/MoonCore.mlua",
    "lua/moonlift/mom/schema/MoonBack.mlua",
    "lua/moonlift/mom/schema/MoonSource.mlua",
    "lua/moonlift/mom/schema/MoonParse.mlua",
    "lua/moonlift/mom/schema/MoonLink.mlua",
    "lua/moonlift/mom/schema/MoonCyclic.mlua",
    "lua/moonlift/mom/schema/MoonDasm.mlua",
    "lua/moonlift/mom/schema/MoonEditor.mlua",
    "lua/moonlift/mom/schema/MoonEditorLspRpc.mlua",
    "lua/moonlift/mom/schema/MoonLsp.mlua",
    "lua/moonlift/mom/schema/MoonMlua.mlua",
    "lua/moonlift/mom/schema/MoonRpc.mlua",
}

M.compiler_sources = {
    -- Phase 0: runtime and data structures
    "lua/moonlift/mom/runtime/builders.mlua",
    "lua/moonlift/mom/runtime/sets.mlua",

    -- Phase 1: parser (native compiler frontend) - provides MomTreeOut.
    "lua/moonlift/mom/parser/document_scan.mlua",
    "lua/moonlift/mom/parser/native_lexer.mlua",
    "lua/moonlift/mom/parser/native_core.mlua",
    "lua/moonlift/mom/parser/native_tree.mlua",

    -- Phase 2: backend infrastructure
    "lua/moonlift/mom/back/ids.mlua",
    "lua/moonlift/mom/back/ops.mlua",
    "lua/moonlift/mom/back/env.mlua",
    "lua/moonlift/mom/back/lower_ctx.mlua",
    "lua/moonlift/mom/back/cmd.mlua",
    "lua/moonlift/mom/back/control.mlua",
    "lua/moonlift/mom/back/validate.mlua",
    "lua/moonlift/mom/back/back_abi.mlua",
    "lua/moonlift/mom/back/expr_lower.mlua",
    "lua/moonlift/mom/back/address.mlua",
    "lua/moonlift/mom/back/stmt_lower.mlua",

    -- Phase 3: type system
    -- Keep one typecheck implementation in the product object.  The split
    -- type_expr/type_stmt/type_place/type_module files remain focused test
    -- fixtures until they replace the monolithic checker completely.
    "lua/moonlift/mom/typecheck/type_check.mlua",
    "lua/moonlift/mom/typecheck/type_control.mlua",

    -- Phase 4: layout resolution
    "lua/moonlift/mom/layout/layout_env.mlua",
    "lua/moonlift/mom/layout/layout_field.mlua",
    "lua/moonlift/mom/layout/layout_resolve.mlua",

    -- Phase 5: driver / wire / backend
    "lua/moonlift/mom/driver/wire.mlua",
    "lua/moonlift/mom/driver/lower_wire.mlua",
    "lua/moonlift/mom/driver/backend_ffi.mlua",
    "lua/moonlift/mom/driver/compile_module.mlua",
    "lua/moonlift/mom/driver/compile_source.mlua",
    "lua/moonlift/mom/driver/lua_api.mlua",
    "lua/moonlift/mom/driver/native_entry.mlua",

    -- Phase 6: vectorization (skeletons)
    "lua/moonlift/mom/vec/vec_facts.mlua",
    "lua/moonlift/mom/vec/vec_decide.mlua",
    "lua/moonlift/mom/vec/vec_lower.mlua",
    "lua/moonlift/mom/vec/vec_plan.mlua",
}

return M
