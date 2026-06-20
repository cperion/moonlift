use std::collections::HashMap;

use crate::wire_tags::{WireTag, TAG_SLOTS};
use crate::{BackScalar, MoonliftError};
use cranelift_codegen::ir::condcodes::{FloatCC, IntCC};
use cranelift_codegen::ir::immediates::{Ieee32, Ieee64};
use cranelift_codegen::ir::{
    AbiParam, AtomicRmwOp, Block, BlockArg, InstBuilder, MemFlags, Signature,
    StackSlot, StackSlotData, StackSlotKind, TrapCode, Type, UserFuncName, Value, types,
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Switch};
use cranelift_module::{DataDescription, DataId, FuncId, Linkage, Module};
use cranelift_codegen::ir::{FuncRef, GlobalValue};

fn read_u32(buf: &[u8], pos: &mut usize) -> Result<u32, MoonliftError> {
    if *pos + 4 > buf.len() {
        return Err(MoonliftError(format!("unexpected end of buffer at offset {pos}")));
    }
    let v = u32::from_le_bytes(buf[*pos..*pos + 4].try_into().unwrap());
    *pos += 4;
    Ok(v)
}

fn read_slots(buf: &[u8], pos: &mut usize, n: usize) -> Result<Vec<u32>, MoonliftError> {
    let end = pos.checked_add(n * 4).ok_or_else(|| MoonliftError("overflow".into()))?;
    if end > buf.len() {
        return Err(MoonliftError(format!("unexpected end at offset {pos}, needed {} bytes", n * 4)));
    }
    let mut slots = Vec::with_capacity(n);
    for _ in 0..n {
        slots.push(u32::from_le_bytes(buf[*pos..*pos + 4].try_into().unwrap()));
        *pos += 4;
    }
    Ok(slots)
}

fn st(code: u32, ptr_ty: Type) -> Result<Type, MoonliftError> {
    let bs = match code {
        1 => BackScalar::Bool, 2 => BackScalar::I8, 3 => BackScalar::I16,
        4 => BackScalar::I32, 5 => BackScalar::I64, 6 => BackScalar::U8,
        7 => BackScalar::U16, 8 => BackScalar::U32, 9 => BackScalar::U64,
        10 => BackScalar::F32, 11 => BackScalar::F64, 12 => BackScalar::Ptr,
        13 => BackScalar::Index,
        _ => return Err(MoonliftError(format!("unknown scalar code {code}"))),
    };
    Ok(bs.clif_type(ptr_ty))
}

fn mf(bits: u32) -> MemFlags {
    let mut f = MemFlags::new();
    if bits & 1 != 0 { f.set_notrap(); }
    if bits & 2 != 0 { f.set_aligned(); }
    if bits & 4 != 0 { f.set_can_move(); }
    if bits & 8 != 0 { f.set_readonly(); }
    f
}

fn icc(kind: u32) -> Result<IntCC, MoonliftError> {
    match kind {
        1 => Ok(IntCC::Equal), 2 => Ok(IntCC::NotEqual),
        3 => Ok(IntCC::SignedLessThan), 4 => Ok(IntCC::SignedLessThanOrEqual),
        5 => Ok(IntCC::SignedGreaterThan), 6 => Ok(IntCC::SignedGreaterThanOrEqual),
        7 => Ok(IntCC::UnsignedLessThan), 8 => Ok(IntCC::UnsignedLessThanOrEqual),
        9 => Ok(IntCC::UnsignedGreaterThan), 10 => Ok(IntCC::UnsignedGreaterThanOrEqual),
        _ => Err(MoonliftError(format!("unknown IntCC {kind}"))),
    }
}

fn fcc(kind: u32) -> Result<FloatCC, MoonliftError> {
    match kind {
        1 => Ok(FloatCC::Equal), 2 => Ok(FloatCC::NotEqual),
        3 => Ok(FloatCC::LessThan), 4 => Ok(FloatCC::LessThanOrEqual),
        5 => Ok(FloatCC::GreaterThan), 6 => Ok(FloatCC::GreaterThanOrEqual),
        _ => Err(MoonliftError(format!("unknown FloatCC {kind}"))),
    }
}

fn rmw(kind: u32) -> Result<AtomicRmwOp, MoonliftError> {
    match kind {
        1 => Ok(AtomicRmwOp::Add), 2 => Ok(AtomicRmwOp::Sub),
        3 => Ok(AtomicRmwOp::And), 4 => Ok(AtomicRmwOp::Or),
        5 => Ok(AtomicRmwOp::Xor), 6 => Ok(AtomicRmwOp::Xchg),
        _ => Err(MoonliftError(format!("unknown AtomicRmwOp {kind}"))),
    }
}

fn bfc(b: &mut FunctionBuilder<'_>, cond: Value) -> Value {
    let one = b.ins().iconst(types::I8, 1);
    let zero = b.ins().iconst(types::I8, 0);
    b.ins().select(cond, one, zero)
}

struct ModuleHeader {
    decl_offset: usize, decl_len: usize,
    body_tbl_offset: usize, body_tbl_len: usize,
}

fn read_header(buf: &[u8], pos: &mut usize) -> Result<ModuleHeader, MoonliftError> {
    let magic = read_u32(buf, pos)?;
    if magic != 0x4D4C { return Err(MoonliftError(format!("bad magic {magic:#010x}"))); }
    let _ver = read_u32(buf, pos)?;
    let _n_funcs = read_u32(buf, pos)?;
    let doff = read_u32(buf, pos)? as usize;
    let dlen = read_u32(buf, pos)? as usize;
    let boff = read_u32(buf, pos)? as usize;
    let blen = read_u32(buf, pos)? as usize;
    Ok(ModuleHeader { decl_offset: doff, decl_len: dlen, body_tbl_offset: boff, body_tbl_len: blen })
}

pub struct ModuleState {
    pub funcs: HashMap<u32, (FuncId, String, Signature)>,
    pub externs: HashMap<u32, FuncId>,
    pub datas: HashMap<u32, DataId>,
    pub sigs: HashMap<u32, Signature>,
}

fn mk_sig(module: &impl Module, params: &[Type], results: &[Type]) -> Signature {
    let mut sig = Signature::new(module.target_config().default_call_conv);
    for &t in params { sig.params.push(AbiParam::new(t)); }
    for &t in results { sig.returns.push(AbiParam::new(t)); }
    sig
}

fn read_declarations<M: Module>(buf: &[u8], pos: &mut usize, end: usize, module: &mut M) -> Result<ModuleState, MoonliftError> {
    let mut sig_types: HashMap<u32, (Vec<Type>, Vec<Type>)> = HashMap::new();
    let mut sigs: HashMap<u32, Signature> = HashMap::new();
    struct DataD { id: DataId, size: u32, align2: u32, inits: Vec<(u32, Vec<u8>)> }

    let ptr_ty = module.target_config().pointer_type();
    
    // Signatures
    if *pos < end {
        let n = read_u32(buf, pos)?;
        for _ in 0..n {
            let sid = read_u32(buf, pos)?;
            let np = read_u32(buf, pos)?;
            let pc = read_slots(buf, pos, np as usize)?;
            let params: Vec<Type> = pc.into_iter().map(|c| st(c, ptr_ty)).collect::<Result<_,_>>()?;
            let nr = read_u32(buf, pos)?;
            let rc = read_slots(buf, pos, nr as usize)?;
            let results: Vec<Type> = rc.into_iter().map(|c| st(c, ptr_ty)).collect::<Result<_,_>>()?;
            sig_types.insert(sid, (params.clone(), results.clone()));
            let sig = mk_sig(module, &params, &results);
            sigs.insert(sid, sig);
        }
    }

    let mut funcs: HashMap<u32, (FuncId, String, Signature)> = HashMap::new();
    let mut externs: HashMap<u32, FuncId> = HashMap::new();
    let mut datas: HashMap<u32, DataD> = HashMap::new();

    if *pos < end {
        let n = read_u32(buf, pos)?;
        for _ in 0..n {
            let fid = read_u32(buf, pos)?;
            let sig_id = read_u32(buf, pos)?;
            let vis = read_u32(buf, pos)?;
            let nlen = read_u32(buf, pos)? as usize;
            let name = if nlen > 0 {
                let end = *pos + nlen;
                if end > buf.len() { return Err(MoonliftError(format!("func {fid} name overflows"))); }
                let s = String::from_utf8_lossy(&buf[*pos..end]).to_string();
                *pos = end;
                let pad = (4 - (nlen % 4)) % 4;
                *pos += pad;
                s
            } else {
                format!("anon_{fid}")
            };
            let (p, r) = sig_types.get(&sig_id)
                .ok_or_else(|| MoonliftError(format!("func {fid}: unknown sig {sig_id}")))?;
            let sig = mk_sig(module, p, r);
            let linkage = if vis == 1 { Linkage::Export } else { Linkage::Local };
            let cfid = module.declare_function(&name, linkage, &sig)
                .map_err(|e| MoonliftError(format!("declare {name}: {e:?}")))?;
            funcs.insert(fid, (cfid, name, sig));
        }
    }

    if *pos < end {
        let n = read_u32(buf, pos)?;
        for _ in 0..n {
            let did = read_u32(buf, pos)?;
            let size = read_u32(buf, pos)?;
            let a2 = read_u32(buf, pos)?;
            let sym = format!("moonlift_data_{did:08x}");
            let cdid = module.declare_data(&sym, Linkage::Local, true, false)
                .map_err(|e| MoonliftError(format!("declare data {sym}: {e:?}")))?;
            datas.insert(did, DataD { id: cdid, size, align2: a2, inits: Vec::new() });
        }
    }

    if *pos < end {
        let n = read_u32(buf, pos)?;
        for _ in 0..n {
            let did = read_u32(buf, pos)?;
            let offset = read_u32(buf, pos)?;
            let lt = read_u32(buf, pos)?;
            let lo = read_u32(buf, pos)?;
            let hi = read_u32(buf, pos)?;
            if let Some(d) = datas.get_mut(&did) {
                let bytes = if lt == 0 { vec![0u8; lo as usize] }
                    else if lt == 1 { vec![if lo != 0 { 1 } else { 0 }; 1] }
                    else {
                        let mut v = Vec::with_capacity(8);
                        v.extend_from_slice(&lo.to_le_bytes());
                        v.extend_from_slice(&hi.to_le_bytes());
                        v
                    };
                d.inits.push((offset, bytes));
            }
        }
    }

    for (_did, d) in &datas {
        let mut desc = DataDescription::new();
        let mut bytes = vec![0u8; d.size as usize];
        for &(off, ref init) in &d.inits {
            let s = off as usize;
            let copy_end = (s + init.len()).min(bytes.len());
            if s < copy_end {
                let len = copy_end - s;
                bytes[s..s+len].copy_from_slice(&init[..len]);
            }
        }
        desc.define(bytes.into_boxed_slice());
        desc.set_align(1u64 << d.align2);
        module.define_data(d.id, &desc)
            .map_err(|e| MoonliftError(format!("define data {_did}: {e:?}")))?;
    }

    if *pos < end {
        let n = read_u32(buf, pos)?;
        for _ in 0..n {
            let eid = read_u32(buf, pos)?;
            let sig_id = read_u32(buf, pos)?;
            let nlen = read_u32(buf, pos)? as usize;
            let sym = if nlen > 0 {
                let end = *pos + nlen;
                if end > buf.len() { return Err(MoonliftError(format!("extern {eid} name overflows"))); }
                let s = String::from_utf8_lossy(&buf[*pos..end]).to_string();
                *pos = end;
                let pad = (4 - (nlen % 4)) % 4;
                *pos += pad;
                s
            } else {
                format!("extern_{eid}")
            };
            let (p, r) = sig_types.get(&sig_id)
                .ok_or_else(|| MoonliftError(format!("extern {eid}: unknown sig {sig_id}")))?;
            let sig = mk_sig(module, p, r);
            let cfid = module.declare_function(&sym, Linkage::Import, &sig)
                .map_err(|e| MoonliftError(format!("declare extern {sym}: {e:?}")))?;
            externs.insert(eid, cfid);
        }
    }

    let datas: HashMap<u32, DataId> = datas.into_iter().map(|(k, d)| (k, d.id)).collect();
    Ok(ModuleState { funcs, externs, datas, sigs })
}

fn read_body_table(buf: &[u8], hdr: &ModuleHeader) -> Result<Vec<(u32, usize, usize)>, MoonliftError> {
    let mut pos = hdr.body_tbl_offset;
    let end = hdr.body_tbl_offset + hdr.body_tbl_len;
    let mut v = Vec::new();
    while pos + 12 <= end {
        let fid = read_u32(buf, &mut pos)?;
        let off = read_u32(buf, &mut pos)? as usize;
        let len = read_u32(buf, &mut pos)? as usize;
        v.push((fid, off, len));
    }
    Ok(v)
}

struct BodyCtx<'a> {
    builder: FunctionBuilder<'a>,
    values: HashMap<u32, Value>,
    blocks: HashMap<u32, Block>,
    stack_slots: HashMap<u32, StackSlot>,
}

impl<'a> BodyCtx<'a> {
    fn new(f: &'a mut cranelift_codegen::ir::Function, fctx: &'a mut FunctionBuilderContext) -> Self {
        Self { builder: FunctionBuilder::new(f, fctx), values: HashMap::new(), blocks: HashMap::new(), stack_slots: HashMap::new() }
    }

    fn bind(&mut self, id: u32, v: Value) -> Result<(), MoonliftError> {
        if self.values.insert(id, v).is_some() { return Err(MoonliftError(format!("value {id} rebound"))); }
        Ok(())
    }

    fn val(&self, id: u32) -> Result<Value, MoonliftError> {
        self.values.get(&id).copied().ok_or_else(|| MoonliftError(format!("unknown value {id}")))
    }

    fn blk(&self, id: u32) -> Result<Block, MoonliftError> {
        self.blocks.get(&id).copied().ok_or_else(|| MoonliftError(format!("unknown block {id}")))
    }

    fn slot(&self, id: u32) -> Result<StackSlot, MoonliftError> {
        self.stack_slots.get(&id).copied().ok_or_else(|| MoonliftError(format!("unknown slot {id}")))
    }

    fn finalize(mut self) {
        self.builder.seal_all_blocks();
        self.builder.finalize();
    }
}

struct FuncRefs {
    func_refs: HashMap<u32, FuncRef>,
    extern_refs: HashMap<u32, FuncRef>,
    data_gvs: HashMap<u32, GlobalValue>,
    sigs: HashMap<u32, Signature>,
}

/// Create a FuncRef for a LibCall by importing the signature and function into the builder.
fn libcall_funcref(bctx: &mut FunctionBuilder, libcall: cranelift_codegen::ir::LibCall, sig_params: Vec<Type>, sig_returns: Vec<Type>) -> FuncRef {
    use cranelift_codegen::ir::ExtFuncData;
    let mut sig = cranelift_codegen::ir::Signature::new(bctx.func.signature.call_conv);
    for t in sig_params { sig.params.push(AbiParam::new(t)); }
    for t in sig_returns { sig.returns.push(AbiParam::new(t)); }
    let sig_ref = bctx.import_signature(sig);
    let ext = ExtFuncData {
        name: cranelift_codegen::ir::ExternalName::LibCall(libcall),
        signature: sig_ref,
        colocated: false,
        patchable: false,
    };
    bctx.import_function(ext)
}

fn precompute_refs(f: &mut cranelift_codegen::ir::Function, module: &mut impl Module, state: &ModuleState) -> FuncRefs {
    let mut fr = HashMap::new();
    let mut er = HashMap::new();
    let mut dg = HashMap::new();
    for (&wid, &(fid, _, _)) in &state.funcs { fr.insert(wid, module.declare_func_in_func(fid, f)); }
    for (&wid, &fid) in &state.externs { er.insert(wid, module.declare_func_in_func(fid, f)); }
    for (&wid, &did) in &state.datas { dg.insert(wid, module.declare_data_in_func(did, f)); }
    FuncRefs { func_refs: fr, extern_refs: er, data_gvs: dg, sigs: state.sigs.clone() }
}

fn decode_body(buf: &[u8], ptr_ty: Type, ctx: &mut BodyCtx<'_>, refs: &FuncRefs) -> Result<(), MoonliftError> {
    let mut pos = 0usize;
    while pos < buf.len() {
        let tag = read_u32(buf, &mut pos)?;
        if tag == 0 || tag >= 256 { return Err(MoonliftError(format!("bad wire tag {tag}"))); }
        let nf = TAG_SLOTS[tag as usize] as usize;
        let s = read_slots(buf, &mut pos, nf)?;

        macro_rules! binop {
            ($dst:expr, $lhs:expr, $rhs:expr, $op:ident) => {{
                let l = ctx.val(s[$lhs])?;
                let r = ctx.val(s[$rhs])?;
                let v = ctx.builder.ins().$op(l, r);
                ctx.bind(s[$dst], v)?;
            }};
        }
        macro_rules! binop_cc {
            ($dst:expr, $lhs:expr, $rhs:expr, $cc:expr) => {{
                let l = ctx.val(s[$lhs])?;
                let r = ctx.val(s[$rhs])?;
                let v = ctx.builder.ins().icmp($cc, l, r);
                ctx.bind(s[$dst], v)?;
            }};
        }
        macro_rules! unop {
            ($dst:expr, $src:expr, $op:ident) => {{
                let v = ctx.val(s[$src])?;
                let r = ctx.builder.ins().$op(v);
                ctx.bind(s[$dst], r)?;
            }};
        }

        match tag as u32 {
            // Structural
            t if t == WireTag::CreateBlock as u32 => {
                let b = ctx.builder.create_block();
                if ctx.blocks.insert(s[0], b).is_some() { return Err(MoonliftError(format!("block {} dup", s[0]))); }
            }
            t if t == WireTag::SwitchToBlock as u32 => ctx.builder.switch_to_block(ctx.blk(s[0])?),
            t if t == WireTag::AppendBlockParam as u32 => {
                let b = ctx.blk(s[0])?;
                let ty = st(s[1], ptr_ty)?;
                let v = ctx.builder.append_block_param(b, ty);
                ctx.bind(s[2], v)?;
            }
            t if t == WireTag::AppendBlockParamVec as u32 => {
                let b = ctx.blk(s[0])?;
                let elem_ty = st(s[1], ptr_ty)?;
                let lanes = s[2];
                let ty = elem_ty.by(lanes).ok_or_else(|| MoonliftError(format!("bad block param vector {elem_ty:?}x{lanes}")))?;
                let v = ctx.builder.append_block_param(b, ty);
                ctx.bind(s[3], v)?;
            }
            t if t == WireTag::CreateStackSlot as u32 => {
                let ss = ctx.builder.create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, s[1], s[2] as u8));
                if ctx.stack_slots.insert(s[0], ss).is_some() { return Err(MoonliftError(format!("slot {} dup", s[0]))); }
            }

            // Constants — no ctx.val() needed
            t if t == WireTag::ConstI32 as u32 => { let v = ctx.builder.ins().iconst(types::I32, s[1] as i64); ctx.bind(s[0], v)?; }
            t if t == WireTag::ConstI64 as u32 => { let imm = (s[1] as i64) | ((s[2] as i64) << 32); let v = ctx.builder.ins().iconst(types::I64, imm); ctx.bind(s[0], v)?; }
            t if t == WireTag::ConstF32 as u32 => { let v = ctx.builder.ins().f32const(Ieee32::with_bits(s[1])); ctx.bind(s[0], v)?; }
            t if t == WireTag::ConstF64 as u32 => { let bits = (s[1] as u64) | ((s[2] as u64) << 32); let v = ctx.builder.ins().f64const(Ieee64::with_bits(bits)); ctx.bind(s[0], v)?; }
            t if t == WireTag::ConstBool as u32 => { let v = ctx.builder.ins().iconst(types::I8, if s[1] != 0 { 1 } else { 0 }); ctx.bind(s[0], v)?; }
            t if t == WireTag::ConstNull as u32 => { let v = ctx.builder.ins().iconst(ptr_ty, 0); ctx.bind(s[0], v)?; }
            t if t == WireTag::ConstInt as u32 => { let ty = st(s[1], ptr_ty)?; let imm = (s[2] as i64) | ((s[3] as i64) << 32); let v = ctx.builder.ins().iconst(ty, imm); ctx.bind(s[0], v)?; }

            // Integer binary
            t if t == WireTag::Iadd as u32 => binop!(0, 1, 2, iadd),
            t if t == WireTag::Isub as u32 => binop!(0, 1, 2, isub),
            t if t == WireTag::Imul as u32 => binop!(0, 1, 2, imul),
            t if t == WireTag::Sdiv as u32 => binop!(0, 1, 2, sdiv),
            t if t == WireTag::Udiv as u32 => binop!(0, 1, 2, udiv),
            t if t == WireTag::Srem as u32 => binop!(0, 1, 2, srem),
            t if t == WireTag::Urem as u32 => binop!(0, 1, 2, urem),
            t if t == WireTag::Ineg as u32 => unop!(0, 1, ineg),

            // Float arithmetic
            t if t == WireTag::Fadd as u32 => binop!(0, 1, 2, fadd),
            t if t == WireTag::Fsub as u32 => binop!(0, 1, 2, fsub),
            t if t == WireTag::Fmul as u32 => binop!(0, 1, 2, fmul),
            t if t == WireTag::Fdiv as u32 => binop!(0, 1, 2, fdiv),
            t if t == WireTag::Fneg as u32 => unop!(0, 1, fneg),
            t if t == WireTag::Fabs as u32 => unop!(0, 1, fabs),
            t if t == WireTag::Fma as u32 => { let a = ctx.val(s[1])?; let b = ctx.val(s[2])?; let c = ctx.val(s[3])?; let v = ctx.builder.ins().fma(a, b, c); ctx.bind(s[0], v)?; }
            t if t == WireTag::Sqrt as u32 => unop!(0, 1, sqrt),
            t if t == WireTag::Floor as u32 => unop!(0, 1, floor),
            t if t == WireTag::Ceil as u32 => unop!(0, 1, ceil),
            t if t == WireTag::Trunc as u32 => unop!(0, 1, trunc),
            t if t == WireTag::Nearest as u32 => unop!(0, 1, nearest),

            // Bitwise
            t if t == WireTag::Band as u32 => binop!(0, 1, 2, band),
            t if t == WireTag::Bor as u32 => binop!(0, 1, 2, bor),
            t if t == WireTag::Bxor as u32 => binop!(0, 1, 2, bxor),
            t if t == WireTag::Bnot as u32 => unop!(0, 1, bnot),

            // Shift / Rotate
            t if t == WireTag::Ishl as u32 => binop!(0, 1, 2, ishl),
            t if t == WireTag::Ushr as u32 => binop!(0, 1, 2, ushr),
            t if t == WireTag::Sshr as u32 => binop!(0, 1, 2, sshr),
            t if t == WireTag::Rotl as u32 => binop!(0, 1, 2, rotl),
            t if t == WireTag::Rotr as u32 => binop!(0, 1, 2, rotr),

            // Compare
            t if t == WireTag::Icmp as u32 => {
                let cc = icc(s[1])?; let l = ctx.val(s[2])?; let r = ctx.val(s[3])?;
                let cond = ctx.builder.ins().icmp(cc, l, r);
                let bv = bfc(&mut ctx.builder, cond);
                ctx.bind(s[0], bv)?;
            }
            t if t == WireTag::Fcmp as u32 => {
                let cc = fcc(s[1])?; let l = ctx.val(s[2])?; let r = ctx.val(s[3])?;
                let cond = ctx.builder.ins().fcmp(cc, l, r);
                let bv = bfc(&mut ctx.builder, cond);
                ctx.bind(s[0], bv)?;
            }

            // Cast
            t if t == WireTag::Bitcast as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().bitcast(ty, MemFlags::new(), v); ctx.bind(s[0], r)?; }
            t if t == WireTag::Ireduce as u32 => {
                let ty = st(s[1], ptr_ty)?;
                let v = ctx.val(s[2])?;
                let src_ty = ctx.builder.func.dfg.value_type(v);
                let r = if src_ty == ty { v } else { ctx.builder.ins().ireduce(ty, v) };
                ctx.bind(s[0], r)?;
            }
            t if t == WireTag::Sextend as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().sextend(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::Uextend as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().uextend(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::Fpromote as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().fpromote(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::Fdemote as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().fdemote(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::FcvtFromSint as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().fcvt_from_sint(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::FcvtFromUint as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().fcvt_from_uint(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::FcvtToSint as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().fcvt_to_sint(ty, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::FcvtToUint as u32 => { let ty = st(s[1], ptr_ty)?; let v = ctx.val(s[2])?; let r = ctx.builder.ins().fcvt_to_uint(ty, v); ctx.bind(s[0], r)?; }

            // Intrinsics
            t if t == WireTag::Popcnt as u32 => unop!(0, 1, popcnt),
            t if t == WireTag::Clz as u32 => unop!(0, 1, clz),
            t if t == WireTag::Ctz as u32 => unop!(0, 1, ctz),
            t if t == WireTag::Bswap as u32 => unop!(0, 1, bswap),
            t if t == WireTag::Iabs as u32 => unop!(0, 1, iabs),

            // Address ops
            t if t == WireTag::StackAddr as u32 => { let ty = st(s[1], ptr_ty)?; let sl = ctx.slot(s[2])?; let v = ctx.builder.ins().stack_addr(ty, sl, 0); ctx.bind(s[0], v)?; }
            t if t == WireTag::GlobalValue as u32 => { let ty = st(s[1], ptr_ty)?; let gv = refs.data_gvs.get(&s[2]).copied().ok_or_else(|| MoonliftError(format!("unknown data {}", s[2])))?; let v = ctx.builder.ins().global_value(ty, gv); ctx.bind(s[0], v)?; }
            t if t == WireTag::FuncAddr as u32 => { let ty = st(s[1], ptr_ty)?; let fr = refs.func_refs.get(&s[2]).copied().ok_or_else(|| MoonliftError(format!("unknown func {}", s[2])))?; let v = ctx.builder.ins().func_addr(ty, fr); ctx.bind(s[0], v)?; }
            t if t == WireTag::ExternAddr as u32 => { let ty = st(s[1], ptr_ty)?; let fr = refs.extern_refs.get(&s[2]).copied().ok_or_else(|| MoonliftError(format!("unknown extern {}", s[2])))?; let v = ctx.builder.ins().func_addr(ty, fr); ctx.bind(s[0], v)?; }

            // Memory
            t if t == WireTag::Load as u32 => { let ty = st(s[1], ptr_ty)?; let fl = mf(s[2]); let a = ctx.val(s[3])?; let v = ctx.builder.ins().load(ty, fl, a, 0); ctx.bind(s[0], v)?; }
            t if t == WireTag::Store as u32 => { let fl = mf(s[1]); let a = ctx.val(s[2])?; let v = ctx.val(s[3])?; ctx.builder.ins().store(fl, v, a, 0); }
            t if t == WireTag::AtomicLoad as u32 => { let ty = st(s[1], ptr_ty)?; let fl = mf(s[2]); let a = ctx.val(s[3])?; let v = ctx.builder.ins().atomic_load(ty, fl, a); ctx.bind(s[0], v)?; }
            t if t == WireTag::AtomicStore as u32 => { let fl = mf(s[1]); let a = ctx.val(s[2])?; let v = ctx.val(s[3])?; ctx.builder.ins().atomic_store(fl, v, a); }
            t if t == WireTag::AtomicRmw as u32 => { let ty = st(s[1], ptr_ty)?; let op = rmw(s[2])?; let fl = mf(s[3]); let a = ctx.val(s[4])?; let v = ctx.val(s[5])?; let r = ctx.builder.ins().atomic_rmw(ty, fl, op, a, v); ctx.bind(s[0], r)?; }
            t if t == WireTag::AtomicCas as u32 => { let fl = mf(s[2]); let a = ctx.val(s[3])?; let e = ctx.val(s[4])?; let r = ctx.val(s[5])?; let v = ctx.builder.ins().atomic_cas(fl, a, e, r); ctx.bind(s[0], v)?; }
            t if t == WireTag::Fence as u32 => { ctx.builder.ins().fence(); }

            // Pointer
            t if t == WireTag::PtrAdd as u32 => binop!(0, 1, 2, iadd),
            t if t == WireTag::PtrOffset as u32 => {
                let base = ctx.val(s[1])?; let idx = ctx.val(s[2])?;
                let es = s[3] as i64; let coff = (s[4] as i64) | ((s[5] as i64) << 32);
                let ev = ctx.builder.ins().iconst(ptr_ty, es);
                let sc = ctx.builder.ins().imul(idx, ev);
                let total = if coff == 0 { sc } else { let cv = ctx.builder.ins().iconst(ptr_ty, coff); ctx.builder.ins().iadd(sc, cv) };
                let result = ctx.builder.ins().iadd(base, total);
                ctx.bind(s[0], result)?;
            }

            // Vector
            t if t == WireTag::Splat as u32 => { let lt = st(s[1], ptr_ty)?; let ln = s[2] as u32; let src = ctx.val(s[3])?; let r = ctx.builder.ins().splat(lt.by(ln).unwrap(), src); ctx.bind(s[0], r)?; }
            t if t == WireTag::InsertLane as u32 => { let vec = ctx.val(s[1])?; let lv = ctx.val(s[2])?; let r = ctx.builder.ins().insertlane(vec, lv, s[3] as u8); ctx.bind(s[0], r)?; }
            t if t == WireTag::ExtractLane as u32 => { let vec = ctx.val(s[2])?; let r = ctx.builder.ins().extractlane(vec, s[3] as u8); ctx.bind(s[0], r)?; }
            t if t == WireTag::VecIadd as u32 => binop!(0, 1, 2, iadd),
            t if t == WireTag::VecIsub as u32 => binop!(0, 1, 2, isub),
            t if t == WireTag::VecImul as u32 => binop!(0, 1, 2, imul),
            t if t == WireTag::VecBand as u32 => binop!(0, 1, 2, band),
            t if t == WireTag::VecBor as u32 => binop!(0, 1, 2, bor),
            t if t == WireTag::VecBxor as u32 => binop!(0, 1, 2, bxor),
            t if t == WireTag::VecIcmpEq as u32 => binop_cc!(0, 1, 2, IntCC::Equal),
            t if t == WireTag::VecIcmpNe as u32 => binop_cc!(0, 1, 2, IntCC::NotEqual),
            t if t == WireTag::VecSIcmpLt as u32 => binop_cc!(0, 1, 2, IntCC::SignedLessThan),
            t if t == WireTag::VecSIcmpLe as u32 => binop_cc!(0, 1, 2, IntCC::SignedLessThanOrEqual),
            t if t == WireTag::VecSIcmpGt as u32 => binop_cc!(0, 1, 2, IntCC::SignedGreaterThan),
            t if t == WireTag::VecSIcmpGe as u32 => binop_cc!(0, 1, 2, IntCC::SignedGreaterThanOrEqual),
            t if t == WireTag::VecUIcmpLt as u32 => binop_cc!(0, 1, 2, IntCC::UnsignedLessThan),
            t if t == WireTag::VecUIcmpLe as u32 => binop_cc!(0, 1, 2, IntCC::UnsignedLessThanOrEqual),
            t if t == WireTag::VecUIcmpGt as u32 => binop_cc!(0, 1, 2, IntCC::UnsignedGreaterThan),
            t if t == WireTag::VecUIcmpGe as u32 => binop_cc!(0, 1, 2, IntCC::UnsignedGreaterThanOrEqual),
            t if t == WireTag::VecSelect as u32 => {
                let mask = ctx.val(s[1])?; let tv = ctx.val(s[2])?; let ev = ctx.val(s[3])?;
                let mt = ctx.builder.ins().band(mask, tv);
                let nm = ctx.builder.ins().bnot(mask);
                let me = ctx.builder.ins().band(nm, ev);
                let result = ctx.builder.ins().bor(mt, me);
                ctx.bind(s[0], result)?;
            }
            t if t == WireTag::VecMaskNot as u32 => unop!(0, 1, bnot),
            t if t == WireTag::VecMaskAnd as u32 => binop!(0, 1, 2, band),
            t if t == WireTag::VecMaskOr as u32 => binop!(0, 1, 2, bor),
            t if t == WireTag::VecLoad as u32 => {
                let lt = st(s[1], ptr_ty)?; let ln = s[2] as usize; let fl = mf(s[3]); let a = ctx.val(s[4])?;
                let vt = lt.by(ln as u32).ok_or_else(|| MoonliftError(format!("bad vec {lt:?}x{ln}")))?;
                let result = ctx.builder.ins().load(vt, fl, a, 0);
                ctx.bind(s[0], result)?;
            }
            t if t == WireTag::VecStore as u32 => { let fl = mf(s[2]); let a = ctx.val(s[3])?; let v = ctx.val(s[4])?; ctx.builder.ins().store(fl, v, a, 0); }

            // Select
            t if t == WireTag::Select as u32 => {
                let cond_v = ctx.val(s[1])?;
                let cond = ctx.builder.ins().icmp_imm(IntCC::NotEqual, cond_v, 0);
                let tv = ctx.val(s[2])?; let ev = ctx.val(s[3])?;
                let result = ctx.builder.ins().select(cond, tv, ev);
                ctx.bind(s[0], result)?;
            }

            // Control flow
            t if t == WireTag::Jump as u32 => {
                let dest = ctx.blk(s[0])?; let na = s[1] as usize;
                let ids = read_slots(buf, &mut pos, na)?;
                let args: Vec<BlockArg> = ids.iter().map(|&id| ctx.val(id).map(BlockArg::Value)).collect::<Result<_,_>>()?;
                ctx.builder.ins().jump(dest, &args);
            }
            t if t == WireTag::Brif as u32 => {
                let cv = ctx.val(s[0])?;
                let cond = ctx.builder.ins().icmp_imm(IntCC::NotEqual, cv, 0);
                let tb = ctx.blk(s[1])?;
                let tn = read_u32(buf, &mut pos)? as usize;
                let ta = read_slots(buf, &mut pos, tn)?;
                let eid = read_u32(buf, &mut pos)?;
                let eb = ctx.blk(eid)?;
                let en = read_u32(buf, &mut pos)? as usize;
                let ea = read_slots(buf, &mut pos, en)?;
                let t_args: Vec<BlockArg> = ta.iter().map(|&id| ctx.val(id).map(BlockArg::Value)).collect::<Result<_,_>>()?;
                let e_args: Vec<BlockArg> = ea.iter().map(|&id| ctx.val(id).map(BlockArg::Value)).collect::<Result<_,_>>()?;
                ctx.builder.ins().brif(cond, tb, &t_args, eb, &e_args);
            }
            t if t == WireTag::SwitchInt as u32 => {
                let val = ctx.val(s[0])?;
                let nc = s[2] as usize;
                let def_id = read_u32(buf, &mut pos)?;
                let def_blk = ctx.blk(def_id)?;
                let mut sw = Switch::new();
                for _ in 0..nc {
                    let clo = read_u32(buf, &mut pos)?;
                    let chi = read_u32(buf, &mut pos)?;
                    let did = read_u32(buf, &mut pos)?;
                    let cv = (clo as u64) | ((chi as u64) << 32);
                    sw.set_entry(cv as u128, ctx.blk(did)?);
                }
                sw.emit(&mut ctx.builder, val, def_blk);
            }
            t if t == WireTag::ReturnVoid as u32 => { ctx.builder.ins().return_(&[]); }
            t if t == WireTag::ReturnValue as u32 => { let v = ctx.val(s[0])?; ctx.builder.ins().return_(&[v]); }
            t if t == WireTag::Trap as u32 => { ctx.builder.ins().trap(TrapCode::unwrap_user(1)); }

            // Call
            t if t == WireTag::CallDirect as u32 => {
                let rt = s[0]; let fid = s[3]; let na = read_u32(buf, &mut pos)? as usize;
                let ids = read_slots(buf, &mut pos, na)?;
                let fr = refs.func_refs.get(&fid).copied().ok_or_else(|| MoonliftError(format!("unknown func {fid}")))?;
                let args: Vec<Value> = ids.iter().map(|&id| ctx.val(id)).collect::<Result<_,_>>()?;
                let inst = ctx.builder.ins().call(fr, &args);
                if rt == 1 { ctx.bind(s[1], ctx.builder.inst_results(inst)[0])?; }
            }
            t if t == WireTag::CallExtern as u32 => {
                let rt = s[0]; let eid = s[3]; let na = read_u32(buf, &mut pos)? as usize;
                let ids = read_slots(buf, &mut pos, na)?;
                let fr = refs.extern_refs.get(&eid).copied().ok_or_else(|| MoonliftError(format!("unknown extern {eid}")))?;
                let args: Vec<Value> = ids.iter().map(|&id| ctx.val(id)).collect::<Result<_,_>>()?;
                let inst = ctx.builder.ins().call(fr, &args);
                if rt == 1 { ctx.bind(s[1], ctx.builder.inst_results(inst)[0])?; }
            }
            t if t == WireTag::CallIndirect as u32 => {
                let rt = s[0]; let callee = ctx.val(s[3])?; let sig_id = s[4]; let na = read_u32(buf, &mut pos)? as usize;
                let ids = read_slots(buf, &mut pos, na)?;
                let args: Vec<Value> = ids.iter().map(|&id| ctx.val(id)).collect::<Result<_,_>>()?;
                let sig = refs.sigs.get(&sig_id).cloned().unwrap_or_else(|| Signature::new(ctx.builder.func.signature.call_conv));
                let sig_ref = ctx.builder.import_signature(sig);
                let inst = ctx.builder.ins().call_indirect(sig_ref, callee, &args);
                if rt == 1 { if let Some(&r) = ctx.builder.inst_results(inst).first() { ctx.bind(s[1], r)?; } }
            }

            // Singleton ops
            t if t == WireTag::Alias as u32 => { let v = ctx.val(s[1])?; ctx.bind(s[0], v)?; }
            t if t == WireTag::BoolNot as u32 => { let v = ctx.val(s[1])?; let cond = ctx.builder.ins().icmp_imm(IntCC::Equal, v, 0); let bv = bfc(&mut ctx.builder, cond); ctx.bind(s[0], bv)?; }

            // Memcpy: 3 slots [dst_ptr, src_ptr, len] — all inputs, side-effect only
            // Uses LibCall::Memcpy which Cranelift resolves to libc memcpy (or JIT symbol override)
            t if t == WireTag::Memcpy as u32 => {
                let dst = ctx.val(s[0])?;
                let src = ctx.val(s[1])?;
                let len = ctx.val(s[2])?;
                let ptr_ty = types::I64;
                let fr = libcall_funcref(&mut ctx.builder, cranelift_codegen::ir::LibCall::Memcpy,
                    vec![ptr_ty, ptr_ty, ptr_ty], vec![ptr_ty]);
                ctx.builder.ins().call(fr, &[dst, src, len]);
            }
            // Memset: 3 slots [dst_ptr, byte_val, len] — all inputs
            // byte_val may be i8/u8; extend to i32 for the libcall
            t if t == WireTag::Memset as u32 => {
                let dst = ctx.val(s[0])?;
                let byte = ctx.val(s[1])?;
                let byte_i32 = if ctx.builder.func.dfg.value_type(byte) == types::I8 {
                    ctx.builder.ins().uextend(types::I32, byte)
                } else { byte };
                let len = ctx.val(s[2])?;
                let ptr_ty = types::I64;
                let fr = libcall_funcref(&mut ctx.builder, cranelift_codegen::ir::LibCall::Memset,
                    vec![ptr_ty, types::I32, ptr_ty], vec![ptr_ty]);
                ctx.builder.ins().call(fr, &[dst, byte_i32, len]);
            }
            // Memcmp: 4 slots [dst_out, left, right, len]
            t if t == WireTag::Memcmp as u32 => {
                let left = ctx.val(s[1])?;
                let right = ctx.val(s[2])?;
                let len = ctx.val(s[3])?;
                let ptr_ty = types::I64;
                let fr = libcall_funcref(&mut ctx.builder, cranelift_codegen::ir::LibCall::Memcmp,
                    vec![ptr_ty, ptr_ty, ptr_ty], vec![types::I32]);
                let call = ctx.builder.ins().call(fr, &[left, right, len]);
                ctx.bind(s[0], ctx.builder.inst_results(call)[0])?;
            }

            _ => return Err(MoonliftError(format!("unhandled wire tag {tag}"))),
        }
    }
    Ok(())
}

pub struct DecodeResult {
    pub func_table: HashMap<u32, (FuncId, String)>,
}

pub fn decode_module<M: Module>(buf: &[u8], module: &mut M) -> Result<DecodeResult, MoonliftError> {
    let mut pos = 0;
    let hdr = read_header(buf, &mut pos)?;
    let decl_end = hdr.decl_offset + hdr.decl_len;
    let state = read_declarations(buf, &mut pos, decl_end, module)?;
    let bodies = read_body_table(buf, &hdr)?;
    let ptr_ty = module.target_config().pointer_type();
    let mut fctx = FunctionBuilderContext::new();

    for (wire_fid, body_off, body_len) in &bodies {
        if *body_len == 0 { continue; }
        let (cfid, _name, sig) = state.funcs.get(wire_fid)
            .map(|(f, n, s)| (*f, n.clone(), s.clone()))
            .ok_or_else(|| MoonliftError(format!("body references undeclared func {wire_fid}")))?;
        if *body_off + *body_len > buf.len() {
            return Err(MoonliftError(format!("body for func {wire_fid} overflows")));
        }
        let bb = &buf[*body_off..*body_off + *body_len];
        let mut ctx = module.make_context();
        ctx.func.name = UserFuncName::user(0, cfid.as_u32());
        ctx.func.signature = sig.clone();
        let refs = precompute_refs(&mut ctx.func, module, &state);
        {
            let mut bctx = BodyCtx::new(&mut ctx.func, &mut fctx);
            decode_body(bb, ptr_ty, &mut bctx, &refs)?;
            bctx.finalize();
        }
        module.define_function(cfid, &mut ctx)
            .map_err(|e| MoonliftError(format!("define func {wire_fid}: {e:?}")))?;
        module.clear_context(&mut ctx);
    }
    Ok(DecodeResult { func_table: state.funcs.into_iter().map(|(id, (fid, name, _))| (id, (fid, name))).collect() })
}
