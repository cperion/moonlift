-- Lua Interpreter VM — Public source-byte compiler entry regions

local host = require("moonlift.host")

local compile_lua_source_into = host.region [[
region compile_lua_source_into(
    cu: ptr(CompileUnit),
    builder: ptr(FuncBuilder),
    out_proto: ptr(Proto),
    bytes: ptr(u8),
    len: index,
    code: ptr(Instr),
    code_cap: index,
    locals: ptr(CompileLocal),
    locals_cap: index;

    ok: cont(proto: ptr(Proto)),
    syntax_error: cont(err: CompileError),
    semantic_error: cont(err: CompileError),
    limit_error: cont(err: CompileError),
    oom: cont())
entry start()
    cu.arena = nil
    cu.root = builder
    cu.current = builder
    cu.lexer.src = { bytes = bytes, len = len, source_name = nil }
    cu.lexer.pos = 0
    cu.lexer.line = 1
    cu.lexer.col = 1
    cu.lexer.has_lookahead = 0

    builder.parent = nil
    builder.out_proto = out_proto
    builder.code = { data = code, len = 0, cap = code_cap }
    builder.constants = { data = nil, len = 0, cap = 0 }
    builder.children = { data = nil, len = 0, cap = 0 }
    builder.locvars = { data = nil, len = 0, cap = 0 }
    builder.upvals = { data = nil, len = 0, cap = 0 }
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
    builder.maxstack = 0
    builder.pc = 0
    builder.lasttarget = 0
    builder.numparams = 0
    builder.flag = 0

    emit compile_prepared_unit(cu;
        ok = compiled,
        syntax_error = syntax_bad,
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
