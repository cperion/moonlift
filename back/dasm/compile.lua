-- compile.lua — DynASM backend: BackProgram → machine code

local ffi    = require("ffi")
local encode = require("back.dasm.encode_x64")
local regalloc = require("back.dasm.regalloc")
local isel   = require("back.dasm.isel_x64")
local bit    = require("bit")

-- ── libdasm + executable memory ───────────────────────────────────────

local libdasm
ffi.cdef([[
    typedef struct dasm_State dasm_State;
    void dasm_init(dasm_State **Dst, int maxsection);
    void dasm_free(dasm_State **Dst);
    void dasm_setupglobal(dasm_State **Dst, void **gl, unsigned int maxgl);
    void dasm_growpc(dasm_State **Dst, unsigned int maxpc);
    void dasm_setup(dasm_State **Dst, const void *actionlist);
    void dasm_put_array(dasm_State **Dst, int start, const int *args, int nargs);
    int  dasm_link(dasm_State **Dst, size_t *szp);
    int  dasm_encode(dasm_State **Dst, void *buffer);
    void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
    int   munmap(void *addr, size_t length);
]])

local PROT_RWX = 7   -- PROT_READ | PROT_WRITE | PROT_EXEC
local MAP_ANON = 0x22 -- MAP_PRIVATE | MAP_ANONYMOUS

local function load_dasm()
    if libdasm then return libdasm end
    local ok, lib = pcall(ffi.load, "./back/libdasm.so")
    if not ok then ok, lib = pcall(ffi.load, "back/libdasm.so") end
    if not ok then error("cannot load libdasm.so: " .. tostring(lib)) end
    libdasm = lib
    return libdasm
end

local function alloc_exec(n)
    local sz = bit.band((n + 4095), bit.bnot(4095))
    local p = ffi.C.mmap(nil, sz, PROT_RWX, MAP_ANON, -1, 0)
    if p == ffi.cast("void *", -1) then error("mmap failed") end
    return p, sz
end

-- ── helpers ───────────────────────────────────────────────────────────

local function idkey(v)
    return type(v) == "string" and v or (v and v.text) or nil
end

-- ── data objects ──────────────────────────────────────────────────────

local function build_data(prog)
    local ds = {}
    for _, cmd in ipairs(prog.cmds) do
        local k = cmd.kind
        if k == "CmdDeclareData" then
            local key = idkey(cmd.data)
            local buf = ffi.new("uint8_t[?]", cmd.size)
            ffi.fill(buf, cmd.size, 0)
            ds[key] = {buf = buf}
        elseif k == "CmdDataInitZero" then
            local d = ds[idkey(cmd.data)]
            if d then ffi.fill(d.buf + cmd.offset, cmd.size, 0) end
        elseif k == "CmdDataInit" then
            local d = ds[idkey(cmd.data)]
            if d and cmd.value then
                local v = cmd.value
                if v.kind == "BackLitInt" then
                    ffi.copy(d.buf + cmd.offset, ffi.new("int64_t[1]", math.floor(tonumber(v.raw) or 0)), 8)
                elseif v.kind == "BackLitFloat" then
                    ffi.copy(d.buf + cmd.offset, ffi.new("double[1]", tonumber(v.raw) or 0), 8)
                elseif v.kind == "BackLitBool" then
                    d.buf[cmd.offset] = v.value and 1 or 0
                end
            end
        end
    end
    return ds
end

-- ── compile ───────────────────────────────────────────────────────────

local function compile(program)
    local lib = load_dasm()
    encode.init()

    -- collect declarations
    local sigs, funcs, externs = {}, {}, {}
    local body = nil
    for _, cmd in ipairs(program.cmds) do
        local k = cmd.kind
        if k == "CmdCreateSig" then
            sigs[idkey(cmd.sig)] = {params = cmd.params or {}, results = cmd.results or {}}
        elseif k == "CmdDeclareFunc" then
            funcs[idkey(cmd.func)] = {sig = idkey(cmd.sig)}
        elseif k == "CmdDeclareExtern" then
            externs[idkey(cmd.func)] = {symbol = cmd.symbol, sig = idkey(cmd.sig)}
        elseif k == "CmdBeginFunc" then
            body = {}
        elseif k == "CmdFinishFunc" then
            local fk = idkey(cmd.func)
            if funcs[fk] then funcs[fk].body = body end
            body = nil
        elseif body and k ~= "CmdCreateSig" and k ~= "CmdDeclareData"
                and k ~= "CmdDataInitZero" and k ~= "CmdDataInit"
                and k ~= "CmdDeclareFunc" and k ~= "CmdDeclareExtern"
                and k ~= "CmdFinalizeModule" and k ~= "CmdTargetModel"
                and k ~= "CmdAliasFact" and k ~= "CmdDataAddr"
                and k ~= "CmdFuncAddr" and k ~= "CmdExternAddr" then
            body[#body + 1] = cmd
        end
    end

    local datas = build_data(program)

    -- sorted keys for deterministic label ordering
    local fkeys = {}; for fk in pairs(funcs) do fkeys[#fkeys+1] = fk end; table.sort(fkeys)
    local ekeys = {}; for ek in pairs(externs) do ekeys[#ekeys+1] = ek end; table.sort(ekeys)
    local dkeys = {}; for dk in pairs(datas) do dkeys[#dkeys+1] = dk end; table.sort(dkeys)

    local nglobals = #fkeys + #ekeys + #dkeys
    local glob_order = {}  -- 1-indexed
    local gi = 1
    for _, fk in ipairs(fkeys) do glob_order[gi] = {kind="func", key=fk}; gi=gi+1 end
    for _, ek in ipairs(ekeys) do glob_order[gi] = {kind="extern", key=ek}; gi=gi+1 end
    for _, dk in ipairs(dkeys) do glob_order[gi] = {kind="data", key=dk}; gi=gi+1 end

    isel.func_labels = {}; for _, fk in ipairs(fkeys) do isel.func_labels[fk] = "->" .. fk end
    isel.extern_labels = {}; for _, ek in ipairs(ekeys) do isel.extern_labels[ek] = "->" .. ek end

    -- ── compile each function ────────────────────────────────────────

    for _, fk in ipairs(fkeys) do
        local fd = funcs[fk]
        local bd = fd.body
        if not bd then goto continue end

        local regmap, spilled, ucs, sa = regalloc.allocate(bd)
        isel.set_frame(ucs, sa)

        isel.block_labels = {}
        isel.stack_slots = {}
        isel.next_slot = 0

        -- pass 1: labels and slots
        local lc = 1
        local function nlab() local n = lc; lc = (n % 9) + 1; return n end
        for _, cmd in ipairs(bd) do
            if cmd.kind == "CmdCreateBlock" then
                local k = idkey(cmd.block)
                if not isel.block_labels[k] then isel.block_labels[k] = nlab() end
            elseif cmd.kind == "CmdCreateStackSlot" then
                isel.alloc_slot(cmd.slot, cmd.size, cmd.align)
            end
        end

        encode.label_def("->" .. fk)
        isel.emit_prologue()

        for _, cmd in ipairs(bd) do
            local k = cmd.kind
            if k == "CmdSwitchToBlock" then
                local bl = isel.block_labels[idkey(cmd.block)]
                if bl then encode.label_def(tostring(bl)) end
            end
            if k == "CmdBindEntryParams" then
                local pr = {7,6,2,1,8,9}
                for i, vid in ipairs(cmd.values or {}) do
                    if i <= #pr then regmap[idkey(vid)] = pr[i] end
                end
            end
            if k == "CmdReturnVoid" then isel.emit_epilogue(); goto next_cmd end
            if k == "CmdCreateBlock" or k == "CmdSwitchToBlock"
                or k == "CmdSealBlock" or k == "CmdBindEntryParams"
                or k == "CmdAppendBlockParam" or k == "CmdCreateStackSlot"
                or k == "CmdAliasFact" or k == "CmdTargetModel" then
                goto next_cmd
            end
            local ok, err = pcall(isel.lower_cmd, cmd, regmap)
            if not ok then error("compile.lua: in '" .. fk .. "': " .. tostring(err), 0) end
            ::next_cmd::
        end
        ::continue::
    end

    -- ── build action list ────────────────────────────────────────────

    encode.flush()
    local fragments = encode.take_fragments()
    local parts = {}
    for _, f in ipairs(fragments) do parts[#parts+1] = f.bytes end
    local alist = table.concat(parts)
    if #alist == 0 then error("compile.lua: empty action list") end

    local albuf = ffi.new("uint8_t[?]", #alist)
    ffi.copy(albuf, alist, #alist)

    -- ── dasm state ───────────────────────────────────────────────────

    local Dst = ffi.new("dasm_State*[1]")
    lib.dasm_init(Dst, 1)
    local globals = ffi.new("void*[?]", nglobals)
    for i, entry in ipairs(glob_order) do
        if entry.kind == "data" then
            local d = datas[entry.key]
            if d then globals[i - 1] = d.buf end
        end
    end
    lib.dasm_setupglobal(Dst, globals, nglobals)
    lib.dasm_growpc(Dst, 0)
    lib.dasm_setup(Dst, albuf)

    -- ── feed fragments ───────────────────────────────────────────────

    for _, f in ipairs(fragments) do
        local n = #f.args
        if n > 0 then
            local ab = ffi.new("int[?]", n)
            for i = 1, n do ab[i-1] = math.floor(tonumber(f.args[i]) or 0) end
            lib.dasm_put_array(Dst, f.offset, ab, n)
        else
            lib.dasm_put_array(Dst, f.offset, nil, 0)
        end
    end

    -- ── link + encode into executable memory ────────────────────────

    local sz = ffi.new("size_t[1]")
    local lrc = lib.dasm_link(Dst, sz)
    if lrc ~= 0 then error("dasm_link failed 0x" .. bit.tohex(lrc)) end

    local code_size = tonumber(sz[0])
    local exec_ptr, exec_sz = alloc_exec(code_size)
    local erc = lib.dasm_encode(Dst, exec_ptr)
    if erc ~= 0 then error("dasm_encode failed 0x" .. bit.tohex(erc)) end

    -- ── extract function pointers ────────────────────────────────────

    local fptrs = {}
    for i, entry in ipairs(glob_order) do
        if entry.kind == "func" then
            local ptr = globals[i - 1]
            if ptr ~= nil then fptrs[entry.key] = ptr end
        end
    end

    -- ── artifact ─────────────────────────────────────────────────────

    return {
        getpointer = function(_, fid)
            local k = idkey(fid)
            local p = fptrs[k]
            if not p then error("compile: no code for '" .. k .. "'") end
            return ffi.cast("const void *", p)
        end,
        free = function()
            lib.dasm_free(Dst)
            ffi.C.munmap(exec_ptr, exec_sz)
        end,
    }
end

return { compile = compile }
