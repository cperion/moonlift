-- isel_x64.lua — instruction selection: BackCmd → x64 assembly text
--
-- Uses encode_x64.lua which delegates to dasm_x86.lua's template engine.
-- Operands are assembly text strings parsed by dasm_x86's parseoperand.

local encode = require("back.dasm.encode_x64")
local abi    = require("back.dasm.abi_sysv")

local isel = {}

-- ── helpers ───────────────────────────────────────────────────────────

local function idkey(v)
    return type(v) == "string" and v or (v and v.text) or nil
end

local function regof(v, m)
    local r = m[idkey(v)]
    if r == nil then error("isel: no reg for '" .. tostring(idkey(v)) .. "'") end
    return r
end

local function mr(r, sz) return encode.reg(r, sz or "q") end  -- reg name
local function mi(v)   return encode.imm(v) end               -- immediate text
local function ml(n)   return encode.label_ref(n) end          -- label ref text

local function emit(op, ...) encode.emit(op, ...) end
local function rr(op, d, s, sz) emit(op, mr(d, sz), mr(s, sz)) end
local function ri(op, d, v, sz) emit(op, mr(d, sz), mi(v)) end

-- ── dispatch ──────────────────────────────────────────────────────────

function isel.lower_cmd(cmd, regmap)
    local k = cmd.kind
    if     k == "CmdConst"      then isel.const_(cmd, regmap)
    elseif k == "CmdAlias"      then isel.alias_(cmd, regmap)
    elseif k == "CmdUnary"      then isel.unary_(cmd, regmap)
    elseif k == "CmdIntBinary"  then isel.intbin_(cmd, regmap)
    elseif k == "CmdBitBinary"  then isel.bitbin_(cmd, regmap)
    elseif k == "CmdBitNot"     then isel.bitnot_(cmd, regmap)
    elseif k == "CmdShift"      then isel.shift_(cmd, regmap)
    elseif k == "CmdRotate"     then isel.rotate_(cmd, regmap)
    elseif k == "CmdCompare"    then isel.compare_(cmd, regmap)
    elseif k == "CmdCast"       then isel.cast_(cmd, regmap)
    elseif k == "CmdIntrinsic"  then isel.intrinsic_(cmd, regmap)
    elseif k == "CmdLoadInfo"   then isel.load_(cmd, regmap)
    elseif k == "CmdStoreInfo"  then isel.store_(cmd, regmap)
    elseif k == "CmdPtrOffset"  then isel.ptroff_(cmd, regmap)
    elseif k == "CmdSelect"     then isel.select_(cmd, regmap)
    elseif k == "CmdJump"       then isel.jump_(cmd, regmap)
    elseif k == "CmdBrIf"       then isel.brif_(cmd, regmap)
    elseif k == "CmdSwitchInt"  then isel.switch_(cmd, regmap)
    elseif k == "CmdCall"       then isel.call_(cmd, regmap)
    elseif k == "CmdReturnValue" then isel.retval_(cmd, regmap)
    elseif k == "CmdTrap"       then emit("ud2_0")
    elseif k == "CmdStackAddr"  then isel.stackaddr_(cmd, regmap)
    elseif k == "CmdFuncAddr"   then isel.funcaddr_(cmd, regmap)
    elseif k == "CmdExternAddr" then isel.externaddr_(cmd, regmap)
    elseif k == "CmdMemcpy"     then isel.memcpy_(cmd, regmap)
    elseif k == "CmdMemset"     then isel.memset_(cmd, regmap)
    end
end

-- ── alias ─────────────────────────────────────────────────────────────

function isel.alias_(cmd, m) m[idkey(cmd.dst)] = m[idkey(cmd.src)] end

-- ── constants ─────────────────────────────────────────────────────────

local function opsize(sk)
    if sk == "BackBool" or sk == "BackI8" or sk == "BackU8" then return "b"
    elseif sk == "BackI16" or sk == "BackU16" then return "w"
    elseif sk == "BackI32" or sk == "BackU32" or sk == "BackF32" then return "d"
    else return "q" end
end

function isel.const_(cmd, m)
    local d = regof(cmd.dst, m)
    local sz = opsize(cmd.ty and cmd.ty.kind or "BackI64")
    local v = cmd.value
    local lk = v and v.kind
    if lk == "BackLitInt" then
        local imm = math.floor(tonumber(v.raw) or 0)
        if sz == "q" and (imm < -2147483648 or imm > 4294967295) then
            emit("mov64_2", mr(d, "q"), mi(imm))
        else
            ri("mov_2", d, imm, sz)
        end
    elseif lk == "BackLitBool" then
        ri("mov_2", d, v.value and 1 or 0, sz)
    elseif lk == "BackLitNull" then
        emit("xor_2", mr(d, sz), mr(d, sz))
    elseif lk == "BackLitFloat" then
        local f = tonumber(v.raw) or 0
        local bits = (sz == "d")
            and string.unpack("I4", string.pack("f", f))
            or  string.unpack("I8", string.pack("d", f))
        emit("mov64_2", mr(d, "q"), mi(bits))
    end
end

-- ── unary ─────────────────────────────────────────────────────────────

function isel.unary_(cmd, m)
    local d = regof(cmd.dst, m)
    local s = regof(cmd.value, m)
    local ok = cmd.op.kind
    local sz = cmd.ty and cmd.ty.kind == "BackShapeScalar" and opsize(cmd.ty.scalar.kind) or "q"
    if ok == "BackUnaryIneg" then
        if d ~= s then rr("mov_2", d, s, sz) end
        emit("neg_1", mr(d, sz))
    elseif ok == "BackUnaryBnot" then
        if d ~= s then rr("mov_2", d, s, sz) end
        emit("not_1", mr(d, sz))
    elseif ok == "BackUnaryBoolNot" then
        if d ~= s then rr("mov_2", d, s, sz) end
        ri("xor_2", d, 1, sz)
    end
end

-- ── integer binary ────────────────────────────────────────────────────

function isel.intbin_(cmd, m)
    local d = regof(cmd.dst, m)
    local l = regof(cmd.lhs, m)
    local r = regof(cmd.rhs, m)
    local ok = cmd.op.kind
    local sz = opsize(cmd.scalar.kind)

    if ok == "BackIntSDiv" or ok == "BackIntUDiv" or ok == "BackIntSRem" or ok == "BackIntURem" then
        return isel.divrem_(cmd, m)
    end

    local ops = {BackIntAdd="add_2", BackIntSub="sub_2", BackIntMul="imul_2"}
    local oname = ops[ok]
    if d ~= l then rr("mov_2", d, l, sz) end
    emit(oname, mr(d, sz), mr(r, sz))
end

function isel.divrem_(cmd, m)
    local l = regof(cmd.lhs, m)
    local r = regof(cmd.rhs, m)
    local d = regof(cmd.dst, m)
    local sig = cmd.op.kind == "BackIntSDiv" or cmd.op.kind == "BackIntSRem"
    local rem = cmd.op.kind == "BackIntSRem" or cmd.op.kind == "BackIntURem"
    if l ~= 0 then rr("mov_2", 0, l, "q") end
    if sig then emit("cqo_0") else emit("xor_2", mr(2,"d"), mr(2,"d")) end
    emit(sig and "idiv_1" or "div_1", mr(r, "q"))
    local res = rem and 2 or 0
    if d ~= res then rr("mov_2", d, res, "q") end
end

-- ── bitwise ───────────────────────────────────────────────────────────

function isel.bitbin_(cmd, m)
    local ops = {BackBitAnd="and_2", BackBitOr="or_2", BackBitXor="xor_2"}
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local sz = opsize(cmd.scalar.kind)
    if d ~= l then rr("mov_2", d, l, sz) end
    emit(ops[cmd.op.kind], mr(d, sz), mr(r, sz))
end

function isel.bitnot_(cmd, m)
    local d = regof(cmd.dst, m); local s = regof(cmd.value, m)
    local sz = opsize(cmd.scalar.kind)
    if d ~= s then rr("mov_2", d, s, sz) end
    emit("not_1", mr(d, sz))
end

-- ── shifts / rotates ──────────────────────────────────────────────────

function isel.shift_(cmd, m)
    local ops = {BackShiftLeft="shl_2", BackShiftLogicalRight="shr_2",
                 BackShiftArithmeticRight="sar_2"}
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local sz = opsize(cmd.scalar.kind)
    if r ~= 1 then rr("mov_2", 1, r, "b") end
    if d ~= l then rr("mov_2", d, l, sz) end
    emit(ops[cmd.op.kind], mr(d, sz), mr(1, "b"))
end

function isel.rotate_(cmd, m)
    local ops = {BackRotateLeft="rol_2", BackRotateRight="ror_2"}
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local sz = opsize(cmd.scalar.kind)
    if r ~= 1 then rr("mov_2", 1, r, "b") end
    if d ~= l then rr("mov_2", d, l, sz) end
    emit(ops[cmd.op.kind], mr(d, sz), mr(1, "b"))
end

-- ── comparisons ───────────────────────────────────────────────────────

function isel.compare_(cmd, m)
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local cc = {BackIcmpEq="e",BackIcmpNe="ne",BackSIcmpLt="l",BackSIcmpLe="le",
                BackSIcmpGt="g",BackSIcmpGe="ge",BackUIcmpLt="b",BackUIcmpLe="be",
                BackUIcmpGt="a",BackUIcmpGe="ae"}
    emit("cmp_2", mr(l, "q"), mr(r, "q"))
    emit("set" .. (cc[cmd.op.kind] or "e") .. "_1", mr(d, "b"))
    emit("movzx_2", mr(d, "d"), mr(d, "b"))
end

-- ── casts ─────────────────────────────────────────────────────────────

function isel.cast_(cmd, m)
    local d = regof(cmd.dst, m); local s = regof(cmd.value, m)
    local ok = cmd.op.kind
    if ok == "BackBitcast" then
        if d ~= s then rr("mov_2", d, s, "q") end
    elseif ok == "BackIreduce" then
        local sz = opsize(cmd.ty.kind)
        if d ~= s then rr("mov_2", d, s, sz) end
    elseif ok == "BackSextend" then
        emit("movsxd_2", mr(d, "q"), mr(s, "d"))
    elseif ok == "BackUextend" then
        if d ~= s then rr("mov_2", d, s, "d") end
    end
end

-- ── intrinsics ────────────────────────────────────────────────────────

function isel.intrinsic_(cmd, m)
    local d = regof(cmd.dst, m)
    local s = cmd.args and cmd.args[1] and regof(cmd.args[1], m)
    local ok = cmd.op.kind
    if ok == "BackIntrinsicPopcount" then emit("popcnt_2", mr(d, "q"), mr(s, "q"))
    elseif ok == "BackIntrinsicClz" then emit("lzcnt_2", mr(d, "q"), mr(s, "q"))
    elseif ok == "BackIntrinsicCtz" then emit("tzcnt_2", mr(d, "q"), mr(s, "q"))
    elseif ok == "BackIntrinsicBswap" then
        emit("bswap_1", mr(s, "q"))
        if d ~= s then rr("mov_2", d, s, "q") end
    end
end

-- ── memory ────────────────────────────────────────────────────────────

local function addr_regs(cmd, m)
    local b = cmd.addr.base
    local br
    if b.kind == "BackAddrValue" then br = regof(b.value, m)
    elseif b.kind == "BackAddrStack" then br = 5
    else error("isel: unknown addr base " .. tostring(b.kind)) end
    local or_ = regof(cmd.addr.byte_offset, m)
    return br, or_
end

function isel.load_(cmd, m)
    local d = regof(cmd.dst, m)
    local sz = cmd.ty and cmd.ty.kind == "BackShapeScalar" and opsize(cmd.ty.scalar.kind) or "q"
    local br, o = addr_regs(cmd, m)
    emit("lea_2", mr(d, "q"), "[" .. mr(br) .. "+" .. mr(o) .. "]")
    emit("mov_2", mr(d, sz), "[" .. mr(d) .. "]")
end

function isel.store_(cmd, m)
    local sz = cmd.ty and cmd.ty.kind == "BackShapeScalar" and opsize(cmd.ty.scalar.kind) or "q"
    local v = regof(cmd.value, m)
    local br, o = addr_regs(cmd, m)
    emit("lea_2", mr(0), "[" .. mr(br) .. "+" .. mr(o) .. "]")  -- lea rax, [br+o]
    emit("mov_2", "[" .. mr(0) .. "]", mr(v, sz))               -- mov [rax], val
end

-- ── pointer offset ────────────────────────────────────────────────────

function isel.ptroff_(cmd, m)
    local d = regof(cmd.dst, m)
    local idx = regof(cmd.index, m)
    local b = cmd.base
    local br = b.kind == "BackAddrValue" and regof(b.value, m)
            or b.kind == "BackAddrStack" and 5 or 0
    local es = cmd.elem_size or 1
    local co = cmd.const_offset or 0
    if idx ~= d then rr("mov_2", d, idx, "q") end
    if es ~= 1 then ri("imul_2", d, es, "d") end
    if co ~= 0 then ri("add_2", d, co, "d") end
    emit("add_2", mr(d, "q"), mr(br, "q"))
end

-- ── select ────────────────────────────────────────────────────────────

function isel.select_(cmd, m)
    local d = regof(cmd.dst, m); local c = regof(cmd.cond, m)
    local t = regof(cmd.then_value, m); local e = regof(cmd.else_value, m)
    if d ~= e then rr("mov_2", d, e, "q") end
    emit("test_2", mr(c, "d"), mr(c, "d"))
    emit("cmovne_2", mr(d, "q"), mr(t, "q"))
end

-- ── control flow ──────────────────────────────────────────────────────

isel.block_labels = {}   -- block_id_text → "1".."9"

local function label_for(dest)
    local k = idkey(dest)
    local n = isel.block_labels[k]
    if not n then error("isel: no label for block '" .. k .. "'") end
    return ">" .. tostring(n)
end

function isel.jump_(cmd, m)
    emit("jmp_1", label_for(cmd.dest))
end

function isel.brif_(cmd, m)
    local c = regof(cmd.cond, m)
    emit("test_2", mr(c, "d"), mr(c, "d"))
    emit("jne_1", label_for(cmd.then_block))
    emit("jmp_1", label_for(cmd.else_block))
end

function isel.switch_(cmd, m)
    local v = regof(cmd.value, m)
    local cases = cmd.cases or {}
    local def = label_for(cmd.default_dest)
    if #cases <= 3 then
        for _, cs in ipairs(cases) do
            local imm = tonumber(cs.raw)
            if imm then
                emit("cmp_2", mr(v, "q"), mi(imm))
                emit("je_1", label_for(cs.dest))
            end
        end
        emit("jmp_1", def)
    end
end

-- ── calls ─────────────────────────────────────────────────────────────

isel.func_labels = {}     -- func_id_text → "->func_id"
isel.extern_labels = {}   -- extern_id_text → "->extern_id"

function isel.call_(cmd, m)
    local tgt = cmd.target
    local args = cmd.args or {}
    -- ABI arg registers
    for i, pr in ipairs(abi.param_regs) do
        if i > #args then break end
        local ar = regof(args[i], m)
        if ar ~= pr then rr("mov_2", pr, ar, "q") end
    end
    -- emit call
    if tgt.kind == "BackCallDirect" then
        emit("call_1", isel.func_labels[idkey(tgt.func)])
    elseif tgt.kind == "BackCallExtern" then
        emit("call_1", isel.extern_labels[idkey(tgt.func)])
    elseif tgt.kind == "BackCallIndirect" then
        emit("call_1", mr(regof(tgt.callee, m), "q"))
    end
    -- capture result
    if cmd.result and cmd.result.kind == "BackCallValue" then
        local d = regof(cmd.result.dst, m)
        if d ~= 0 then rr("mov_2", d, 0, "q") end
    end
end

-- ── return ────────────────────────────────────────────────────────────

function isel.retval_(cmd, m)
    local v = regof(cmd.value, m)
    if v ~= 0 then rr("mov_2", 0, v, "q") end
    isel.emit_epilogue()
end

-- ── address-taking ────────────────────────────────────────────────────

isel.stack_slots = {}
isel.next_slot = 0

function isel.alloc_slot(sid, sz, al)
    al = al or 8
    if isel.next_slot % al ~= 0 then
        isel.next_slot = isel.next_slot + (al - (isel.next_slot % al))
    end
    local off = isel.next_slot
    isel.stack_slots[idkey(sid)] = off
    isel.next_slot = off + (sz or 8)
    if isel.next_slot % 8 ~= 0 then isel.next_slot = isel.next_slot + (8 - (isel.next_slot % 8)) end
    return off
end

function isel.stackaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    local off = isel.stack_slots[idkey(cmd.slot)]
    emit("lea_2", mr(d, "q"), "[" .. mr(5) .. "+" .. tostring(off) .. "]")
end

function isel.funcaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    emit("lea_2", mr(d, "q"), isel.func_labels[idkey(cmd.func)])
end

function isel.externaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    emit("lea_2", mr(d, "q"), isel.extern_labels[idkey(cmd.func)])
end

-- ── memcpy / memset ───────────────────────────────────────────────────

function isel.memcpy_(cmd, m)
    local dst = regof(cmd.dst, m); local src = regof(cmd.src, m)
    local len = regof(cmd.len, m)
    if dst ~= 7 then rr("mov_2", 7, dst, "q") end
    if src ~= 6 then rr("mov_2", 6, src, "q") end
    if len ~= 1 then rr("mov_2", 1, len, "q") end
    emit("cld_0"); emit("rep_movsb_0")
end

function isel.memset_(cmd, m)
    local dst = regof(cmd.dst, m); local byte = regof(cmd.byte, m)
    local len = regof(cmd.len, m)
    if dst ~= 7 then rr("mov_2", 7, dst, "q") end
    if byte ~= 0 then rr("mov_2", 0, byte, "b") end
    if len ~= 1 then rr("mov_2", 1, len, "q") end
    emit("cld_0"); emit("rep_stosb_0")
end

-- ── prologue / epilogue ──────────────────────────────────────────────

isel.ucs = nil  -- used callee-saved
isel.sa  = 0    -- spill area

function isel.set_frame(u, s) isel.ucs = u; isel.sa = s end

function isel.emit_prologue()
    emit("push_1", mr(5))          -- push rbp
    emit("mov_2", mr(5), mr(4))     -- mov rbp, rsp
    for _, r in ipairs({3,12,13,14,15}) do
        if isel.ucs and isel.ucs[r] then emit("push_1", mr(r)) end
    end
    if isel.sa > 0 then emit("sub_2", mr(4), mi(isel.sa)) end  -- sub rsp, N
end

function isel.emit_epilogue()
    if isel.sa > 0 then emit("add_2", mr(4), mi(isel.sa)) end  -- add rsp, N
    for i = 5, 1, -1 do
        local r = ({3,12,13,14,15})[i]
        if isel.ucs and isel.ucs[r] then emit("pop_1", mr(r)) end
    end
    emit("pop_1", mr(5))            -- pop rbp
    emit("ret_0")
end

return isel
