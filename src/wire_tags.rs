/// Flat wire tags — one per Cranelift IR operation variant.
/// The tag space is dense (1..=N) with no gaps.
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WireTag {
    // ── Structural tags (function body scaffold) ────
    CreateBlock = 1,
    SwitchToBlock = 2,
    AppendBlockParam = 3,
    CreateStackSlot = 4,
    AppendBlockParamVec = 5,

    // ── Constants ────
    ConstI32 = 10,
    ConstI64 = 11,
    ConstF32 = 12,
    ConstF64 = 13,
    ConstBool = 14,
    ConstNull = 15,
    ConstInt = 16,     // generic: [dst, scalar_type, lo, hi]

    // ── Integer arithmetic ────
    Iadd = 20,
    Isub = 21,
    Imul = 22,
    Sdiv = 23,
    Udiv = 24,
    Srem = 25,
    Urem = 26,
    Ineg = 27,

    // ── Float arithmetic ────
    Fadd = 30,
    Fsub = 31,
    Fmul = 32,
    Fdiv = 33,
    Fneg = 34,
    Fabs = 35,
    Fma = 36,    // [dst, a, b, c]
    Sqrt = 37,
    Floor = 38,
    Ceil = 39,
    Trunc = 40,
    Nearest = 41,

    // ── Bitwise ────
    Band = 50,
    Bor = 51,
    Bxor = 52,
    Bnot = 53,

    // ── Shift / Rotate ────
    Ishl = 60,
    Ushr = 61,
    Sshr = 62,
    Rotl = 63,
    Rotr = 64,

    // ── Compare (returns b1) ────
    Icmp = 70,    // [dst, cc_kind, lhs, rhs]  — cc_kind maps to IntCC
    Fcmp = 71,    // [dst, cc_kind, lhs, rhs]  — maps to FloatCC

    // ── Cast / Convert ────
    Bitcast = 80,     // [dst, scalar_type, src]
    Ireduce = 81,     // [dst, scalar_type, src]
    Sextend = 82,     // [dst, scalar_type, src]
    Uextend = 83,     // [dst, scalar_type, src]
    Fpromote = 84,    // [dst, scalar_type, src]
    Fdemote = 85,     // [dst, scalar_type, src]
    FcvtFromSint = 86, // [dst, scalar_type, src]
    FcvtFromUint = 87, // [dst, scalar_type, src]
    FcvtToSint = 88,  // [dst, scalar_type, src]
    FcvtToUint = 89,  // [dst, scalar_type, src]

    // ── Intrinsics ────
    Popcnt = 90,      // [dst, src]
    Clz = 91,         // [dst, src]
    Ctz = 92,         // [dst, src]
    Bswap = 93,       // [dst, src]
    Iabs = 94,        // [dst, src]

    // ── Address ops ────
    StackAddr = 100,   // [dst, ptr_type, slot_id]
    GlobalValue = 101, // [dst, ptr_type, data_id]
    FuncAddr = 102,    // [dst, ptr_type, func_id]
    ExternAddr = 103,  // [dst, ptr_type, extern_id]

    // ── Memory ────
    Load = 110,        // [dst, scalar_type, memflags, addr] memflags bit0=notrap bit1=aligned bit2=can_move bit3=readonly
    Store = 111,       // [scalar_type, memflags, addr, value]
    AtomicLoad = 112,  // [dst, scalar_type, memflags, addr]
    AtomicStore = 113, // [scalar_type, memflags, addr, value]
    AtomicRmw = 114,   // [dst, scalar_type, op_kind, memflags, addr, value]
    AtomicCas = 115,   // [dst, scalar_type, memflags, addr, expected, replacement]
    Fence = 116,       // (no slots)
    Memcpy = 117,      // [dst_ptr, src_ptr, len]
    Memset = 118,      // [dst_ptr, byte_val, len]
    Memcmp = 119,      // [dst, left, right, len]

    // ── Pointer ────
    PtrAdd = 120,      // [dst, base, offset]
    PtrOffset = 121,   // [dst, base, index, elem_size, const_lo, const_hi]

    // ── Vector ────
    Splat = 130,             // [dst, scalar_type, lanes, src]
    InsertLane = 131,        // [dst, vector, lane_value, lane_idx]
    ExtractLane = 132,       // [dst, scalar_type, vector, lane_idx]
    VecIadd = 133,           // [dst, lhs, rhs]
    VecIsub = 134,
    VecImul = 135,
    VecBand = 136,
    VecBor = 137,
    VecBxor = 138,
    VecIcmpEq = 139,         // [dst, lhs, rhs] — vector icmp
    VecIcmpNe = 140,
    VecSIcmpLt = 141,
    VecSIcmpLe = 142,
    VecSIcmpGt = 143,
    VecSIcmpGe = 144,
    VecUIcmpLt = 145,
    VecUIcmpLe = 146,
    VecUIcmpGt = 147,
    VecUIcmpGe = 148,
    VecSelect = 149,         // [dst, mask, then_val, else_val]
    VecMaskNot = 150,        // [dst, vec]
    VecMaskAnd = 151,        // [dst, lhs, rhs]
    VecMaskOr = 152,         // [dst, lhs, rhs]
    VecLoad = 153,           // [dst, scalar_type, lanes, memflags, addr] memflags bit0=notrap bit1=aligned bit2=can_move bit3=readonly
    VecStore = 154,          // [scalar_type, lanes, memflags, addr, value]

    // ── Select ────
    Select = 160,            // [dst, cond, then_val, else_val]

    // ── Control flow ────
    Jump = 170,              // [dest_block, n_args, args...] (variable)
    Brif = 171,              // [cond, then_block, then_nargs, then_args..., else_block, else_nargs, else_args...] (variable)
    SwitchInt = 172,         // [value, scalar_type, n_cases, cases..., default_block]
                             // each case: [lo, hi, dest_block]  (lo = u32, hi = u32 for u64 value, dest_block = u32)
    ReturnVoid = 173,        // (no slots)
    ReturnValue = 174,       // [value]
    Trap = 175,              // (no slots)

    // ── Call ────
    CallDirect = 180,        // [result_tag, dst, scalar_type, func_id, sig_id, n_args, args...] (variable)
                             // result_tag = 0 (void) or 1 (value)
    CallExtern = 181,        // [result_tag, dst, scalar_type, extern_id, sig_id, n_args, args...] (variable)
    CallIndirect = 182,      // [result_tag, dst, scalar_type, callee, sig_id, n_args, args...] (variable)

    // ── Singleton ops ────
    Alias = 190,             // [dst, src]
    BoolNot = 191,           // [dst, value]
}

/// Minimum fixed slot count per tag (before any variable-length data).
/// Tags with variable-length data have their fixed prefix counted here;
/// the decoder reads additional slots based on count fields.
pub static TAG_SLOTS: [u8; 256] = {
    let mut t = [0u8; 256];

    // Structural
    t[WireTag::CreateBlock as usize] = 1;     // [block_id]
    t[WireTag::SwitchToBlock as usize] = 1;   // [block_id]
    t[WireTag::AppendBlockParam as usize] = 3; // [block_id, scalar_type, value_id]
    t[WireTag::CreateStackSlot as usize] = 3; // [slot_id, size, align_log2]
    t[WireTag::AppendBlockParamVec as usize] = 4; // [block_id, scalar_type, lanes, value_id]

    // Constants
    t[WireTag::ConstI32 as usize] = 2;   // [dst, value]
    t[WireTag::ConstI64 as usize] = 3;   // [dst, lo, hi]
    t[WireTag::ConstF32 as usize] = 2;   // [dst, bits]
    t[WireTag::ConstF64 as usize] = 3;   // [dst, lo, hi]
    t[WireTag::ConstBool as usize] = 2;  // [dst, 0/1]
    t[WireTag::ConstNull as usize] = 1;  // [dst]
    t[WireTag::ConstInt as usize] = 4;   // [dst, scalar_type, lo, hi]

    // Integer arithmetic (all: [dst, lhs, rhs])
    t[WireTag::Iadd as usize] = 3;
    t[WireTag::Isub as usize] = 3;
    t[WireTag::Imul as usize] = 3;
    t[WireTag::Sdiv as usize] = 3;
    t[WireTag::Udiv as usize] = 3;
    t[WireTag::Srem as usize] = 3;
    t[WireTag::Urem as usize] = 3;
    t[WireTag::Ineg as usize] = 2;  // [dst, src]

    // Float arithmetic
    t[WireTag::Fadd as usize] = 3;
    t[WireTag::Fsub as usize] = 3;
    t[WireTag::Fmul as usize] = 3;
    t[WireTag::Fdiv as usize] = 3;
    t[WireTag::Fneg as usize] = 2;
    t[WireTag::Fabs as usize] = 2;
    t[WireTag::Fma as usize] = 4;   // [dst, a, b, c]
    t[WireTag::Sqrt as usize] = 2;
    t[WireTag::Floor as usize] = 2;
    t[WireTag::Ceil as usize] = 2;
    t[WireTag::Trunc as usize] = 2;
    t[WireTag::Nearest as usize] = 2;

    // Bitwise
    t[WireTag::Band as usize] = 3;
    t[WireTag::Bor as usize] = 3;
    t[WireTag::Bxor as usize] = 3;
    t[WireTag::Bnot as usize] = 2;

    // Shift / Rotate
    t[WireTag::Ishl as usize] = 3;
    t[WireTag::Ushr as usize] = 3;
    t[WireTag::Sshr as usize] = 3;
    t[WireTag::Rotl as usize] = 3;
    t[WireTag::Rotr as usize] = 3;

    // Compare
    t[WireTag::Icmp as usize] = 4;  // [dst, cc_kind, lhs, rhs]
    t[WireTag::Fcmp as usize] = 4;  // [dst, cc_kind, lhs, rhs]

    // Cast
    t[WireTag::Bitcast as usize] = 3;
    t[WireTag::Ireduce as usize] = 3;
    t[WireTag::Sextend as usize] = 3;
    t[WireTag::Uextend as usize] = 3;
    t[WireTag::Fpromote as usize] = 3;
    t[WireTag::Fdemote as usize] = 3;
    t[WireTag::FcvtFromSint as usize] = 3;
    t[WireTag::FcvtFromUint as usize] = 3;
    t[WireTag::FcvtToSint as usize] = 3;
    t[WireTag::FcvtToUint as usize] = 3;

    // Intrinsics
    t[WireTag::Popcnt as usize] = 2;
    t[WireTag::Clz as usize] = 2;
    t[WireTag::Ctz as usize] = 2;
    t[WireTag::Bswap as usize] = 2;
    t[WireTag::Iabs as usize] = 2;

    // Address ops
    t[WireTag::StackAddr as usize] = 3;    // [dst, ptr_type, slot_id]
    t[WireTag::GlobalValue as usize] = 3;  // [dst, ptr_type, data_id]
    t[WireTag::FuncAddr as usize] = 3;     // [dst, ptr_type, func_id]
    t[WireTag::ExternAddr as usize] = 3;   // [dst, ptr_type, extern_id]

    // Memory
    t[WireTag::Load as usize] = 4;     // [dst, scalar_type, memflags, addr]
    t[WireTag::Store as usize] = 4;    // [scalar_type, memflags, addr, value]
    t[WireTag::AtomicLoad as usize] = 4;
    t[WireTag::AtomicStore as usize] = 4;
    t[WireTag::AtomicRmw as usize] = 6; // [dst, scalar_type, op_kind, memflags, addr, value]
    t[WireTag::AtomicCas as usize] = 6; // [dst, scalar_type, memflags, addr, expected, replacement]
    t[WireTag::Fence as usize] = 0;
    t[WireTag::Memcpy as usize] = 3;
    t[WireTag::Memset as usize] = 3;
    t[WireTag::Memcmp as usize] = 4;

    // Pointer
    t[WireTag::PtrAdd as usize] = 3;
    t[WireTag::PtrOffset as usize] = 6; // [dst, base, index, elem_size, const_lo, const_hi]

    // Vector
    t[WireTag::Splat as usize] = 4;             // [dst, scalar_type, lanes, src]
    t[WireTag::InsertLane as usize] = 4;   // [dst, vector, lane_value, lane_idx]
    t[WireTag::ExtractLane as usize] = 4;  // [dst, scalar_type, vector, lane_idx]
    t[WireTag::VecIadd as usize] = 3;
    t[WireTag::VecIsub as usize] = 3;
    t[WireTag::VecImul as usize] = 3;
    t[WireTag::VecBand as usize] = 3;
    t[WireTag::VecBor as usize] = 3;
    t[WireTag::VecBxor as usize] = 3;
    t[WireTag::VecIcmpEq as usize] = 3;
    t[WireTag::VecIcmpNe as usize] = 3;
    t[WireTag::VecSIcmpLt as usize] = 3;
    t[WireTag::VecSIcmpLe as usize] = 3;
    t[WireTag::VecSIcmpGt as usize] = 3;
    t[WireTag::VecSIcmpGe as usize] = 3;
    t[WireTag::VecUIcmpLt as usize] = 3;
    t[WireTag::VecUIcmpLe as usize] = 3;
    t[WireTag::VecUIcmpGt as usize] = 3;
    t[WireTag::VecUIcmpGe as usize] = 3;
    t[WireTag::VecSelect as usize] = 4;     // [dst, mask, then_val, else_val]
    t[WireTag::VecMaskNot as usize] = 2;    // [dst, vec]
    t[WireTag::VecMaskAnd as usize] = 3;
    t[WireTag::VecMaskOr as usize] = 3;
    t[WireTag::VecLoad as usize] = 5;       // [dst, scalar_type, lanes, memflags, addr]
    t[WireTag::VecStore as usize] = 5;      // [scalar_type, lanes, memflags, addr, value]

    // Select
    t[WireTag::Select as usize] = 4;  // [dst, cond, then_val, else_val]

    // Control flow (variable-length tags have their fixed prefix counted here)
    t[WireTag::Jump as usize] = 2;              // [dest_block, n_args] + variable args
    t[WireTag::Brif as usize] = 2;              // [cond, then_block] then variable then_args + else + else_args
    t[WireTag::SwitchInt as usize] = 3;          // [value, scalar_type, n_cases] + variable cases + default_block
    t[WireTag::ReturnVoid as usize] = 0;
    t[WireTag::ReturnValue as usize] = 1;        // [value]
    t[WireTag::Trap as usize] = 0;

    // Call (variable)
    t[WireTag::CallDirect as usize] = 5;    // [result_tag, dst/void, scalar_type, func_id, sig_id] + variable args
    t[WireTag::CallExtern as usize] = 5;    // [result_tag, dst/void, scalar_type, extern_id, sig_id] + variable args
    t[WireTag::CallIndirect as usize] = 5;  // [result_tag, dst/void, scalar_type, callee, sig_id] + variable args

    // Singleton ops
    t[WireTag::Alias as usize] = 2;   // [dst, src]
    t[WireTag::BoolNot as usize] = 2; // [dst, value]

    t
};
