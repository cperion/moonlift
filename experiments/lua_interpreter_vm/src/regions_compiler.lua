-- Lua Interpreter VM — Public source-byte compiler entry regions

local moon = require("moonlift")
local host = require("moonlift.host")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")
local parser = require("experiments.lua_interpreter_vm.src.regions_parser")
local semantic = require("experiments.lua_interpreter_vm.src.regions_semantic")
local lower = require("experiments.lua_interpreter_vm.src.regions_lower")

local OFF = {
    PARSE_NODES = 0,
    PARSE_FUNCTIONS = 65536,
    PARSE_CHILDREN = 81920,
    PARSE_FRAMES = 86016,
    EXPR_OPS = 118784,
    EXPR_VALS = 126976,
    HIR_FUNCTIONS = 135168,
    HIR_BLOCKS = 151552,
    HIR_STMTS = 167936,
    HIR_EXPRS = 200704,
    SCOPES = 233472,
    SYMBOLS = 249856,
    CAPTURES = 282624,
    NAME_USES = 299008,
    SEMANTIC_FRAMES = 323584,
    LOWER_FRAMES = 348160,
    LOWER_SCOPES = 372736,
    PATCHES = 389120,
    EXPR_SLOTS = 413696,
    CONSTANTS = 430080,
    UPVALS = 434176,
    CHILDREN = 438272,
    STRING_ARENA = 438784,
    REQUIRED = 438784,
}

local CAP = {
    PARSE_NODES = 256,
    PARSE_FUNCTIONS = 64,
    PARSE_CHILDREN = 256,
    PARSE_FRAMES = 128,
    EXPR_OPS = 128,
    EXPR_VALS = 128,
    HIR_FUNCTIONS = 64,
    HIR_BLOCKS = 128,
    HIR_STMTS = 256,
    HIR_EXPRS = 256,
    SCOPES = 128,
    SYMBOLS = 256,
    CAPTURES = 128,
    NAME_USES = 256,
    SEMANTIC_FRAMES = 128,
    LOWER_FRAMES = 128,
    LOWER_SCOPES = 128,
    PATCHES = 256,
    EXPR_SLOTS = 128,
    CONSTANTS = 256,
    UPVALS = 16,
    CHILDREN = 64,
}

local V = {
    parse_source_to_products = parser.parse_source_to_products,
    verify_parse_products = parser.verify_parse_products,
    build_hir_from_parse = semantic.build_hir_from_parse,
    verify_hir = semantic.verify_hir,
    lower_hir_to_proto = lower.lower_hir_to_proto,
}
for k, v in pairs(pconst.SourcePhase) do V["SOURCE_" .. k] = moon.int(v) end
for k, v in pairs(OFF) do V["OFF_" .. k] = moon.int(v) end
for k, v in pairs(CAP) do V["CAP_" .. k] = moon.int(v) end

local compile_lua_source_into = host.region(V) [[
region compile_lua_source_into(
    cu: ptr(CompileUnit),
    builder: ptr(FuncBuilder),
    out_proto: ptr(Proto),
    bytes: ptr(u8),
    len: index,
    code: ptr(Instr),
    code_cap: index,
    locals: ptr(CompileLocal),
    locals_cap: index,
    workspace: ptr(u8),
    workspace_cap: index;

    ok(proto: ptr(Proto)) |
    syntax_error(err: CompileError) |
    semantic_error(err: CompileError) |
    limit_error(err: CompileError) |
    oom)
entry start()
    if workspace == nil then jump out_of_mem() end
    if workspace_cap < as(index, @{OFF_REQUIRED}) then jump out_of_mem() end

    cu.phase = @{SOURCE_INIT}
    cu.status = 0
    cu.reserved = 0
    cu.error = { code = 0, pos = { offset = 0, line = 1, col = 1 }, token = 0 }
    cu.arena = { base = workspace, pos = as(index, @{OFF_STRING_ARENA}), cap = workspace_cap, overflowed = 0 }
    cu.root = builder
    cu.current = builder
    cu.lexer.src = { bytes = bytes, len = len, source_name = nil }
    cu.lexer.pos = 0
    cu.lexer.line = 1
    cu.lexer.col = 1
    cu.lexer.current = { kind = 0, start = 0, len = 0, line = 1, aux = 0, bits = 0 }
    cu.lexer.lookahead = { kind = 0, start = 0, len = 0, line = 1, aux = 0, bits = 0 }
    cu.lexer.has_lookahead = 0
    cu.root_parse_function = 0
    cu.root_hir_function = 0

    cu.parse_nodes = { data = as(ptr(ParseNode), workspace + as(index, @{OFF_PARSE_NODES})), len = 0, cap = as(index, @{CAP_PARSE_NODES}) }
    cu.parse_functions = { data = as(ptr(ParseFunction), workspace + as(index, @{OFF_PARSE_FUNCTIONS})), len = 0, cap = as(index, @{CAP_PARSE_FUNCTIONS}) }
    cu.parse_children = { data = as(ptr(index), workspace + as(index, @{OFF_PARSE_CHILDREN})), len = 0, cap = as(index, @{CAP_PARSE_CHILDREN}) }
    cu.parse_frames = { data = as(ptr(ParseFrame), workspace + as(index, @{OFF_PARSE_FRAMES})), len = 0, cap = as(index, @{CAP_PARSE_FRAMES}) }
    cu.expr_ops = { data = as(ptr(ExprOpEntry), workspace + as(index, @{OFF_EXPR_OPS})), len = 0, cap = as(index, @{CAP_EXPR_OPS}) }
    cu.expr_vals = { data = as(ptr(ExprValEntry), workspace + as(index, @{OFF_EXPR_VALS})), len = 0, cap = as(index, @{CAP_EXPR_VALS}) }

    cu.hir_functions = { data = as(ptr(HirFunction), workspace + as(index, @{OFF_HIR_FUNCTIONS})), len = 0, cap = as(index, @{CAP_HIR_FUNCTIONS}) }
    cu.hir_blocks = { data = as(ptr(HirBlock), workspace + as(index, @{OFF_HIR_BLOCKS})), len = 0, cap = as(index, @{CAP_HIR_BLOCKS}) }
    cu.hir_stmts = { data = as(ptr(HirStmt), workspace + as(index, @{OFF_HIR_STMTS})), len = 0, cap = as(index, @{CAP_HIR_STMTS}) }
    cu.hir_exprs = { data = as(ptr(HirExpr), workspace + as(index, @{OFF_HIR_EXPRS})), len = 0, cap = as(index, @{CAP_HIR_EXPRS}) }
    cu.scopes = { data = as(ptr(ScopeRec), workspace + as(index, @{OFF_SCOPES})), len = 0, cap = as(index, @{CAP_SCOPES}) }
    cu.symbols = { data = as(ptr(SymbolRec), workspace + as(index, @{OFF_SYMBOLS})), len = 0, cap = as(index, @{CAP_SYMBOLS}) }
    cu.captures = { data = as(ptr(CaptureRec), workspace + as(index, @{OFF_CAPTURES})), len = 0, cap = as(index, @{CAP_CAPTURES}) }
    cu.name_uses = { data = as(ptr(NameUse), workspace + as(index, @{OFF_NAME_USES})), len = 0, cap = as(index, @{CAP_NAME_USES}) }
    cu.semantic_frames = { data = as(ptr(SemanticFrame), workspace + as(index, @{OFF_SEMANTIC_FRAMES})), len = 0, cap = as(index, @{CAP_SEMANTIC_FRAMES}) }

    cu.lower_frames = { data = as(ptr(LowerFrame), workspace + as(index, @{OFF_LOWER_FRAMES})), len = 0, cap = as(index, @{CAP_LOWER_FRAMES}) }
    cu.lower_scopes = { data = as(ptr(LowerScope), workspace + as(index, @{OFF_LOWER_SCOPES})), len = 0, cap = as(index, @{CAP_LOWER_SCOPES}) }
    cu.patches = { data = as(ptr(PatchRec), workspace + as(index, @{OFF_PATCHES})), len = 0, cap = as(index, @{CAP_PATCHES}) }
    cu.expr_slots = { data = as(ptr(ExprSlot), workspace + as(index, @{OFF_EXPR_SLOTS})), len = 0, cap = as(index, @{CAP_EXPR_SLOTS}) }

    cu.parse_mark = 0
    cu.semantic_mark = 0
    cu.lower_mark = 0
    cu.durable_mark = 0

    builder.parent = nil
    builder.out_proto = out_proto
    builder.code = { data = code, len = 0, cap = code_cap }
    builder.constants = { data = as(ptr(Value), workspace + as(index, @{OFF_CONSTANTS})), len = 0, cap = as(index, @{CAP_CONSTANTS}) }
    builder.children = { data = as(ptr(ptr(Proto)), workspace + as(index, @{OFF_CHILDREN})), len = 0, cap = as(index, @{CAP_CHILDREN}) }
    builder.locvars = { data = nil, len = 0, cap = 0 }
    builder.upvals = { data = as(ptr(UpValDesc), workspace + as(index, @{OFF_UPVALS})), len = 0, cap = as(index, @{CAP_UPVALS}) }
    builder.locals = locals
    builder.locals_len = 0
    builder.locals_cap = locals_cap
    builder.labels = nil
    builder.labels_len = 0
    builder.labels_cap = 0
    builder.gotos = nil
    builder.gotos_len = 0
    builder.gotos_cap = 0
    builder.firstlocal = 0
    builder.nactvar = 0
    builder.freereg = 0
    builder.maxstack = 1
    builder.pc = 0
    builder.lasttarget = 0
    builder.numparams = 0
    builder.flag = 0

    emit @{parse_source_to_products}(cu;
        ok = parsed,
        syntax_error = syntax_bad,
        limit_error = limit_bad,
        oom = out_of_mem)
end
block parsed()
    emit @{verify_parse_products}(cu;
        ok = parse_verified,
        syntax_error = syntax_bad,
        limit_error = limit_bad)
end
block parse_verified()
    emit @{build_hir_from_parse}(cu;
        ok = hir_built,
        semantic_error = sem_bad,
        limit_error = limit_bad,
        oom = out_of_mem)
end
block hir_built()
    emit @{verify_hir}(cu;
        ok = hir_verified,
        semantic_error = sem_bad,
        limit_error = limit_bad)
end
block hir_verified()
    emit @{lower_hir_to_proto}(cu;
        ok = compiled,
        semantic_error = sem_bad,
        limit_error = limit_bad,
        oom = out_of_mem)
end
block compiled(proto: ptr(Proto))
    jump ok(proto = proto)
end
block syntax_bad(err: CompileError)
    jump syntax_error(err = err)
end
block sem_bad(err: CompileError)
    jump semantic_error(err = err)
end
block limit_bad(err: CompileError)
    jump limit_error(err = err)
end
block out_of_mem()
    jump oom()
end
end
]]

return {
    compile_lua_source_into = compile_lua_source_into,
}
