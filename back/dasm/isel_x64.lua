-- isel_x64.lua — instruction selection: ASDL BackCmd → x64 assembly
--
-- Uses encode_x64.lua (DynASM templates) for emission.
-- Command dispatch is generated from back/dasm/rules_x64.lisle.
-- Vector operations currently error at rule-handlers as unsupported.

local encode = require("back.dasm.encode_x64")
local abi    = require("back.dasm.abi_sysv")
local LisleCompile = require("lalin.lisle.compile")

local isel = {}
isel.value_scalars = {}
isel.lower_rule_by_index = {}
isel.const_i64_by_val = {}

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

local function emit(op, ...) encode.emit(op, ...) end
local function rr(op, d, s, sz) emit(op, mr(d, sz), mr(s, sz)) end
local function ri(op, d, v, sz) emit(op, mr(d, sz), mi(v)) end

local function this_dir()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    local d = src:match("^(.*)/[^/]+$")
    return d or "."
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local s = f:read("*a")
    f:close()
    return s
end

local function sh_quote(path)
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function file_mtime(path)
    local p = io.popen("stat -c %Y " .. sh_quote(path) .. " 2>/dev/null")
    if not p then return nil end
    local out = p:read("*a") or ""
    p:close()
    return tonumber((out:gsub("%s+$", "")))
end

isel._rules_x64_path = this_dir() .. "/rules_x64.lisle"
isel._rules_x64_seen_mtime = nil
isel._rules_x64_loaded_mtime = nil
isel._lower_cmd_lisle = nil
isel._lower_cmd_lisle_err = nil
isel._lower_cmd_lisle_ctx = {}
isel._lisle_autoreload = (os.getenv("LALIN_DASM_WATCH_RULES") == "1")

function isel.set_lisle_autoreload(enabled)
    isel._lisle_autoreload = enabled and true or false
    return isel._lisle_autoreload
end

function isel.lisle_autoreload_enabled()
    return isel._lisle_autoreload
end

function isel.reload_lisle_dispatch(path)
    if path then isel._rules_x64_path = path end
    isel._lower_cmd_lisle = nil
    isel._lower_cmd_lisle_err = nil

    local mtime = file_mtime(isel._rules_x64_path)
    isel._rules_x64_seen_mtime = mtime

    local src, rerr = read_all(isel._rules_x64_path)
    if not src then
        isel._lower_cmd_lisle_err = "isel: cannot read lisle rules file: " .. tostring(isel._rules_x64_path) .. ": " .. tostring(rerr)
        return nil, isel._lower_cmd_lisle_err
    end

    local env = { isel = isel, encode = encode }
    setmetatable(env, { __index = _G })

    local ok, mod_or_err = pcall(function()
        return select(1, LisleCompile.load_source(src, "back.dasm.rules_x64", env))
    end)
    if not ok then
        isel._lower_cmd_lisle_err = "isel: lisle compile failed for " .. tostring(isel._rules_x64_path) .. ": " .. tostring(mod_or_err)
        return nil, isel._lower_cmd_lisle_err
    end

    local fn = mod_or_err and mod_or_err.lower_cmd
    if type(fn) ~= "function" then
        isel._lower_cmd_lisle_err = "isel: lisle module did not produce lower_cmd"
        return nil, isel._lower_cmd_lisle_err
    end

    isel._lower_cmd_lisle = fn
    isel._rules_x64_loaded_mtime = mtime
    return fn
end

local function maybe_reload_if_changed()
    if not isel._lisle_autoreload then return end
    local mt = file_mtime(isel._rules_x64_path)
    if mt == nil then return end
    if mt ~= isel._rules_x64_seen_mtime then
        isel.reload_lisle_dispatch()
    end
end

function isel.lower_cmd(cmd, regmap, cmd_index)
    maybe_reload_if_changed()
    local fn = isel._lower_cmd_lisle or isel.reload_lisle_dispatch()
    if not fn then error(isel._lower_cmd_lisle_err or "isel: lisle lower_cmd unavailable", 0) end
    return fn(isel._lower_cmd_lisle_ctx, cmd, regmap, cmd_index)
end

-- ── alias ─────────────────────────────────────────────────────────────

function isel.alias_(cmd, m)
    local d = regof(cmd.dst, m)
    local s = regof(cmd.src, m)
    if d == s then return end
    local sk = isel.value_scalars[idkey(cmd.dst)] or isel.value_scalars[idkey(cmd.src)]
    if sk == "BackF32" then
        emit("movss_2", mr(d, "x"), mr(s, "x"))
    elseif sk == "BackF64" then
        emit("movsd_2", mr(d, "x"), mr(s, "x"))
    else
        emit("mov_2", mr(d, "q"), mr(s, "q"))
    end
end

-- ── operand size from scalar kind ─────────────────────────────────────

local function opsize(sk)
    if sk == nil then return "q" end
    -- sk may be: a string kind, a BackScalar {kind=...} table,
    -- or a BackShape {kind="BackShapeScalar", scalar={kind=...}} table.
    if type(sk) == "table" then
        if sk.kind == "BackShapeScalar" then sk = sk.scalar end
        sk = sk.kind  -- unwrap to the plain kind string
    end
    if sk == "BackBool" or sk == "BackI8"  or sk == "BackU8"  then return "b"
    elseif sk == "BackI16" or sk == "BackU16" then return "w"
    elseif sk == "BackI32" or sk == "BackU32" or sk == "BackF32" then return "d"
    else return "q" end
end

-- ── constants ─────────────────────────────────────────────────────────

function isel.const_(cmd, m)
    local d = regof(cmd.dst, m)
    local sk = cmd.ty and cmd.ty.kind
    local sz = opsize(sk)
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
        if sk == "BackF32" then
            local bits = string.unpack("I4", string.pack("f", f))
            emit("mov64_2", mr(d, "q"), mi(bits))
            -- push to xmm0, move back
            emit("push_1", mr(d, "q"))
            emit("movss_2", mr(d, "x"), "[rsp]")
            emit("add_2", mr(4), mi(8))  -- add rsp, 8
            -- store back to dest register as full 64-bit
            -- Actually for float constants, we store the float value
            -- in the register directly. The caller will use it from XMM.
            -- For simplicity, we'll use the integer register for now
            -- and load to XMM when needed for float operations.
            emit("movss_2", mr(d, "x"), mr(d, "d"))
        else  -- BackF64
            local bits = string.unpack("I8", string.pack("d", f))
            emit("mov64_2", mr(d, "q"), mi(bits))
            emit("push_1", mr(d, "q"))
            emit("movsd_2", mr(d, "x"), "[rsp]")
            emit("add_2", mr(4), mi(8))
        end
    end
end

-- ── unary ─────────────────────────────────────────────────────────────

function isel.unary_(cmd, m)
    local d = regof(cmd.dst, m)
    local s = regof(cmd.value, m)
    local ok = cmd.op.kind
    local sz = opsize(cmd.ty)  -- cmd.ty is BackShape
    if ok == "BackUnaryIneg" then
        if d ~= s then rr("mov_2", d, s, sz) end
        emit("neg_1", mr(d, sz))
    elseif ok == "BackUnaryFneg" then
        -- xorps with sign bit mask
        if d ~= s then emit("movsd_2", mr(d, "x"), mr(s, "x")) end
        -- push sign bit mask, xorpd
        emit("mov64_2", mr(0, "q"), mi(0x8000000000000000))
        emit("push_1", mr(0, "q"))
        emit("movsd_2", mr(0, "x"), "[rsp]")
        emit("add_2", mr(4), mi(8))
        emit("xorpd_2", mr(d, "x"), mr(0, "x"))
    elseif ok == "BackUnaryBnot" then
        if d ~= s then rr("mov_2", d, s, "q") end
        emit("not_1", mr(d, "q"))
    elseif ok == "BackUnaryBoolNot" then
        if d ~= s then rr("mov_2", d, s, "d") end
        ri("xor_2", d, 1, "d")
    end
end

-- ── integer binary ────────────────────────────────────────────────────

function isel.intbin_(cmd, m, cmd_index)
    local d = regof(cmd.dst, m)
    local l = regof(cmd.lhs, m)
    local r = regof(cmd.rhs, m)
    local ok = cmd.op.kind
    local sz = opsize(cmd.scalar and cmd.scalar.kind)

    if ok == "BackIntSDiv" or ok == "BackIntUDiv" or ok == "BackIntSRem" or ok == "BackIntURem" then
        return isel.divrem_(cmd, m)
    end

    local rule = cmd_index and isel.lower_rule_by_index and isel.lower_rule_by_index[cmd_index]
    local imm = isel.const_i64_by_val and isel.const_i64_by_val[idkey(cmd.rhs)]
    if imm ~= nil and (rule == "intbin.imm32" or rule == "intbin.mul_pow2") then
        if d ~= l then rr("mov_2", d, l, sz) end
        if ok == "BackIntAdd" then
            ri("add_2", d, imm, sz)
            return
        elseif ok == "BackIntSub" then
            ri("sub_2", d, imm, sz)
            return
        elseif ok == "BackIntMul" and rule == "intbin.mul_pow2" and imm > 0 then
            local sh = math.floor(math.log(imm) / math.log(2))
            ri("shl_2", d, sh, sz)
            return
        end
    end

    local ops = {BackIntAdd="add_2", BackIntSub="sub_2", BackIntMul="imul_2"}
    local oname = ops[ok]
    if not oname then error("isel: unknown int binary op " .. ok) end
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

function isel.bitbin_(cmd, m, cmd_index)
    local ops = {BackBitAnd="and_2", BackBitOr="or_2", BackBitXor="xor_2"}
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local sz = opsize(cmd.scalar and cmd.scalar.kind)
    if d ~= l then rr("mov_2", d, l, sz) end

    local rule = cmd_index and isel.lower_rule_by_index and isel.lower_rule_by_index[cmd_index]
    local imm = isel.const_i64_by_val and isel.const_i64_by_val[idkey(cmd.rhs)]
    if imm ~= nil and rule == "bitbin.imm" then
        ri(ops[cmd.op.kind], d, imm, sz)
        return
    end

    emit(ops[cmd.op.kind], mr(d, sz), mr(r, sz))
end

function isel.bitnot_(cmd, m)
    local d = regof(cmd.dst, m); local s = regof(cmd.value, m)
    local sz = opsize(cmd.scalar and cmd.scalar.kind)
    if d ~= s then rr("mov_2", d, s, sz) end
    emit("not_1", mr(d, sz))
end

-- ── shifts / rotates ──────────────────────────────────────────────────

function isel.shift_(cmd, m, cmd_index)
    local ops = {BackShiftLeft="shl_2", BackShiftLogicalRight="shr_2",
                 BackShiftArithmeticRight="sar_2"}
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local sz = opsize(cmd.scalar and cmd.scalar.kind)

    local rule = cmd_index and isel.lower_rule_by_index and isel.lower_rule_by_index[cmd_index]
    local imm = isel.const_i64_by_val and isel.const_i64_by_val[idkey(cmd.rhs)]
    if imm ~= nil and rule == "shiftrotate.imm" then
        if d ~= l then rr("mov_2", d, l, sz) end
        ri(ops[cmd.op.kind], d, imm, sz)
        return
    end

    local work = d
    local tmp_work, tmp_count = 10, 11
    if work == 1 then work = tmp_work end

    if work ~= l then rr("mov_2", work, l, sz) end

    if r ~= 1 then
        local csrc = r
        if csrc == work then
            rr("mov_2", tmp_count, csrc, "b")
            csrc = tmp_count
        end
        rr("mov_2", 1, csrc, "b")
    end

    emit(ops[cmd.op.kind], mr(work, sz), mr(1, "b"))

    if d ~= work then rr("mov_2", d, work, sz) end
end

function isel.rotate_(cmd, m, cmd_index)
    local ops = {BackRotateLeft="rol_2", BackRotateRight="ror_2"}
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local sz = opsize(cmd.scalar and cmd.scalar.kind)

    local rule = cmd_index and isel.lower_rule_by_index and isel.lower_rule_by_index[cmd_index]
    local imm = isel.const_i64_by_val and isel.const_i64_by_val[idkey(cmd.rhs)]
    if imm ~= nil and rule == "shiftrotate.imm" then
        if d ~= l then rr("mov_2", d, l, sz) end
        ri(ops[cmd.op.kind], d, imm, sz)
        return
    end

    local work = d
    local tmp_work, tmp_count = 10, 11
    if work == 1 then work = tmp_work end

    if work ~= l then rr("mov_2", work, l, sz) end

    if r ~= 1 then
        local csrc = r
        if csrc == work then
            rr("mov_2", tmp_count, csrc, "b")
            csrc = tmp_count
        end
        rr("mov_2", 1, csrc, "b")
    end

    emit(ops[cmd.op.kind], mr(work, sz), mr(1, "b"))

    if d ~= work then rr("mov_2", d, work, sz) end
end

-- ── float binary ──────────────────────────────────────────────────────

function isel.floatbin_(cmd, m)
    local d = regof(cmd.dst, m)
    local l = regof(cmd.lhs, m)
    local r = regof(cmd.rhs, m)
    local ok = cmd.op.kind
    local sk = cmd.scalar and cmd.scalar.kind
    local is_f32 = (sk == "BackF32")
    local move_op = is_f32 and "movss_2" or "movsd_2"
    local ops = {
        BackFloatAdd = is_f32 and "addss_2" or "addsd_2",
        BackFloatSub = is_f32 and "subss_2" or "subsd_2",
        BackFloatMul = is_f32 and "mulss_2" or "mulsd_2",
        BackFloatDiv = is_f32 and "divss_2" or "divsd_2",
    }
    local xop = ops[ok]
    if not xop then error("isel: unknown float binary op " .. ok) end
    if d ~= l then emit(move_op, mr(d, "x"), mr(l, "x")) end
    emit(xop, mr(d, "x"), mr(r, "x"))
end

-- ── comparisons ───────────────────────────────────────────────────────

function isel.compare_(cmd, m)
    local d = regof(cmd.dst, m); local l = regof(cmd.lhs, m); local r = regof(cmd.rhs, m)
    local ok = cmd.op.kind

    -- Integer comparisons
    local int_cc = {
        BackIcmpEq="e", BackIcmpNe="ne",
        BackSIcmpLt="l", BackSIcmpLe="le", BackSIcmpGt="g", BackSIcmpGe="ge",
        BackUIcmpLt="b", BackUIcmpLe="be", BackUIcmpGt="a", BackUIcmpGe="ae",
    }
    -- Float comparisons
    local float_cc = {
        BackFCmpEq="e", BackFCmpNe="ne",
        BackFCmpLt="b", BackFCmpLe="be", BackFCmpGt="a", BackFCmpGe="ae",
    }

    if int_cc[ok] then
        local sz = opsize(cmd.ty)  -- use scalar size for the compare
        emit("cmp_2", mr(l, sz), mr(r, sz))
        emit("set" .. int_cc[ok] .. "_1", mr(d, "b"))
        emit("movzx_2", mr(d, "d"), mr(d, "b"))
    elseif float_cc[ok] then
        -- ucomiss/ucomisd sets EFLAGS
        local sk = cmd.ty and cmd.ty.kind
        local is_f32
        if type(sk) == "table" and sk.kind == "BackShapeScalar" then
            is_f32 = (sk.scalar.kind == "BackF32")
        else
            is_f32 = false
        end
        local cmp_op = is_f32 and "ucomiss_2" or "ucomisd_2"
        emit(cmp_op, mr(l, "x"), mr(r, "x"))
        if ok == "BackFCmpEq" then
            -- For FP equality, we need to check PF (no unordered) and ZF
            emit("setnp_1", mr(d, "b"))   -- d = !unordered
            local tmp = 10  -- r10 as scratch
            emit("sete_1", mr(tmp, "b"))  -- tmp = ZF
            emit("and_2", mr(d, "b"), mr(tmp, "b"))
        else
            emit("set" .. float_cc[ok] .. "_1", mr(d, "b"))
        end
        emit("movzx_2", mr(d, "d"), mr(d, "b"))
    else
        error("isel: unknown compare op " .. ok)
    end
end

-- ── casts ─────────────────────────────────────────────────────────────

function isel.cast_(cmd, m)
    local d = regof(cmd.dst, m); local s = regof(cmd.value, m)
    local ok = cmd.op.kind
    if ok == "BackBitcast" then
        if d ~= s then rr("mov_2", d, s, "q") end
    elseif ok == "BackIreduce" then
        local sk = cmd.ty and cmd.ty.kind
        local sz = opsize(sk)
        if d ~= s then rr("mov_2", d, s, sz) end
    elseif ok == "BackSextend" then
        emit("movsxd_2", mr(d, "q"), mr(s, "d"))
    elseif ok == "BackUextend" then
        local sk = cmd.ty and cmd.ty.kind
        local sz = opsize(sk)
        if d ~= s then rr("mov_2", d, s, sz) end
    elseif ok == "BackFpromote" then
        -- f32 → f64
        emit("cvtss2sd_2", mr(d, "x"), mr(s, "x"))
    elseif ok == "BackFdemote" then
        -- f64 → f32
        emit("cvtsd2ss_2", mr(d, "x"), mr(s, "x"))
    elseif ok == "BackSToF" then
        -- signed int → float (use source width, not always 64-bit)
        local dst_sk = cmd.ty and cmd.ty.kind
        local src_sk = isel.value_scalars[idkey(cmd.value)]
        local src_sz = (src_sk == "BackI64" or src_sk == "BackU64" or src_sk == "BackPtr" or src_sk == "BackIndex") and "q" or "d"
        if dst_sk == "BackF32" then
            emit("cvtsi2ss_2", mr(d, "x"), mr(s, src_sz))
        else
            emit("cvtsi2sd_2", mr(d, "x"), mr(s, src_sz))
        end
    elseif ok == "BackUToF" then
        -- unsigned int → float: fast path for <=32-bit values
        local dst_sk = cmd.ty and cmd.ty.kind
        local src_sk = isel.value_scalars[idkey(cmd.value)]
        local src_sz = (src_sk == "BackU64") and "q" or "d"
        if dst_sk == "BackF32" then
            emit("cvtsi2ss_2", mr(d, "x"), mr(s, src_sz))
        else
            emit("cvtsi2sd_2", mr(d, "x"), mr(s, src_sz))
        end
    elseif ok == "BackFToS" then
        -- float → signed int
        local sk = cmd.ty and cmd.ty.kind
        if sk == "BackI32" then
            emit("cvttss2si_2", mr(d, "d"), mr(s, "x"))
        else
            emit("cvttsd2si_2", mr(d, "q"), mr(s, "x"))
        end
    elseif ok == "BackFToU" then
        -- float → unsigned int (approximate, uses signed conversion)
        local sk = cmd.ty and cmd.ty.kind
        if sk == "BackU32" then
            emit("cvttss2si_2", mr(d, "d"), mr(s, "x"))
        else
            emit("cvttsd2si_2", mr(d, "q"), mr(s, "x"))
        end
    end
end

-- ── intrinsics ────────────────────────────────────────────────────────

function isel.intrinsic_(cmd, m)
    local d = regof(cmd.dst, m)
    local s = cmd.args and cmd.args[1] and regof(cmd.args[1], m)
    local ok = cmd.op.kind

    local scalar = nil
    if type(cmd.ty) == "table" and cmd.ty.kind == "BackShapeScalar" then
        scalar = cmd.ty.scalar and cmd.ty.scalar.kind
    end
    local sz = opsize(scalar)
    if sz == "b" or sz == "w" then sz = "d" end

    if ok == "BackIntrinsicPopcount" then emit("popcnt_2", mr(d, sz), mr(s, sz))
    elseif ok == "BackIntrinsicClz" then emit("lzcnt_2", mr(d, sz), mr(s, sz))
    elseif ok == "BackIntrinsicCtz" then emit("tzcnt_2", mr(d, sz), mr(s, sz))
    elseif ok == "BackIntrinsicBswap" then
        emit("bswap_1", mr(s, sz))
        if d ~= s then rr("mov_2", d, s, sz) end
    elseif ok == "BackIntrinsicSqrt" then
        -- Determine float size from shape
        local shape = cmd.ty
        local is_f32 = false
        if type(shape) == "table" then
            if shape.kind == "BackShapeScalar" then
                is_f32 = (shape.scalar.kind == "BackF32")
            end
        end
        if is_f32 then
            emit("sqrtss_2", mr(d, "x"), mr(s, "x"))
        else
            emit("sqrtsd_2", mr(d, "x"), mr(s, "x"))
        end
    elseif ok == "BackIntrinsicAbs" then
        -- Float abs: clear sign bit
        local shape = cmd.ty
        local is_f32 = false
        if type(shape) == "table" then
            if shape.kind == "BackShapeScalar" then
                is_f32 = (shape.scalar.kind == "BackF32")
            end
        end
        if d ~= s then
            emit(is_f32 and "movss_2" or "movsd_2", mr(d, "x"), mr(s, "x"))
        end
        if is_f32 then
            -- Create mask 0x7FFFFFFF
            emit("mov64_2", mr(0, "q"), mi(0x7FFFFFFF))
            emit("push_1", mr(0, "q"))
            emit("movss_2", mr(0, "x"), "[rsp]")
            emit("add_2", mr(4), mi(8))
            emit("andps_2", mr(d, "x"), mr(0, "x"))
        else
            emit("mov64_2", mr(0, "q"), mi(0x7FFFFFFFFFFFFFFF))
            emit("push_1", mr(0, "q"))
            emit("movsd_2", mr(0, "x"), "[rsp]")
            emit("add_2", mr(4), mi(8))
            emit("andpd_2", mr(d, "x"), mr(0, "x"))
        end
    elseif ok == "BackIntrinsicFloor" then
        emit("roundsd_2", mr(d, "x"), mi(1), mr(s, "x"))  -- roundsd with mode 1 = floor
    elseif ok == "BackIntrinsicCeil" then
        emit("roundsd_2", mr(d, "x"), mi(2), mr(s, "x"))  -- roundsd with mode 2 = ceil
    elseif ok == "BackIntrinsicTruncFloat" then
        emit("roundsd_2", mr(d, "x"), mi(3), mr(s, "x"))  -- roundsd with mode 3 = trunc
    elseif ok == "BackIntrinsicRound" then
        emit("roundsd_2", mr(d, "x"), mi(0), mr(s, "x"))  -- roundsd with mode 0 = nearest
    else
        error("isel: unsupported intrinsic " .. ok)
    end
end

-- ── memory ────────────────────────────────────────────────────────────

local function addr_base_reg(cmd_base, m)
    -- BackAddressBase can be: BackAddrValue, BackAddrStack, BackAddrData
    local bk = cmd_base.kind
    if bk == "BackAddrValue" then
        return regof(cmd_base.value, m)
    elseif bk == "BackAddrStack" then
        return 5  -- rbp (frame pointer)
    elseif bk == "BackAddrData" then
        -- Data address: need to load from globals
        -- For now, use lea with the data label
        local dk = idkey(cmd_base.data)
        return nil, dk  -- signal that this is a data ref
    else
        error("isel: unknown addr base " .. tostring(bk))
    end
end

local function emit_addr_load(target_reg, addr, m)
    -- Emits code to compute the effective address into target_reg.
    -- addr is a BackAddress with base, byte_offset, etc.
    local base = addr.base
    local offset_val = addr.byte_offset

    local bk = base.kind
    if bk == "BackAddrValue" then
        local br = regof(base.value, m)
        local oreg = regof(offset_val, m)
        if oreg ~= 0 then rr("mov_2", 0, oreg, "q") end
        emit("add_2", mr(0, "q"), mr(br, "q"))
        if target_reg ~= 0 then rr("mov_2", target_reg, 0, "q") end
    elseif bk == "BackAddrStack" then
        local off = isel.stack_slots[idkey(base.slot)]
        local oreg = regof(offset_val, m)
        if oreg ~= 0 then rr("mov_2", 0, oreg, "q") end
        emit("lea_2", mr(target_reg, "q"), "[" .. mr(5) .. "+" .. mr(0) .. "]")
        if off then
            ri("add_2", target_reg, off, "q")
        end
    elseif bk == "BackAddrData" then
        local dk = idkey(base.data)
        local oreg = regof(offset_val, m)
        -- lea target_reg, [data_label + offset]
        if oreg ~= 0 then
            rr("mov_2", target_reg, oreg, "q")
            emit("add_2", mr(target_reg, "q"), mr(0, "q"))
        end
        -- For now, data addresses are handled via globals
        -- This will need runtime resolution
        error("isel: BackAddrData not yet supported in load/store (use CmdDataAddr + CmdLoadInfo)")
    end
end

function isel.load_(cmd, m)
    local d = regof(cmd.dst, m)
    local addr = cmd.addr
    local shape = cmd.ty
    local sz = opsize(shape)
    local is_float = false
    if type(shape) == "table" and shape.kind == "BackShapeScalar" then
        local sk = shape.scalar.kind
        if sk == "BackF32" or sk == "BackF64" then is_float = true end
    end

    local base = addr.base
    local bk = base.kind
    local oreg = regof(addr.byte_offset, m)
    local memop

    if bk == "BackAddrValue" then
        local br = regof(base.value, m)
        memop = "[" .. mr(br, "q") .. "+" .. mr(oreg, "q") .. "]"
    elseif bk == "BackAddrStack" then
        local off = isel.stack_slots[idkey(base.slot)] or 0
        memop = "[" .. mr(5, "q") .. "+" .. mr(oreg, "q")
        if off ~= 0 then memop = memop .. (off >= 0 and "+" or "") .. tostring(off) end
        memop = memop .. "]"
    else
        error("isel: load addr base " .. bk .. " not supported directly; use CmdDataAddr + CmdLoadInfo")
    end

    if is_float then
        local load_op = (sz == "d") and "movss_2" or "movsd_2"
        emit(load_op, mr(d, "x"), memop)
    else
        emit("mov_2", mr(d, sz), memop)
    end
end

function isel.store_(cmd, m)
    local shape = cmd.ty
    local sz = opsize(shape)
    local is_float = false
    if type(shape) == "table" and shape.kind == "BackShapeScalar" then
        local sk = shape.scalar.kind
        if sk == "BackF32" or sk == "BackF64" then is_float = true end
    end

    local v = regof(cmd.value, m)
    local addr = cmd.addr
    local base = addr.base
    local bk = base.kind
    local oreg = regof(addr.byte_offset, m)
    local memop

    if bk == "BackAddrValue" then
        local br = regof(base.value, m)
        memop = "[" .. mr(br, "q") .. "+" .. mr(oreg, "q") .. "]"
    elseif bk == "BackAddrStack" then
        local off = isel.stack_slots[idkey(base.slot)] or 0
        memop = "[" .. mr(5, "q") .. "+" .. mr(oreg, "q")
        if off ~= 0 then memop = memop .. (off >= 0 and "+" or "") .. tostring(off) end
        memop = memop .. "]"
    else
        error("isel: store addr base " .. bk .. " not supported directly")
    end

    if is_float then
        local store_op = (sz == "d") and "movss_2" or "movsd_2"
        emit(store_op, memop, mr(v, "x"))
    else
        emit("mov_2", memop, mr(v, sz))
    end
end

-- ── pointer offset ────────────────────────────────────────────────────

function isel.ptroff_(cmd, m)
    local d = regof(cmd.dst, m)
    local idx = regof(cmd.index, m)
    local b = cmd.base
    local bk = b.kind
    local br

    if bk == "BackAddrValue" then
        br = regof(b.value, m)
    elseif bk == "BackAddrStack" then
        br = 5 -- rbp
    elseif bk == "BackAddrData" then
        -- materialize label base in rax and fall through
        local dk = idkey(b.data)
        emit("mov_2", mr(0, "q"), isel.data_labels[dk] or ("->data_" .. tostring(dk)))
        br = 0
    else
        br = 0
    end

    local es = cmd.elem_size or 1
    local co = cmd.const_offset or 0

    -- Cranelift-like fast path: use one LEA when scale is encodable.
    if es == 1 or es == 2 or es == 4 or es == 8 then
        local memop = "[" .. mr(br, "q") .. "+" .. mr(idx, "q")
        if es ~= 1 then memop = memop .. "*" .. tostring(es) end
        if co ~= 0 then memop = memop .. (co >= 0 and "+" or "") .. tostring(co) end
        memop = memop .. "]"
        emit("lea_2", mr(d, "q"), memop)
        return
    end

    -- fallback for non-encodable scales
    if idx ~= d then rr("mov_2", d, idx, "q") end
    if es ~= 1 then ri("imul_2", d, es, "d") end
    if co ~= 0 then ri("add_2", d, co, "d") end
    emit("add_2", mr(d, "q"), mr(br, "q"))
end

-- ── select ────────────────────────────────────────────────────────────

function isel.select_(cmd, m)
    local d = regof(cmd.dst, m); local c = regof(cmd.cond, m)
    local t = regof(cmd.then_value, m); local e = regof(cmd.else_value, m)
    local sz = opsize(cmd.ty)
    if d ~= e then rr("mov_2", d, e, sz) end
    emit("test_2", mr(c, "d"), mr(c, "d"))
    emit("cmovne_2", mr(d, sz), mr(t, sz))
end

-- ── fma ───────────────────────────────────────────────────────────────

function isel.fma_(cmd, m)
    local d = regof(cmd.dst, m)
    local a = regof(cmd.a, m)
    local b = regof(cmd.b, m)
    local c = regof(cmd.c, m)
    local sk = cmd.ty and cmd.ty.kind
    local is_f32 = (sk == "BackF32")
    -- d = a * b + c
    -- If d != a, move a into d
    if d ~= a then emit(is_f32 and "movss_2" or "movsd_2", mr(d, "x"), mr(a, "x")) end
    -- d = d * b
    emit(is_f32 and "mulss_2" or "mulsd_2", mr(d, "x"), mr(b, "x"))
    -- d = d + c
    emit(is_f32 and "addss_2" or "addsd_2", mr(d, "x"), mr(c, "x"))
    -- Note: true FMA3 vfmadd* would be better but requires AVX2/FMA detection
end

-- ── control flow ──────────────────────────────────────────────────────

isel.block_labels = {}   -- block_id_text → global/local label text

local function label_for(dest)
    local k = idkey(dest)
    local n = isel.block_labels[k]
    if not n then error("isel: no label for block '" .. k .. "'") end
    return tostring(n)
end

function isel.cmp_brif_(cmp, br, m)
    local l = regof(cmp.lhs, m)
    local r = regof(cmp.rhs, m)
    local ok = cmp.op.kind

    local int_cc = {
        BackIcmpEq="e", BackIcmpNe="ne",
        BackSIcmpLt="l", BackSIcmpLe="le", BackSIcmpGt="g", BackSIcmpGe="ge",
        BackUIcmpLt="b", BackUIcmpLe="be", BackUIcmpGt="a", BackUIcmpGe="ae",
    }
    local float_cc = {
        BackFCmpEq="e", BackFCmpNe="ne",
        BackFCmpLt="b", BackFCmpLe="be", BackFCmpGt="a", BackFCmpGe="ae",
    }

    if int_cc[ok] then
        local sz = opsize(cmp.ty)
        emit("cmp_2", mr(l, sz), mr(r, sz))
        emit("j" .. int_cc[ok] .. "_1", label_for(br.then_block))
        emit("jmp_1", label_for(br.else_block))
        return
    end

    if float_cc[ok] then
        local sk = cmp.ty and cmp.ty.kind
        local is_f32
        if type(sk) == "table" and sk.kind == "BackShapeScalar" then
            is_f32 = (sk.scalar.kind == "BackF32")
        else
            is_f32 = false
        end
        local cmp_op = is_f32 and "ucomiss_2" or "ucomisd_2"
        emit(cmp_op, mr(l, "x"), mr(r, "x"))

        if ok == "BackFCmpEq" then
            -- ordered equality: if unordered -> else
            emit("jp_1", label_for(br.else_block))
            emit("je_1", label_for(br.then_block))
            emit("jmp_1", label_for(br.else_block))
        else
            emit("j" .. float_cc[ok] .. "_1", label_for(br.then_block))
            emit("jmp_1", label_for(br.else_block))
        end
        return
    end

    error("isel: cmp_brif unsupported compare op " .. tostring(ok))
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
    local tk = tgt.kind
    if tk == "BackCallDirect" then
        emit("call_1", isel.func_labels[idkey(tgt.func)])
    elseif tk == "BackCallExtern" then
        emit("call_1", isel.extern_labels[idkey(tgt.func)])
    elseif tk == "BackCallIndirect" then
        emit("call_1", mr(regof(tgt.callee, m), "q"))
    end
    -- capture result
    local result = cmd.result
    if result then
        local rk = result.kind
        if rk == "BackCallValue" then
            local d = regof(result.dst, m)
            local rsk = result.ty and result.ty.kind
            if rsk == "BackF32" or rsk == "BackF64" then
                -- Result is in xmm0 (reg 0 as XMM)
                -- For now, treat XMM0 as the return register
                -- This is a simplification; proper XMM alloc needed later
                if d ~= 0 then emit("movsd_2", mr(d, "x"), mr(0, "x")) end
            else
                if d ~= 0 then rr("mov_2", d, 0, "q") end
            end
        end
    end
end

-- ── return ────────────────────────────────────────────────────────────

function isel.retval_(cmd, m)
    local v = regof(cmd.value, m)
    local sk = isel.value_scalars[idkey(cmd.value)]
    if sk == "BackF32" then
        if v ~= 0 then emit("movss_2", mr(0, "x"), mr(v, "x")) end
    elseif sk == "BackF64" then
        if v ~= 0 then emit("movsd_2", mr(0, "x"), mr(v, "x")) end
    else
        if v ~= 0 then rr("mov_2", 0, v, "q") end
    end
    isel.emit_epilogue()
end

-- ── address-taking ────────────────────────────────────────────────────

isel.stack_slots = {}
isel.next_slot = 0
isel.data_labels = {}

function isel.alloc_slot(sid, sz, al)
    sz = sz or 8
    al = al or 8
    if isel.next_slot % al ~= 0 then
        isel.next_slot = isel.next_slot + (al - (isel.next_slot % al))
    end
    local start = isel.next_slot
    isel.next_slot = start + sz
    if isel.next_slot % 8 ~= 0 then
        isel.next_slot = isel.next_slot + (8 - (isel.next_slot % 8))
    end
    local off = -(start + sz)
    isel.stack_slots[idkey(sid)] = off
    return off
end

function isel.stackaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    local off = isel.stack_slots[idkey(cmd.slot)] or 0
    local memop = "[" .. mr(5, "q")
    if off ~= 0 then memop = memop .. (off >= 0 and "+" or "") .. tostring(off) end
    memop = memop .. "]"
    emit("lea_2", mr(d, "q"), memop)
end

function isel.funcaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    local lbl = isel.func_labels[idkey(cmd.func)]
    emit("lea_2", mr(d, "q"), "[" .. tostring(lbl) .. "]")
end

function isel.externaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    local lbl = isel.extern_labels[idkey(cmd.func)]
    emit("lea_2", mr(d, "q"), "[" .. tostring(lbl) .. "]")
end

function isel.dataaddr_(cmd, m)
    local d = regof(cmd.dst, m)
    local dk = idkey(cmd.data)
    local lbl = isel.data_labels and isel.data_labels[dk] or ("->data_" .. tostring(dk))
    emit("lea_2", mr(d, "q"), "[" .. tostring(lbl) .. "]")
end

-- ── memcpy / memset ───────────────────────────────────────────────────

function isel.memcpy_(cmd, m)
    local dst = regof(cmd.dst, m); local src = regof(cmd.src, m)
    local len = regof(cmd.len, m)
    -- rep movsb advances rdi/rsi and zeroes rcx; save dst so the IR
    -- value remains valid after the copy.
    emit("push_1", mr(dst, "q"))
    if dst ~= 7 then rr("mov_2", 7, dst, "q") end
    if src ~= 6 then rr("mov_2", 6, src, "q") end
    if len ~= 1 then rr("mov_2", 1, len, "q") end
    emit("cld_0"); emit("rep_0"); emit("movsb_0")
    emit("pop_1", mr(dst, "q"))  -- restore original dst pointer
end

function isel.memset_(cmd, m)
    local dst = regof(cmd.dst, m); local byte = regof(cmd.byte, m)
    local len = regof(cmd.len, m)
    -- rep stosb advances rdi; save dst for the same reason.
    emit("push_1", mr(dst, "q"))
    if dst ~= 7 then rr("mov_2", 7, dst, "q") end
    if byte ~= 0 then rr("mov_2", 0, byte, "b") end
    if len ~= 1 then rr("mov_2", 1, len, "q") end
    emit("cld_0"); emit("rep_0"); emit("stosb_0")
    emit("pop_1", mr(dst, "q"))
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
