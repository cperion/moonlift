-- Lua 5.5 bytecode bit-layout oracle for the Lalin VM.
-- This records encoding facts only. It does not import PUC runtime behavior.

local bytecode = {}

bytecode.SIZE_OP = 7
bytecode.POS_A = 7
bytecode.POS_K = 15
bytecode.POS_B = 16
bytecode.POS_C = 24
bytecode.POS_VB = 16
bytecode.POS_VC = 22
bytecode.POS_BX = 15
bytecode.POS_AX = 7
bytecode.MAX_BX = 131071
bytecode.OFFSET_SBX = 65535
bytecode.MAX_AX = 33554431
bytecode.OFFSET_SJ = 16777215
bytecode.OFFSET_SC = 127

local POW_A = 2 ^ bytecode.POS_A
local POW_K = 2 ^ bytecode.POS_K
local POW_B = 2 ^ bytecode.POS_B
local POW_C = 2 ^ bytecode.POS_C
local POW_VC = 2 ^ bytecode.POS_VC
local POW_BX = 2 ^ bytecode.POS_BX
local POW_AX = 2 ^ bytecode.POS_AX
local POW_32 = 2 ^ 32

function bytecode.exprs(expr)
    return {
        OP = expr [[as(u16, word & 127)]],
        A = expr [[as(u16, (word >> 7) & 255)]],
        K = expr [[as(u8, (word >> 15) & 1)]],
        B = expr [[as(u16, (word >> 16) & 255)]],
        C = expr [[as(u16, (word >> 24) & 255)]],
        VB = expr [[as(u16, (word >> 16) & 63)]],
        VC = expr [[as(u16, (word >> 22) & 1023)]],
        BX = expr [[(word >> 15) & 131071]],
        SBX = expr [[as(i32, ((word >> 15) & 131071)) - 65535]],
        AX = expr [[(word >> 7) & 33554431]],
        SJ = expr [[as(i32, ((word >> 7) & 33554431)) - 16777215]],
        SC = expr [[as(i32, ((word >> 24) & 255)) - 127]],
    }
end

local function norm32(w)
    w = w % POW_32
    if w < 0 then w = w + POW_32 end
    return w
end

function bytecode.decode_word(word)
    word = norm32(word)
    local op = word % 128
    local a = math.floor(word / POW_A) % 256
    local k = math.floor(word / POW_K) % 2
    local b = math.floor(word / POW_B) % 256
    local c = math.floor(word / POW_C) % 256
    local vb = math.floor(word / POW_B) % 64
    local vc = math.floor(word / POW_VC) % 1024
    local bx = math.floor(word / POW_BX) % 131072
    local ax = math.floor(word / POW_AX) % 33554432
    return {
        word = word,
        op = op,
        A = a,
        K = k,
        B = b,
        C = c,
        vB = vb,
        vC = vc,
        Bx = bx,
        sBx = bx - bytecode.OFFSET_SBX,
        Ax = ax,
        sJ = ax - bytecode.OFFSET_SJ,
        sC = c - bytecode.OFFSET_SC,
    }
end

function bytecode.encode_ABC(op, a, b, c, k)
    return norm32(op + (a or 0) * POW_A + (k or 0) * POW_K + (b or 0) * POW_B + (c or 0) * POW_C)
end

function bytecode.encode_ABx(op, a, bx)
    return norm32(op + (a or 0) * POW_A + (bx or 0) * POW_BX)
end

function bytecode.encode_AsBx(op, a, sbx)
    return bytecode.encode_ABx(op, a, (sbx or 0) + bytecode.OFFSET_SBX)
end

function bytecode.encode_Ax(op, ax)
    return norm32(op + (ax or 0) * POW_AX)
end

function bytecode.encode_sJ(op, sj)
    return bytecode.encode_Ax(op, (sj or 0) + bytecode.OFFSET_SJ)
end

function bytecode.encode_AvBCk(op, a, vb, vc, k)
    return norm32(op + (a or 0) * POW_A + (k or 0) * POW_K + (vb or 0) * POW_B + (vc or 0) * POW_VC)
end

return bytecode
