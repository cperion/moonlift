use crate::{
    Artifact, BackAccessId, BackAccessMode, BackAlignment, BackAtomicOrdering, BackAtomicRmwOp,
    BackBlockId, BackCmd, BackDataId, BackDereference, BackExternId, BackFloatSemantics,
    BackFuncId, BackIntExact, BackIntOverflow, BackIntSemantics, BackMemoryInfo, BackMotion,
    BackProgram, BackScalar, BackSigId, BackStackSlotId, BackSwitchCase, BackTrap, BackValId,
    BackVec, Jit, MoonliftError, compile_object,
};
use crate::host_arena::{HostSession, MoonHostFieldInit, MoonHostPtr, MoonHostRecordSpec, MoonHostRef};
use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;
use std::sync::LazyLock;

#[repr(C)]
pub struct moonlift_jit_t {
    inner: Jit,
}

#[repr(C)]
pub struct moonlift_artifact_t {
    inner: Artifact,
}

#[repr(C)]
pub struct moonlift_bytes_t {
    data: *mut u8,
    len: usize,
}

#[repr(C)]
pub struct moonlift_host_session_t {
    inner: HostSession,
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::new("ok").expect("valid CString"));
}

fn set_last_error(message: impl Into<String>) {
    let mut text = message.into();
    if text.as_bytes().contains(&0) {
        text = text.replace('\0', "?");
    }
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = CString::new(text).unwrap_or_else(|_| CString::new("moonlift ffi error").unwrap());
    });
}

fn clear_last_error() {
    set_last_error("ok");
}

fn fail_ptr<T>(message: impl Into<String>) -> *mut T {
    set_last_error(message);
    ptr::null_mut()
}

fn fail_const_ptr<T>(message: impl Into<String>) -> *const T {
    set_last_error(message);
    ptr::null()
}

fn fail_int(message: impl Into<String>) -> c_int {
    set_last_error(message);
    0
}

fn ok_int() -> c_int {
    clear_last_error();
    1
}

fn require_ptr<'a, T>(ptr: *mut T, what: &str) -> Result<&'a mut T, MoonliftError> {
    unsafe { ptr.as_mut() }.ok_or_else(|| MoonliftError(format!("{what} pointer was null")))
}

fn read_cstr(ptr: *const c_char, what: &str) -> Result<String, MoonliftError> {
    if ptr.is_null() {
        return Err(MoonliftError(format!("{what} string pointer was null")));
    }
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| MoonliftError(format!("{what} was not valid UTF-8: {e}")))?;
    Ok(text.to_string())
}

fn read_scalar(code: u32) -> Result<BackScalar, MoonliftError> {
    match code {
        1 => Ok(BackScalar::Bool),
        2 => Ok(BackScalar::I8),
        3 => Ok(BackScalar::I16),
        4 => Ok(BackScalar::I32),
        5 => Ok(BackScalar::I64),
        6 => Ok(BackScalar::U8),
        7 => Ok(BackScalar::U16),
        8 => Ok(BackScalar::U32),
        9 => Ok(BackScalar::U64),
        10 => Ok(BackScalar::F32),
        11 => Ok(BackScalar::F64),
        12 => Ok(BackScalar::Ptr),
        13 => Ok(BackScalar::Index),
        _ => Err(MoonliftError(format!("unknown BackScalar code {code}"))),
    }
}

fn read_int_overflow(kind: u32) -> Result<BackIntOverflow, MoonliftError> {
    match kind {
        0 => Ok(BackIntOverflow::Wrap),
        1 => Ok(BackIntOverflow::NoSignedWrap),
        2 => Ok(BackIntOverflow::NoUnsignedWrap),
        3 => Ok(BackIntOverflow::NoWrap),
        _ => Err(MoonliftError(format!("unknown BackIntOverflow kind {kind}"))),
    }
}

fn read_int_exact(kind: u32) -> Result<BackIntExact, MoonliftError> {
    match kind {
        0 => Ok(BackIntExact::MayLose),
        1 => Ok(BackIntExact::Exact),
        _ => Err(MoonliftError(format!("unknown BackIntExact kind {kind}"))),
    }
}

fn read_int_semantics(overflow_kind: u32, exact_kind: u32) -> Result<BackIntSemantics, MoonliftError> {
    Ok(BackIntSemantics::new(read_int_overflow(overflow_kind)?, read_int_exact(exact_kind)?))
}

fn read_float_semantics(kind: u32) -> Result<BackFloatSemantics, MoonliftError> {
    match kind {
        0 => Ok(BackFloatSemantics::Strict),
        1 => Ok(BackFloatSemantics::FastMath),
        _ => Err(MoonliftError(format!("unknown BackFloatSemantics kind {kind}"))),
    }
}

fn read_alignment(kind: u32, bytes: u32) -> Result<BackAlignment, MoonliftError> {
    match kind {
        0 => Ok(BackAlignment::Unknown),
        1 => Ok(BackAlignment::Known(bytes)),
        2 => Ok(BackAlignment::AtLeast(bytes)),
        3 => Ok(BackAlignment::Assumed(bytes)),
        _ => Err(MoonliftError(format!("unknown BackAlignment kind {kind}"))),
    }
}

fn read_dereference(kind: u32, bytes: u32) -> Result<BackDereference, MoonliftError> {
    match kind {
        0 => Ok(BackDereference::Unknown),
        1 => Ok(BackDereference::Bytes(bytes)),
        2 => Ok(BackDereference::Assumed(bytes)),
        _ => Err(MoonliftError(format!("unknown BackDereference kind {kind}"))),
    }
}

fn read_trap(kind: u32) -> Result<BackTrap, MoonliftError> {
    match kind {
        0 => Ok(BackTrap::MayTrap),
        1 => Ok(BackTrap::NonTrapping),
        2 => Ok(BackTrap::Checked),
        _ => Err(MoonliftError(format!("unknown BackTrap kind {kind}"))),
    }
}

fn read_motion(kind: u32) -> Result<BackMotion, MoonliftError> {
    match kind {
        0 => Ok(BackMotion::MayNotMove),
        1 => Ok(BackMotion::CanMove),
        _ => Err(MoonliftError(format!("unknown BackMotion kind {kind}"))),
    }
}

fn read_access_mode(kind: u32) -> Result<BackAccessMode, MoonliftError> {
    match kind {
        1 => Ok(BackAccessMode::Read),
        2 => Ok(BackAccessMode::Write),
        3 => Ok(BackAccessMode::ReadWrite),
        _ => Err(MoonliftError(format!("unknown BackAccessMode kind {kind}"))),
    }
}

fn read_atomic_ordering(text: &str) -> Result<BackAtomicOrdering, MoonliftError> {
    match text {
        "BackAtomicSeqCst" => Ok(BackAtomicOrdering::SeqCst),
        other => Err(MoonliftError(format!("unknown BackAtomicOrdering {other}"))),
    }
}

fn read_atomic_rmw_op(text: &str) -> Result<BackAtomicRmwOp, MoonliftError> {
    match text {
        "BackAtomicRmwAdd" => Ok(BackAtomicRmwOp::Add),
        "BackAtomicRmwSub" => Ok(BackAtomicRmwOp::Sub),
        "BackAtomicRmwAnd" => Ok(BackAtomicRmwOp::And),
        "BackAtomicRmwOr" => Ok(BackAtomicRmwOp::Or),
        "BackAtomicRmwXor" => Ok(BackAtomicRmwOp::Xor),
        "BackAtomicRmwXchg" => Ok(BackAtomicRmwOp::Xchg),
        other => Err(MoonliftError(format!("unknown BackAtomicRmwOp {other}"))),
    }
}

fn tape_unescape(text: &str) -> Result<String, MoonliftError> {
    let mut out = String::new();
    let mut chars = text.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
            continue;
        }
        match chars.next() {
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('\\') => out.push('\\'),
            Some(other) => return Err(MoonliftError(format!("invalid tape escape \\{other}"))),
            None => return Err(MoonliftError("unterminated tape escape".to_string())),
        }
    }
    Ok(out)
}

struct TapeLine {
    line: usize,
    fields: Vec<String>,
    pos: usize,
}

impl TapeLine {
    fn new(line: usize, raw: &str) -> Result<Self, MoonliftError> {
        let fields = raw.split('\t').map(tape_unescape).collect::<Result<Vec<_>, _>>()?;
        Ok(Self { line, fields, pos: 0 })
    }
    fn take(&mut self, what: &str) -> Result<String, MoonliftError> {
        let value = self.fields.get(self.pos).cloned().ok_or_else(|| MoonliftError(format!("tape line {} missing {what}", self.line)))?;
        self.pos += 1;
        Ok(value)
    }
    fn take_u32(&mut self, what: &str) -> Result<u32, MoonliftError> {
        self.take(what)?.parse::<u32>().map_err(|e| MoonliftError(format!("tape line {} invalid {what}: {e}", self.line)))
    }
    fn take_i64(&mut self, what: &str) -> Result<i64, MoonliftError> {
        self.take(what)?.parse::<i64>().map_err(|e| MoonliftError(format!("tape line {} invalid {what}: {e}", self.line)))
    }
    fn take_usize(&mut self, what: &str) -> Result<usize, MoonliftError> {
        self.take(what)?.parse::<usize>().map_err(|e| MoonliftError(format!("tape line {} invalid {what}: {e}", self.line)))
    }
    fn take_scalar(&mut self) -> Result<BackScalar, MoonliftError> { read_scalar(self.take_u32("scalar")?) }
    fn take_val(&mut self, what: &str) -> Result<BackValId, MoonliftError> { Ok(BackValId::from(self.take(what)?)) }
    fn take_vals(&mut self, what: &str) -> Result<Vec<BackValId>, MoonliftError> {
        let n = self.take_usize(&format!("{what} len"))?;
        let mut out = Vec::with_capacity(n);
        for i in 0..n { out.push(BackValId::from(self.take(&format!("{what}[{i}]"))?)); }
        Ok(out)
    }
    fn take_scalars(&mut self, what: &str) -> Result<Vec<BackScalar>, MoonliftError> {
        let n = self.take_usize(&format!("{what} len"))?;
        let mut out = Vec::with_capacity(n);
        for _ in 0..n { out.push(self.take_scalar()?); }
        Ok(out)
    }
    fn take_vec(&mut self) -> Result<BackVec, MoonliftError> {
        let elem = self.take_scalar()?;
        let lanes = self.take_u32("lanes")?;
        Ok(BackVec::new(elem, lanes))
    }
    fn take_shape(&mut self) -> Result<TapeShape, MoonliftError> {
        match self.take("shape kind")?.as_str() {
            "S" => Ok(TapeShape::Scalar(self.take_scalar()?)),
            "V" => Ok(TapeShape::Vec(self.take_vec()?)),
            other => Err(MoonliftError(format!("tape line {} invalid shape kind {other}", self.line))),
        }
    }
    fn take_memory(&mut self) -> Result<BackMemoryInfo, MoonliftError> {
        let access = BackAccessId::from(self.take("memory access")?);
        let ak = self.take_u32("alignment kind")?;
        let ab = self.take_u32("alignment bytes")?;
        let dk = self.take_u32("dereference kind")?;
        let db = self.take_u32("dereference bytes")?;
        let tk = self.take_u32("trap kind")?;
        let mk = self.take_u32("motion kind")?;
        let mode = self.take_u32("mode kind")?;
        Ok(BackMemoryInfo::new(access, read_alignment(ak, ab)?, read_dereference(dk, db)?, read_trap(tk)?, read_motion(mk)?, read_access_mode(mode)?))
    }
}

enum TapeShape { Scalar(BackScalar), Vec(BackVec) }

fn tape_base_cmds(line: &mut TapeLine, dst_prefix: &str, out: &mut Vec<BackCmd>) -> Result<BackValId, MoonliftError> {
    let kind = line.take("address base kind")?;
    let value = line.take("address base")?;
    match kind.as_str() {
        "V" => Ok(BackValId::from(value)),
        "S" => { let dst = BackValId::from(format!("{dst_prefix}:base")); out.push(BackCmd::StackAddr(dst.clone(), BackStackSlotId::from(value))); Ok(dst) }
        "D" => { let dst = BackValId::from(format!("{dst_prefix}:base")); out.push(BackCmd::DataAddr(dst.clone(), BackDataId::from(value))); Ok(dst) }
        other => Err(MoonliftError(format!("tape line {} invalid address base kind {other}", line.line))),
    }
}

fn tape_addr_cmds(line: &mut TapeLine, dst_prefix: &str, out: &mut Vec<BackCmd>) -> Result<BackValId, MoonliftError> {
    let base = tape_base_cmds(line, dst_prefix, out)?;
    let offset = line.take_val("byte offset")?;
    let dst = BackValId::from(format!("{dst_prefix}:addr"));
    out.push(BackCmd::PtrAdd(dst.clone(), base, offset));
    Ok(dst)
}

fn tape_int_op(op: &str, dst: BackValId, ty: BackScalar, sem: BackIntSemantics, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        "BackIntAdd" => Ok(BackCmd::Iadd(dst, ty, sem, lhs, rhs)),
        "BackIntSub" => Ok(BackCmd::Isub(dst, ty, sem, lhs, rhs)),
        "BackIntMul" => Ok(BackCmd::Imul(dst, ty, sem, lhs, rhs)),
        "BackIntSDiv" => Ok(BackCmd::Sdiv(dst, ty, sem, lhs, rhs)),
        "BackIntUDiv" => Ok(BackCmd::Udiv(dst, ty, sem, lhs, rhs)),
        "BackIntSRem" => Ok(BackCmd::Srem(dst, ty, sem, lhs, rhs)),
        "BackIntURem" => Ok(BackCmd::Urem(dst, ty, sem, lhs, rhs)),
        _ => Err(MoonliftError(format!("unsupported tape int op {op}"))),
    }
}

fn tape_float_op(op: &str, dst: BackValId, ty: BackScalar, sem: BackFloatSemantics, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        "BackFloatAdd" => Ok(BackCmd::Fadd(dst, ty, sem, lhs, rhs)),
        "BackFloatSub" => Ok(BackCmd::Fsub(dst, ty, sem, lhs, rhs)),
        "BackFloatMul" => Ok(BackCmd::Fmul(dst, ty, sem, lhs, rhs)),
        "BackFloatDiv" => Ok(BackCmd::Fdiv(dst, ty, sem, lhs, rhs)),
        _ => Err(MoonliftError(format!("unsupported tape float op {op}"))),
    }
}

pub(crate) fn parse_back_command_tape(payload: &str) -> Result<Vec<BackCmd>, MoonliftError> {
    let mut lines = payload.lines();
    let Some(header) = lines.next() else { return Err(MoonliftError("empty BackCommandTape payload".to_string())); };
    if header != "moonlift-back-command-tape-v2" { return Err(MoonliftError(format!("unsupported BackCommandTape header {header}"))); }
    let mut out = Vec::new();
    for (line_no, raw) in lines.enumerate() {
        if raw.is_empty() { continue; }
        let mut line = TapeLine::new(line_no + 2, raw)?;
        let op = line.take("command")?;
        match op.as_str() {
            "CmdTargetModel" | "CmdAliasFact" => {}
            "CmdCreateSig" => { let sig = BackSigId::from(line.take("sig")?); let params = line.take_scalars("params")?; let results = line.take_scalars("results")?; out.push(BackCmd::CreateSig(sig, params, results)); }
            "CmdDeclareData" => out.push(BackCmd::DeclareData(BackDataId::from(line.take("data")?), line.take_u32("size")?, line.take_u32("align")?)),
            "CmdDataInitZero" => out.push(BackCmd::DataInitZero(BackDataId::from(line.take("data")?), line.take_u32("offset")?, line.take_u32("size")?)),
            "CmdDataInit" => { let data = BackDataId::from(line.take("data")?); let offset = line.take_u32("offset")?; let ty = line.take_scalar()?; let lit = line.take("literal kind")?; match lit.as_str() { "I" => out.push(BackCmd::DataInitInt(data, offset, ty, line.take("int literal")?)), "F" => out.push(BackCmd::DataInitFloat(data, offset, ty, line.take("float literal")?)), "B" => out.push(BackCmd::DataInitBool(data, offset, line.take("bool literal")? == "1")), "N" => out.push(BackCmd::DataInitZero(data, offset, ty.byte_size(8))), _ => return Err(MoonliftError(format!("unsupported tape data literal {lit}"))) } }
            "CmdDataAddr" => out.push(BackCmd::DataAddr(line.take_val("dst")?, BackDataId::from(line.take("data")?))),
            "CmdFuncAddr" => out.push(BackCmd::FuncAddr(line.take_val("dst")?, BackFuncId::from(line.take("func")?))),
            "CmdExternAddr" => out.push(BackCmd::ExternAddr(line.take_val("dst")?, BackExternId::from(line.take("extern")?))),
            "CmdDeclareFunc" => { let vis = line.take("visibility")?; let func = BackFuncId::from(line.take("func")?); let sig = BackSigId::from(line.take("sig")?); if vis == "E" { out.push(BackCmd::DeclareFuncExport(func, sig)); } else { out.push(BackCmd::DeclareFuncLocal(func, sig)); } }
            "CmdDeclareExtern" => out.push(BackCmd::DeclareFuncExtern(BackExternId::from(line.take("extern")?), line.take("symbol")?, BackSigId::from(line.take("sig")?))),
            "CmdBeginFunc" => out.push(BackCmd::BeginFunc(BackFuncId::from(line.take("func")?))),
            "CmdFinishFunc" => out.push(BackCmd::FinishFunc(BackFuncId::from(line.take("func")?))),
            "CmdCreateBlock" => out.push(BackCmd::CreateBlock(BackBlockId::from(line.take("block")?))),
            "CmdSwitchToBlock" => out.push(BackCmd::SwitchToBlock(BackBlockId::from(line.take("block")?))),
            "CmdSealBlock" => out.push(BackCmd::SealBlock(BackBlockId::from(line.take("block")?))),
            "CmdBindEntryParams" => { let block = BackBlockId::from(line.take("block")?); let vals = line.take_vals("entry params")?; out.push(BackCmd::BindEntryParams(block, vals)); }
            "CmdAppendBlockParam" => { let block = BackBlockId::from(line.take("block")?); let val = line.take_val("value")?; match line.take_shape()? { TapeShape::Scalar(s) => out.push(BackCmd::AppendBlockParam(block, val, s)), TapeShape::Vec(v) => out.push(BackCmd::AppendVecBlockParam(block, val, v)) } }
            "CmdCreateStackSlot" => out.push(BackCmd::CreateStackSlot(BackStackSlotId::from(line.take("slot")?), line.take_u32("size")?, line.take_u32("align")?)),
            "CmdAlias" => out.push(BackCmd::Alias(line.take_val("dst")?, line.take_val("src")?)),
            "CmdStackAddr" => out.push(BackCmd::StackAddr(line.take_val("dst")?, BackStackSlotId::from(line.take("slot")?))),
            "CmdConst" => { let dst = line.take_val("dst")?; let ty = line.take_scalar()?; let lit = line.take("literal kind")?; match lit.as_str() { "I" => out.push(BackCmd::ConstInt(dst, ty, line.take("int")?)), "F" => out.push(BackCmd::ConstFloat(dst, ty, line.take("float")?)), "B" => out.push(BackCmd::ConstBool(dst, line.take("bool")? == "1")), "N" => out.push(BackCmd::ConstNull(dst)), _ => return Err(MoonliftError(format!("unsupported tape const literal {lit}"))) } }
            "CmdUnary" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = match line.take_shape()? { TapeShape::Scalar(s) => s, TapeShape::Vec(_) => return Err(MoonliftError("CmdUnary vector shape unsupported in tape backend".to_string())) }; let v = line.take_val("value")?; out.push(match opk.as_str() { "BackUnaryIneg" => BackCmd::Ineg(dst, ty, v), "BackUnaryFneg" => BackCmd::Fneg(dst, ty, v), "BackUnaryBnot" => BackCmd::Bnot(dst, ty, v), "BackUnaryBoolNot" => BackCmd::BoolNot(dst, v), _ => return Err(MoonliftError(format!("unsupported unary op {opk}"))) }); }
            "CmdIntrinsic" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = match line.take_shape()? { TapeShape::Scalar(s) => s, TapeShape::Vec(_) => return Err(MoonliftError("CmdIntrinsic vector shape unsupported".to_string())) }; let args = line.take_vals("intrinsic args")?; let v = args[0].clone(); out.push(match opk.as_str() { "BackIntrinsicPopcount" => BackCmd::Popcount(dst, ty, v), "BackIntrinsicClz" => BackCmd::Clz(dst, ty, v), "BackIntrinsicCtz" => BackCmd::Ctz(dst, ty, v), "BackIntrinsicBswap" => BackCmd::Bswap(dst, ty, v), "BackIntrinsicSqrt" => BackCmd::Sqrt(dst, ty, v), "BackIntrinsicAbs" => BackCmd::Abs(dst, ty, v), "BackIntrinsicFloor" => BackCmd::Floor(dst, ty, v), "BackIntrinsicCeil" => BackCmd::Ceil(dst, ty, v), "BackIntrinsicTruncFloat" => BackCmd::TruncFloat(dst, ty, v), "BackIntrinsicRound" => BackCmd::Round(dst, ty, v), _ => return Err(MoonliftError(format!("unsupported intrinsic {opk}"))) }); }
            "CmdCompare" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = match line.take_shape()? { TapeShape::Scalar(s) => s, TapeShape::Vec(_) => return Err(MoonliftError("CmdCompare vector shape unsupported".to_string())) }; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(match opk.as_str() { "BackIcmpEq" => BackCmd::IcmpEq(dst, ty, lhs, rhs), "BackIcmpNe" => BackCmd::IcmpNe(dst, ty, lhs, rhs), "BackSIcmpLt" => BackCmd::SIcmpLt(dst, ty, lhs, rhs), "BackSIcmpLe" => BackCmd::SIcmpLe(dst, ty, lhs, rhs), "BackSIcmpGt" => BackCmd::SIcmpGt(dst, ty, lhs, rhs), "BackSIcmpGe" => BackCmd::SIcmpGe(dst, ty, lhs, rhs), "BackUIcmpLt" => BackCmd::UIcmpLt(dst, ty, lhs, rhs), "BackUIcmpLe" => BackCmd::UIcmpLe(dst, ty, lhs, rhs), "BackUIcmpGt" => BackCmd::UIcmpGt(dst, ty, lhs, rhs), "BackUIcmpGe" => BackCmd::UIcmpGe(dst, ty, lhs, rhs), "BackFCmpEq" => BackCmd::FCmpEq(dst, ty, lhs, rhs), "BackFCmpNe" => BackCmd::FCmpNe(dst, ty, lhs, rhs), "BackFCmpLt" => BackCmd::FCmpLt(dst, ty, lhs, rhs), "BackFCmpLe" => BackCmd::FCmpLe(dst, ty, lhs, rhs), "BackFCmpGt" => BackCmd::FCmpGt(dst, ty, lhs, rhs), "BackFCmpGe" => BackCmd::FCmpGe(dst, ty, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported compare {opk}"))) }); }
            "CmdCast" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = line.take_scalar()?; let v = line.take_val("value")?; out.push(match opk.as_str() { "BackBitcast" => BackCmd::Bitcast(dst, ty, v), "BackIreduce" => BackCmd::Ireduce(dst, ty, v), "BackSextend" => BackCmd::Sextend(dst, ty, v), "BackUextend" => BackCmd::Uextend(dst, ty, v), "BackFpromote" => BackCmd::Fpromote(dst, ty, v), "BackFdemote" => BackCmd::Fdemote(dst, ty, v), "BackSToF" => BackCmd::SToF(dst, ty, v), "BackUToF" => BackCmd::UToF(dst, ty, v), "BackFToS" => BackCmd::FToS(dst, ty, v), "BackFToU" => BackCmd::FToU(dst, ty, v), _ => return Err(MoonliftError(format!("unsupported cast {opk}"))) }); }
            "CmdPtrOffset" => { let dst = line.take_val("dst")?; let base = tape_base_cmds(&mut line, &format!("__moonlift_tape:ptr:{}", dst.as_str()), &mut out)?; let index = line.take_val("index")?; let elem = line.take_u32("elem size")?; let co = line.take_i64("const offset")?; out.push(BackCmd::PtrOffset(dst, base, index, elem, co)); }
            "CmdLoadInfo" => { let dst = line.take_val("dst")?; let shape = line.take_shape()?; let addr = tape_addr_cmds(&mut line, &format!("__moonlift_tape:load:{}", dst.as_str()), &mut out)?; let mem = line.take_memory()?; match shape { TapeShape::Scalar(s) => out.push(BackCmd::LoadInfo(dst, s, addr, mem)), TapeShape::Vec(v) => out.push(BackCmd::VecLoadInfo(dst, v, addr, mem)) } }
            "CmdStoreInfo" => { let shape = line.take_shape()?; let prefix = format!("__moonlift_tape:store:{}", line.line); let addr = tape_addr_cmds(&mut line, &prefix, &mut out)?; let val = line.take_val("store value")?; let mem = line.take_memory()?; match shape { TapeShape::Scalar(s) => out.push(BackCmd::StoreInfo(s, addr, val, mem)), TapeShape::Vec(v) => out.push(BackCmd::VecStoreInfo(v, addr, val, mem)) } }
            "CmdAtomicLoad" => { let dst = line.take_val("dst")?; let ty = line.take_scalar()?; let addr = tape_addr_cmds(&mut line, &format!("__moonlift_tape:atomic_load:{}", dst.as_str()), &mut out)?; let mem = line.take_memory()?; let ordering = read_atomic_ordering(&line.take("atomic ordering")?)?; out.push(BackCmd::AtomicLoad(dst, ty, addr, mem, ordering)); }
            "CmdAtomicStore" => { let ty = line.take_scalar()?; let prefix = format!("__moonlift_tape:atomic_store:{}", line.line); let addr = tape_addr_cmds(&mut line, &prefix, &mut out)?; let val = line.take_val("atomic store value")?; let mem = line.take_memory()?; let ordering = read_atomic_ordering(&line.take("atomic ordering")?)?; out.push(BackCmd::AtomicStore(ty, addr, val, mem, ordering)); }
            "CmdAtomicRmw" => { let dst = line.take_val("dst")?; let op = read_atomic_rmw_op(&line.take("atomic rmw op")?)?; let ty = line.take_scalar()?; let addr = tape_addr_cmds(&mut line, &format!("__moonlift_tape:atomic_rmw:{}", dst.as_str()), &mut out)?; let val = line.take_val("atomic rmw value")?; let mem = line.take_memory()?; let ordering = read_atomic_ordering(&line.take("atomic ordering")?)?; out.push(BackCmd::AtomicRmw(dst, op, ty, addr, val, mem, ordering)); }
            "CmdAtomicCas" => { let dst = line.take_val("dst")?; let ty = line.take_scalar()?; let addr = tape_addr_cmds(&mut line, &format!("__moonlift_tape:atomic_cas:{}", dst.as_str()), &mut out)?; let expected = line.take_val("atomic cas expected")?; let replacement = line.take_val("atomic cas replacement")?; let mem = line.take_memory()?; let ordering = read_atomic_ordering(&line.take("atomic ordering")?)?; out.push(BackCmd::AtomicCas(dst, ty, addr, expected, replacement, mem, ordering)); }
            "CmdAtomicFence" => { let ordering = read_atomic_ordering(&line.take("atomic ordering")?)?; out.push(BackCmd::AtomicFence(ordering)); }
            "CmdIntBinary" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = line.take_scalar()?; let sem = read_int_semantics(line.take_u32("overflow")?, line.take_u32("exact")?)?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(tape_int_op(&opk, dst, ty, sem, lhs, rhs)?); }
            "CmdBitBinary" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = line.take_scalar()?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(match opk.as_str() { "BackBitAnd" => BackCmd::Band(dst, ty, lhs, rhs), "BackBitOr" => BackCmd::Bor(dst, ty, lhs, rhs), "BackBitXor" => BackCmd::Bxor(dst, ty, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported bit op {opk}"))) }); }
            "CmdBitNot" => { let dst = line.take_val("dst")?; let ty = line.take_scalar()?; let v = line.take_val("value")?; out.push(BackCmd::Bnot(dst, ty, v)); }
            "CmdShift" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = line.take_scalar()?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(match opk.as_str() { "BackShiftLeft" => BackCmd::Ishl(dst, ty, lhs, rhs), "BackShiftLogicalRight" => BackCmd::Ushr(dst, ty, lhs, rhs), "BackShiftArithmeticRight" => BackCmd::Sshr(dst, ty, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported shift op {opk}"))) }); }
            "CmdRotate" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = line.take_scalar()?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(match opk.as_str() { "BackRotateLeft" => BackCmd::Rotl(dst, ty, lhs, rhs), "BackRotateRight" => BackCmd::Rotr(dst, ty, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported rotate op {opk}"))) }); }
            "CmdFloatBinary" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let ty = line.take_scalar()?; let sem = read_float_semantics(line.take_u32("float semantics")?)?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(tape_float_op(&opk, dst, ty, sem, lhs, rhs)?); }
            "CmdMemcpy" => out.push(BackCmd::Memcpy(line.take_val("dst")?, line.take_val("src")?, line.take_val("len")?)),
            "CmdMemset" => out.push(BackCmd::Memset(line.take_val("dst")?, line.take_val("byte")?, line.take_val("len")?)),
            "CmdSelect" => { let dst = line.take_val("dst")?; let ty = match line.take_shape()? { TapeShape::Scalar(s) => s, TapeShape::Vec(_) => return Err(MoonliftError("CmdSelect vector shape unsupported".to_string())) }; out.push(BackCmd::Select(dst, ty, line.take_val("cond")?, line.take_val("then")?, line.take_val("else")?)); }
            "CmdFma" => { let dst = line.take_val("dst")?; let ty = line.take_scalar()?; let sem = read_float_semantics(line.take_u32("sem")?)?; out.push(BackCmd::Fma(dst, ty, sem, line.take_val("a")?, line.take_val("b")?, line.take_val("c")?)); }
            "CmdVecSplat" => { let dst = line.take_val("dst")?; let vec = line.take_vec()?; out.push(BackCmd::VecSplat(dst, vec, line.take_val("value")?)); }
            "CmdVecBinary" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let vec = line.take_vec()?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(match opk.as_str() { "BackVecIntAdd" => BackCmd::VecIadd(dst, vec, lhs, rhs), "BackVecIntSub" => BackCmd::VecIsub(dst, vec, lhs, rhs), "BackVecIntMul" => BackCmd::VecImul(dst, vec, lhs, rhs), "BackVecBitAnd" => BackCmd::VecBand(dst, vec, lhs, rhs), "BackVecBitOr" => BackCmd::VecBor(dst, vec, lhs, rhs), "BackVecBitXor" => BackCmd::VecBxor(dst, vec, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported vec binary {opk}"))) }); }
            "CmdVecCompare" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let vec = line.take_vec()?; let lhs = line.take_val("lhs")?; let rhs = line.take_val("rhs")?; out.push(match opk.as_str() { "BackVecIcmpEq" => BackCmd::VecIcmpEq(dst, vec, lhs, rhs), "BackVecIcmpNe" => BackCmd::VecIcmpNe(dst, vec, lhs, rhs), "BackVecSIcmpLt" => BackCmd::VecSIcmpLt(dst, vec, lhs, rhs), "BackVecSIcmpLe" => BackCmd::VecSIcmpLe(dst, vec, lhs, rhs), "BackVecSIcmpGt" => BackCmd::VecSIcmpGt(dst, vec, lhs, rhs), "BackVecSIcmpGe" => BackCmd::VecSIcmpGe(dst, vec, lhs, rhs), "BackVecUIcmpLt" => BackCmd::VecUIcmpLt(dst, vec, lhs, rhs), "BackVecUIcmpLe" => BackCmd::VecUIcmpLe(dst, vec, lhs, rhs), "BackVecUIcmpGt" => BackCmd::VecUIcmpGt(dst, vec, lhs, rhs), "BackVecUIcmpGe" => BackCmd::VecUIcmpGe(dst, vec, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported vec compare {opk}"))) }); }
            "CmdVecSelect" => { let dst = line.take_val("dst")?; let vec = line.take_vec()?; out.push(BackCmd::VecSelect(dst, vec, line.take_val("mask")?, line.take_val("then")?, line.take_val("else")?)); }
            "CmdVecMask" => { let dst = line.take_val("dst")?; let opk = line.take("op")?; let vec = line.take_vec()?; let args = line.take_vals("mask args")?; let lhs = args[0].clone(); let rhs = args.get(1).cloned().unwrap_or_else(|| lhs.clone()); out.push(match opk.as_str() { "BackVecMaskNot" => BackCmd::VecMaskNot(dst, vec, lhs), "BackVecMaskAnd" => BackCmd::VecMaskAnd(dst, vec, lhs, rhs), "BackVecMaskOr" => BackCmd::VecMaskOr(dst, vec, lhs, rhs), _ => return Err(MoonliftError(format!("unsupported vec mask {opk}"))) }); }
            "CmdVecInsertLane" => { let dst = line.take_val("dst")?; let vec = line.take_vec()?; out.push(BackCmd::VecInsertLane(dst, vec, line.take_val("value")?, line.take_val("lane value")?, line.take_u32("lane")?)); }
            "CmdVecExtractLane" => out.push(BackCmd::VecExtractLane(line.take_val("dst")?, line.take_scalar()?, line.take_val("value")?, line.take_u32("lane")?)),
            "CmdCall" => { let result_kind = line.take("result kind")?; let result_dst = line.take("result dst")?; let result_ty = line.take_u32("result ty")?; let target_kind = line.take("target kind")?; let target = line.take("target")?; let sig = BackSigId::from(line.take("sig")?); let args = line.take_vals("call args")?; let cmd = match (result_kind.as_str(), target_kind.as_str()) { ("BackCallValue", "BackCallDirect") => BackCmd::CallValueDirect(BackValId::from(result_dst), read_scalar(result_ty)?, BackFuncId::from(target), sig, args), ("BackCallStmt", "BackCallDirect") => BackCmd::CallStmtDirect(BackFuncId::from(target), sig, args), ("BackCallValue", "BackCallExtern") => BackCmd::CallValueExtern(BackValId::from(result_dst), read_scalar(result_ty)?, BackExternId::from(target), sig, args), ("BackCallStmt", "BackCallExtern") => BackCmd::CallStmtExtern(BackExternId::from(target), sig, args), ("BackCallValue", "BackCallIndirect") => BackCmd::CallValueIndirect(BackValId::from(result_dst), read_scalar(result_ty)?, BackValId::from(target), sig, args), ("BackCallStmt", "BackCallIndirect") => BackCmd::CallStmtIndirect(BackValId::from(target), sig, args), _ => return Err(MoonliftError(format!("unsupported call {result_kind}/{target_kind}"))) }; out.push(cmd); }
            "CmdJump" => { let dest = BackBlockId::from(line.take("dest")?); let args = line.take_vals("jump args")?; out.push(BackCmd::Jump(dest, args)); }
            "CmdBrIf" => { let cond = line.take_val("cond")?; let then_block = BackBlockId::from(line.take("then")?); let then_args = line.take_vals("then args")?; let else_block = BackBlockId::from(line.take("else")?); let else_args = line.take_vals("else args")?; out.push(BackCmd::BrIf(cond, then_block, then_args, else_block, else_args)); }
            "CmdSwitchInt" => { let value = line.take_val("value")?; let ty = line.take_scalar()?; let n = line.take_usize("case count")?; let mut cases = Vec::with_capacity(n); for _ in 0..n { cases.push(BackSwitchCase::new(line.take("case raw")?, BackBlockId::from(line.take("case dest")?))); } let default = BackBlockId::from(line.take("default")?); out.push(BackCmd::SwitchInt(value, ty, cases, default)); }
            "CmdReturnVoid" => out.push(BackCmd::ReturnVoid),
            "CmdReturnValue" => out.push(BackCmd::ReturnValue(line.take_val("value")?)),
            "CmdTrap" => out.push(BackCmd::Trap),
            "CmdFinalizeModule" => out.push(BackCmd::FinalizeModule),
            other => return Err(MoonliftError(format!("unsupported BackCommandTape op {other}"))),
        }
    }
    Ok(out)
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_last_error_message() -> *const c_char {
    LAST_ERROR.with(|slot| slot.borrow().as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_new() -> *mut moonlift_jit_t {
    clear_last_error();
    let mut inner = Jit::new();
    crate::lua_api::register_symbols(&mut inner);
    Box::into_raw(Box::new(moonlift_jit_t { inner }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_free(ptr: *mut moonlift_jit_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_artifact_free(ptr: *mut moonlift_artifact_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_bytes_free(data: *mut u8, len: usize) {
    if !data.is_null() {
        unsafe { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, len))); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_object_compile_tape(
    payload: *const c_char,
    module_name: *const c_char,
    out: *mut moonlift_bytes_t,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let out = unsafe { out.as_mut() }
            .ok_or_else(|| MoonliftError("moonlift_bytes_t output pointer was null".to_string()))?;
        let payload = read_cstr(payload, "BackCommandTape payload")?;
        let module_name = if module_name.is_null() {
            "moonlift_object".to_string()
        } else {
            read_cstr(module_name, "object module name")?
        };
        let cmds = parse_back_command_tape(&payload)?;
        let artifact = compile_object(&BackProgram::new(cmds), &module_name)?;
        let mut bytes = artifact.into_bytes().into_boxed_slice();
        out.data = bytes.as_mut_ptr();
        out.len = bytes.len();
        std::mem::forget(bytes);
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_new() -> *mut moonlift_host_session_t {
    clear_last_error();
    Box::into_raw(Box::new(moonlift_host_session_t { inner: HostSession::new() }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_free(ptr: *mut moonlift_host_session_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_id(ptr: *const moonlift_host_session_t) -> u64 {
    let Some(session) = (unsafe { ptr.as_ref() }) else {
        set_last_error("moonlift_host_session_t pointer was null");
        return 0;
    };
    clear_last_error();
    session.inner.session_id()
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_generation(ptr: *const moonlift_host_session_t) -> u32 {
    let Some(session) = (unsafe { ptr.as_ref() }) else {
        set_last_error("moonlift_host_session_t pointer was null");
        return 0;
    };
    clear_last_error();
    session.inner.generation()
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_session_reset(ptr: *mut moonlift_host_session_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_ptr(ptr, "moonlift_host_session_t")?;
        session.inner.reset();
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_alloc_record(
    ptr: *mut moonlift_host_session_t,
    type_id: u32,
    tag: u32,
    size: usize,
    align: usize,
    out_ref: *mut MoonHostRef,
    out_ptr: *mut MoonHostPtr,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_ptr(ptr, "moonlift_host_session_t")?;
        let out_ref = unsafe { out_ref.as_mut() }
            .ok_or_else(|| MoonliftError("MoonHostRef output pointer was null".to_string()))?;
        let out_ptr = unsafe { out_ptr.as_mut() }
            .ok_or_else(|| MoonliftError("MoonHostPtr output pointer was null".to_string()))?;
        let (r, p) = session.inner.alloc_record(type_id, tag, size, align).map_err(MoonliftError)?;
        *out_ref = r;
        *out_ptr = p;
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_alloc_records(
    ptr: *mut moonlift_host_session_t,
    specs: *const MoonHostRecordSpec,
    specs_len: usize,
    fields: *const MoonHostFieldInit,
    fields_len: usize,
    out_refs: *mut MoonHostRef,
    out_ptrs: *mut MoonHostPtr,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = require_ptr(ptr, "moonlift_host_session_t")?;
        if specs_len == 0 {
            return Ok(());
        }
        if specs.is_null() {
            return Err(MoonliftError("MoonHostRecordSpec array pointer was null".to_string()));
        }
        if out_refs.is_null() {
            return Err(MoonliftError("MoonHostRef output array pointer was null".to_string()));
        }
        if out_ptrs.is_null() {
            return Err(MoonliftError("MoonHostPtr output array pointer was null".to_string()));
        }
        if fields_len > 0 && fields.is_null() {
            return Err(MoonliftError("MoonHostFieldInit array pointer was null".to_string()));
        }
        let specs = unsafe { std::slice::from_raw_parts(specs, specs_len) };
        let fields = if fields_len == 0 {
            &[][..]
        } else {
            unsafe { std::slice::from_raw_parts(fields, fields_len) }
        };
        let out_refs = unsafe { std::slice::from_raw_parts_mut(out_refs, specs_len) };
        let out_ptrs = unsafe { std::slice::from_raw_parts_mut(out_ptrs, specs_len) };
        for (i, spec) in specs.iter().enumerate() {
            let end = spec.first_field.checked_add(spec.field_count)
                .ok_or_else(|| MoonliftError(format!("record spec {i} field range overflow")))?;
            if end > fields.len() {
                return Err(MoonliftError(format!(
                    "record spec {i} field range [{}..{}) exceeds field array len {}",
                    spec.first_field, end, fields.len()
                )));
            }
            let (r, p) = session.inner.alloc_record(spec.type_id, spec.tag, spec.size, spec.align)
                .map_err(MoonliftError)?;
            for field in &fields[spec.first_field..end] {
                session.inner.write_field(r, *field).map_err(MoonliftError)?;
            }
            out_refs[i] = r;
            out_ptrs[i] = p;
        }
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_host_ptr_for_ref(
    ptr: *const moonlift_host_session_t,
    host_ref: MoonHostRef,
    out_ptr: *mut MoonHostPtr,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let session = unsafe { ptr.as_ref() }
            .ok_or_else(|| MoonliftError("moonlift_host_session_t pointer was null".to_string()))?;
        let out_ptr = unsafe { out_ptr.as_mut() }
            .ok_or_else(|| MoonliftError("MoonHostPtr output pointer was null".to_string()))?;
        *out_ptr = session.inner.ptr_for_ref(host_ref).map_err(MoonliftError)?;
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_symbol(
    jit: *mut moonlift_jit_t,
    name: *const c_char,
    ptr_value: *const c_void,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        let name = read_cstr(name, "symbol name")?;
        jit.inner.symbol(name, ptr_value.cast());
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_compile_tape(
    jit: *mut moonlift_jit_t,
    payload: *const c_char,
) -> *mut moonlift_artifact_t {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        let payload = read_cstr(payload, "BackCommandTape payload")?;
        let cmds = parse_back_command_tape(&payload)?;
        let artifact = jit.inner.compile(&BackProgram::new(cmds))?;
        Ok(Box::into_raw(Box::new(moonlift_artifact_t { inner: artifact })))
    })();
    match result {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => fail_ptr(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_artifact_getpointer(
    artifact: *const moonlift_artifact_t,
    func: *const c_char,
) -> *const c_void {
    let result: Result<_, MoonliftError> = (|| {
        let artifact = unsafe { artifact.as_ref() }
            .ok_or_else(|| MoonliftError("moonlift_artifact_t pointer was null".to_string()))?;
        let func = read_cstr(func, "function id")?;
        artifact.inner.getpointer_by_name(&func)
    })();
    match result {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => fail_const_ptr(err.0),
    }
}

// =========================================================================
// Binary wire format decoder (MLBT v3)
// =========================================================================

/// Slot count per command tag. Index by tag (0 = invalid).
static SLOT_COUNT: LazyLock<[usize; 64]> = LazyLock::new(|| {
    let mut t = [0usize; 64];
    t[1] = 0;  // CmdTargetModel
    t[2] = 0;  // CmdAliasFact
    t[3] = 5;  // CmdCreateSig
    t[4] = 3;  // CmdDeclareData
    t[5] = 3;  // CmdDataInitZero
    t[6] = 6;  // CmdDataInit
    t[7] = 2;  // CmdDataAddr
    t[8] = 2;  // CmdFuncAddr
    t[9] = 2;  // CmdExternAddr
    t[10] = 3; // CmdDeclareFunc
    t[11] = 3; // CmdDeclareExtern
    t[12] = 1; // CmdBeginFunc
    t[13] = 1; // CmdCreateBlock
    t[14] = 1; // CmdSwitchToBlock
    t[15] = 1; // CmdSealBlock
    t[16] = 3; // CmdBindEntryParams
    t[17] = 5; // CmdAppendBlockParam
    t[18] = 3; // CmdCreateStackSlot
    t[19] = 2; // CmdAlias
    t[20] = 2; // CmdStackAddr
    t[21] = 5; // CmdConst
    t[22] = 6; // CmdUnary
    t[23] = 7; // CmdIntrinsic
    t[24] = 7; // CmdCompare
    t[25] = 4; // CmdCast
    t[26] = 7; // CmdPtrOffset
    t[27] = 15; // CmdLoadInfo
    t[28] = 15; // CmdStoreInfo
    t[29] = 15; // CmdAtomicLoad
    t[30] = 14; // CmdAtomicStore
    t[31] = 16; // CmdAtomicRmw
    t[32] = 17; // CmdAtomicCas
    t[33] = 1; // CmdAtomicFence
    t[34] = 7; // CmdIntBinary
    t[35] = 5; // CmdBitBinary
    t[36] = 3; // CmdBitNot
    t[37] = 5; // CmdShift
    t[38] = 5; // CmdRotate
    t[39] = 6; // CmdFloatBinary
    t[40] = 3; // CmdMemcpy
    t[41] = 3; // CmdMemset
    t[42] = 7; // CmdSelect
    t[43] = 6; // CmdFma
    t[44] = 4; // CmdVecSplat
    t[45] = 6; // CmdVecBinary
    t[46] = 6; // CmdVecCompare
    t[47] = 6; // CmdVecSelect
    t[48] = 6; // CmdVecMask
    t[49] = 6; // CmdVecInsertLane
    t[50] = 4; // CmdVecExtractLane
    t[51] = 15; // CmdVecLoadInfo
    t[52] = 14; // CmdVecStoreInfo
    t[53] = 8; // CmdCall
    t[54] = 3; // CmdJump
    t[55] = 7; // CmdBrIf
    t[56] = 5; // CmdSwitchInt
    t[57] = 0; // CmdReturnVoid
    t[58] = 1; // CmdReturnValue
    t[59] = 0; // CmdTrap
    t[60] = 1; // CmdFinishFunc
    t[61] = 0; // CmdFinalizeModule
    t
});

/// Binary wire format reader.
struct BinaryReader<'a> {
    buf: &'a [u8],
    pos: usize,
    pool: Vec<String>,
    aux_offsets: Vec<usize>,  // aux[i] = byte offset into buf for the aux entry data
    aux_counts: Vec<u32>,     // aux[i] = count of u32 words
}

impl<'a> BinaryReader<'a> {
    fn new(buf: &'a [u8]) -> Result<Self, MoonliftError> {
        if buf.len() < 16 {
            return Err(MoonliftError("binary wire buffer too short for header".to_string()));
        }
        let magic = u32::from_le_bytes(buf[0..4].try_into().unwrap());
        if magic != 0x4D4C4254 {
            return Err(MoonliftError(format!("invalid binary wire magic {magic:#010x}")));
        }
        let version = u32::from_le_bytes(buf[4..8].try_into().unwrap());
        if version != 3 {
            return Err(MoonliftError(format!("unsupported binary wire version {version}")));
        }
        let n_strings = u32::from_le_bytes(buf[8..12].try_into().unwrap()) as usize;
        let _n_aux = u32::from_le_bytes(buf[12..16].try_into().unwrap()) as usize;

        let mut reader = Self {
            buf,
            pos: 16,
            pool: Vec::with_capacity(n_strings),
            aux_offsets: Vec::new(),
            aux_counts: Vec::new(),
        };

        // Read string pool.
        for i in 0..n_strings {
            let len = reader.take_u32("pool string len")? as usize;
            if reader.pos + len > reader.buf.len() {
                return Err(MoonliftError(format!("pool string {i} overflows buffer")));
            }
            let s = String::from_utf8_lossy(&reader.buf[reader.pos..reader.pos + len]).to_string();
            reader.pool.push(s);
            let padded_len = len + (4 - (len % 4)) % 4;
            reader.pos += padded_len;
        }

        // Record aux entry offsets.
        let _aux_start = reader.pos;
        let mut aux_scan = reader.pos;
        for i in 0.._n_aux {
            if aux_scan + 4 > buf.len() {
                return Err(MoonliftError(format!("aux entry {i} count overflows buffer")));
            }
            let count = u32::from_le_bytes(buf[aux_scan..aux_scan + 4].try_into().unwrap());
            reader.aux_offsets.push(aux_scan + 4);
            reader.aux_counts.push(count);
            aux_scan += 4 + 4 * count as usize;
        }
        reader.pos = aux_scan;

        Ok(reader)
    }

    fn take_u32(&mut self, what: &str) -> Result<u32, MoonliftError> {
        if self.pos + 4 > self.buf.len() {
            return Err(MoonliftError(format!("unexpected end of buffer reading {what}")));
        }
        let v = u32::from_le_bytes(self.buf[self.pos..self.pos + 4].try_into().unwrap());
        self.pos += 4;
        Ok(v)
    }

    fn pool_str(&self, idx: u32, what: &str) -> Result<String, MoonliftError> {
        let i = idx as usize;
        if i >= self.pool.len() {
            return Err(MoonliftError(format!("{what} pool index {idx} out of range (pool has {} entries)", self.pool.len())));
        }
        Ok(self.pool[i].clone())
    }

    fn pool_val(&self, idx: u32, what: &str) -> Result<BackValId, MoonliftError> {
        Ok(BackValId::from(self.pool_str(idx, what)?))
    }

    fn pool_block(&self, idx: u32, what: &str) -> Result<BackBlockId, MoonliftError> {
        Ok(BackBlockId::from(self.pool_str(idx, what)?))
    }

    fn pool_sig(&self, idx: u32, what: &str) -> Result<BackSigId, MoonliftError> {
        Ok(BackSigId::from(self.pool_str(idx, what)?))
    }

    fn pool_func(&self, idx: u32, what: &str) -> Result<BackFuncId, MoonliftError> {
        Ok(BackFuncId::from(self.pool_str(idx, what)?))
    }

    fn pool_extern(&self, idx: u32, what: &str) -> Result<BackExternId, MoonliftError> {
        Ok(BackExternId::from(self.pool_str(idx, what)?))
    }

    fn pool_data(&self, idx: u32, what: &str) -> Result<BackDataId, MoonliftError> {
        Ok(BackDataId::from(self.pool_str(idx, what)?))
    }

    fn pool_slot(&self, idx: u32, what: &str) -> Result<BackStackSlotId, MoonliftError> {
        Ok(BackStackSlotId::from(self.pool_str(idx, what)?))
    }

    fn pool_access(&self, idx: u32, what: &str) -> Result<BackAccessId, MoonliftError> {
        Ok(BackAccessId::from(self.pool_str(idx, what)?))
    }

    fn read_scalar(&self, code: u32, what: &str) -> Result<BackScalar, MoonliftError> {
        read_scalar_code(code, what)
    }

    fn read_shape(&self, shape_tag: u32, scalar: u32, lanes: u32) -> Result<Option<BackVec>, MoonliftError> {
        match shape_tag {
            0 => Ok(None),
            1 => {
                let elem = self.read_scalar(scalar, "shape scalar")?;
                Ok(Some(BackVec::new(elem, lanes)))
            }
            _ => Err(MoonliftError(format!("invalid shape tag {shape_tag}"))),
        }
    }

    /// Read u32 values from an aux entry. Returns the u32 slice.
    fn aux_slice(&self, aux_idx: u32, what: &str) -> Result<&'a [u8], MoonliftError> {
        let i = aux_idx as usize;
        if i >= self.aux_offsets.len() {
            return Err(MoonliftError(format!("{what} aux index {aux_idx} out of range")));
        }
        let offset = self.aux_offsets[i];
        let count = self.aux_counts[i] as usize;
        let end = offset + 4 * count;
        if end > self.buf.len() {
            return Err(MoonliftError(format!("{what} aux entry {aux_idx} overflows buffer")));
        }
        Ok(&self.buf[offset..end])
    }

    /// Read pool-indexed val IDs from aux.
    fn aux_vals(&self, aux_idx: u32, count: u32, what: &str) -> Result<Vec<BackValId>, MoonliftError> {
        let data = self.aux_slice(aux_idx, what)?;
        let n = count as usize;
        if n * 4 != data.len() {
            return Err(MoonliftError(format!("{what}: expected {n} u32s but aux has {} u32s", data.len() / 4)));
        }
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            let idx = u32::from_le_bytes(data[i * 4..i * 4 + 4].try_into().unwrap());
            out.push(self.pool_val(idx, what)?);
        }
        Ok(out)
    }

    /// Read scalar tags from aux.
    fn aux_scalars(&self, aux_idx: u32, count: u32, what: &str) -> Result<Vec<BackScalar>, MoonliftError> {
        let data = self.aux_slice(aux_idx, what)?;
        let n = count as usize;
        if n * 4 != data.len() {
            return Err(MoonliftError(format!("{what}: expected {n} u32s but aux has {} u32s", data.len() / 4)));
        }
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            let code = u32::from_le_bytes(data[i * 4..i * 4 + 4].try_into().unwrap());
            out.push(self.read_scalar(code, what)?);
        }
        Ok(out)
    }

    fn decode_address_base(&self, base_tag: u32, base_id: u32, prefix: &str, out: &mut Vec<BackCmd>) -> Result<BackValId, MoonliftError> {
        match base_tag {
            0 => Ok(self.pool_val(base_id, &format!("{prefix} base value"))?),
            1 => {
                let slot = self.pool_slot(base_id, &format!("{prefix} base slot"))?;
                let dst = BackValId::from(format!("{prefix}:base"));
                out.push(BackCmd::StackAddr(dst.clone(), slot));
                Ok(dst)
            }
            2 => {
                let data = self.pool_data(base_id, &format!("{prefix} base data"))?;
                let dst = BackValId::from(format!("{prefix}:base"));
                out.push(BackCmd::DataAddr(dst.clone(), data));
                Ok(dst)
            }
            _ => Err(MoonliftError(format!("invalid base_tag {base_tag}"))),
        }
    }

    fn decode_address(&self, base_tag: u32, base_id: u32, offset_id: u32, prefix: &str, out: &mut Vec<BackCmd>) -> Result<BackValId, MoonliftError> {
        let base = self.decode_address_base(base_tag, base_id, prefix, out)?;
        let byte_offset = self.pool_val(offset_id, &format!("{prefix} byte_offset"))?;
        let dst = BackValId::from(format!("{prefix}:addr"));
        out.push(BackCmd::PtrAdd(dst.clone(), base, byte_offset));
        Ok(dst)
    }

    fn decode_memory(&self, slots: &[u32], offset: usize) -> Result<BackMemoryInfo, MoonliftError> {
        let access = self.pool_access(slots[offset], "memory access")?;
        let ak = slots[offset + 1];
        let ab = slots[offset + 2];
        let dk = slots[offset + 3];
        let db = slots[offset + 4];
        let tk = slots[offset + 5];
        let mk = slots[offset + 6];
        let mode_k = slots[offset + 7];
        Ok(BackMemoryInfo::new(
            access,
            read_alignment(ak, ab)?,
            read_dereference(dk, db)?,
            read_trap(tk)?,
            read_motion(mk)?,
            read_access_mode(mode_k)?,
        ))
    }

    #[allow(dead_code)]
    fn decode_literal(&self, _lit_tag: u32, _lit_lo: u32, _lit_hi: u32, _scalar: BackScalar) -> Result<BackCmd, MoonliftError> {
        // This returns the raw cmd fragments; caller assembles the final BackCmd.
        // We return a small helper enum but actually just return parts.
        // Instead, let the caller handle this.
        unreachable!() // unused, see inline below
    }

    fn decode_commands(mut self) -> Result<Vec<BackCmd>, MoonliftError> {
        let mut out = Vec::new();
        while self.pos < self.buf.len() {
            let tag = self.take_u32("command tag")?;
            if tag == 0 || tag as usize >= SLOT_COUNT.len() {
                return Err(MoonliftError(format!("invalid command tag {tag}")));
            }
            let n_slots = SLOT_COUNT[tag as usize];
            if self.pos + 4 * n_slots > self.buf.len() {
                return Err(MoonliftError(format!("command tag {tag} needs {n_slots} slots but buffer has {} bytes left", self.buf.len() - self.pos)));
            }
            // Read slots as u32 slice.
            let _slots_start = self.pos;
            let mut slots = Vec::with_capacity(n_slots);
            for _ in 0..n_slots {
                slots.push(u32::from_le_bytes(self.buf[self.pos..self.pos + 4].try_into().unwrap()));
                self.pos += 4;
            }

            match tag {
                1 | 2 => { /* CmdTargetModel, CmdAliasFact: no-op */ }

                3 => { // CmdCreateSig
                    let sig = self.pool_sig(slots[0], "sig")?;
                    let params = self.aux_scalars(slots[1], slots[2], "sig params")?;
                    let results = self.aux_scalars(slots[3], slots[4], "sig results")?;
                    out.push(BackCmd::CreateSig(sig, params, results));
                }

                4 => { // CmdDeclareData
                    out.push(BackCmd::DeclareData(self.pool_data(slots[0], "data")?, slots[1], slots[2]));
                }

                5 => { // CmdDataInitZero
                    out.push(BackCmd::DataInitZero(self.pool_data(slots[0], "data")?, slots[1], slots[2]));
                }

                6 => { // CmdDataInit
                    let data = self.pool_data(slots[0], "data")?;
                    let offset = slots[1];
                    let scalar = self.read_scalar(slots[2], "data init scalar")?;
                    match slots[3] {
                        0 => out.push(BackCmd::DataInitZero(data, offset, scalar.byte_size(8))),
                        1 => out.push(BackCmd::DataInitBool(data, offset, slots[4] != 0)),
                        2 => {
                            let raw = binary_int_literal_raw(scalar, slots[4], slots[5]);
                            out.push(BackCmd::DataInitInt(data, offset, scalar, raw));
                        }
                        3 => {
                            let bits = (slots[4] as u64) | ((slots[5] as u64) << 32);
                            let raw = match scalar {
                                BackScalar::F32 => format!("{}", f32::from_bits(bits as u32)),
                                BackScalar::F64 => format!("{}", f64::from_bits(bits)),
                                _ => format!("{bits}"),
                            };
                            out.push(BackCmd::DataInitFloat(data, offset, scalar, raw));
                        }
                        _ => return Err(MoonliftError(format!("unsupported lit_tag {}", slots[3]))),
                    }
                }

                7 => { // CmdDataAddr
                    out.push(BackCmd::DataAddr(self.pool_val(slots[0], "dst")?, self.pool_data(slots[1], "data")?));
                }

                8 => { // CmdFuncAddr
                    out.push(BackCmd::FuncAddr(self.pool_val(slots[0], "dst")?, self.pool_func(slots[1], "func")?));
                }

                9 => { // CmdExternAddr
                    out.push(BackCmd::ExternAddr(self.pool_val(slots[0], "dst")?, self.pool_extern(slots[1], "extern")?));
                }

                10 => { // CmdDeclareFunc
                    let func = self.pool_func(slots[1], "func")?;
                    let sig = self.pool_sig(slots[2], "sig")?;
                    if slots[0] == 1 {
                        out.push(BackCmd::DeclareFuncExport(func, sig));
                    } else {
                        out.push(BackCmd::DeclareFuncLocal(func, sig));
                    }
                }

                11 => { // CmdDeclareExtern
                    out.push(BackCmd::DeclareFuncExtern(self.pool_extern(slots[0], "extern")?, self.pool_str(slots[1], "symbol")?, self.pool_sig(slots[2], "sig")?));
                }

                12 => { out.push(BackCmd::BeginFunc(self.pool_func(slots[0], "func")?)); }
                13 => { out.push(BackCmd::CreateBlock(self.pool_block(slots[0], "block")?)); }
                14 => { out.push(BackCmd::SwitchToBlock(self.pool_block(slots[0], "block")?)); }
                15 => { out.push(BackCmd::SealBlock(self.pool_block(slots[0], "block")?)); }

                16 => { // CmdBindEntryParams
                    let block = self.pool_block(slots[0], "block")?;
                    let vals = self.aux_vals(slots[1], slots[2], "entry params")?;
                    out.push(BackCmd::BindEntryParams(block, vals));
                }

                17 => { // CmdAppendBlockParam
                    let block = self.pool_block(slots[0], "block")?;
                    let val = self.pool_val(slots[1], "value")?;
                    if let Some(vec) = self.read_shape(slots[2], slots[3], slots[4])? {
                        out.push(BackCmd::AppendVecBlockParam(block, val, vec));
                    } else {
                        out.push(BackCmd::AppendBlockParam(block, val, self.read_scalar(slots[3], "param scalar")?));
                    }
                }

                18 => { out.push(BackCmd::CreateStackSlot(self.pool_slot(slots[0], "slot")?, slots[1], slots[2])); }
                19 => { out.push(BackCmd::Alias(self.pool_val(slots[0], "dst")?, self.pool_val(slots[1], "src")?)); }
                20 => { out.push(BackCmd::StackAddr(self.pool_val(slots[0], "dst")?, self.pool_slot(slots[1], "slot")?)); }

                21 => { // CmdConst
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[1], "const scalar")?;
                    match slots[2] {
                        0 => out.push(BackCmd::ConstNull(dst)),
                        1 => out.push(BackCmd::ConstBool(dst, slots[3] != 0)),
                        2 => {
                            let raw = binary_int_literal_raw(scalar, slots[3], slots[4]);
                            out.push(BackCmd::ConstInt(dst, scalar, raw));
                        }
                        3 => {
                            let bits = (slots[3] as u64) | ((slots[4] as u64) << 32);
                            let raw = match scalar {
                                BackScalar::F32 => format!("{}", f32::from_bits(bits as u32)),
                                BackScalar::F64 => format!("{}", f64::from_bits(bits)),
                                _ => format!("{bits}"),
                            };
                            out.push(BackCmd::ConstFloat(dst, scalar, raw));
                        }
                        _ => return Err(MoonliftError(format!("unsupported lit_tag {}", slots[2]))),
                    }
                }

                22 => { // CmdUnary
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[3], "unary scalar")?;
                    let value = self.pool_val(slots[5], "unary value")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Ineg(dst, scalar, value),
                        2 => BackCmd::Fneg(dst, scalar, value),
                        3 => BackCmd::Bnot(dst, scalar, value),
                        4 => BackCmd::BoolNot(dst, value),
                        _ => return Err(MoonliftError(format!("unsupported unary op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                23 => { // CmdIntrinsic
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[3], "intrinsic scalar")?;
                    let args = self.aux_vals(slots[5], slots[6], "intrinsic args")?;
                    let v = args[0].clone();
                    let cmd = match slots[1] {
                        1 => BackCmd::Popcount(dst, scalar, v),
                        2 => BackCmd::Clz(dst, scalar, v),
                        3 => BackCmd::Ctz(dst, scalar, v),
                        4 => BackCmd::Bswap(dst, scalar, v),
                        5 => BackCmd::Sqrt(dst, scalar, v),
                        6 => BackCmd::Abs(dst, scalar, v),
                        7 => BackCmd::Floor(dst, scalar, v),
                        8 => BackCmd::Ceil(dst, scalar, v),
                        9 => BackCmd::TruncFloat(dst, scalar, v),
                        10 => BackCmd::Round(dst, scalar, v),
                        _ => return Err(MoonliftError(format!("unsupported intrinsic op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                24 => { // CmdCompare
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[3], "compare scalar")?;
                    let lhs = self.pool_val(slots[5], "compare lhs")?;
                    let rhs = self.pool_val(slots[6], "compare rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::IcmpEq(dst, scalar, lhs, rhs),
                        2 => BackCmd::IcmpNe(dst, scalar, lhs, rhs),
                        3 => BackCmd::SIcmpLt(dst, scalar, lhs, rhs),
                        4 => BackCmd::SIcmpLe(dst, scalar, lhs, rhs),
                        5 => BackCmd::SIcmpGt(dst, scalar, lhs, rhs),
                        6 => BackCmd::SIcmpGe(dst, scalar, lhs, rhs),
                        7 => BackCmd::UIcmpLt(dst, scalar, lhs, rhs),
                        8 => BackCmd::UIcmpLe(dst, scalar, lhs, rhs),
                        9 => BackCmd::UIcmpGt(dst, scalar, lhs, rhs),
                        10 => BackCmd::UIcmpGe(dst, scalar, lhs, rhs),
                        11 => BackCmd::FCmpEq(dst, scalar, lhs, rhs),
                        12 => BackCmd::FCmpNe(dst, scalar, lhs, rhs),
                        13 => BackCmd::FCmpLt(dst, scalar, lhs, rhs),
                        14 => BackCmd::FCmpLe(dst, scalar, lhs, rhs),
                        15 => BackCmd::FCmpGt(dst, scalar, lhs, rhs),
                        16 => BackCmd::FCmpGe(dst, scalar, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported compare op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                25 => { // CmdCast
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "cast scalar")?;
                    let value = self.pool_val(slots[3], "cast value")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Bitcast(dst, scalar, value),
                        2 => BackCmd::Ireduce(dst, scalar, value),
                        3 => BackCmd::Sextend(dst, scalar, value),
                        4 => BackCmd::Uextend(dst, scalar, value),
                        5 => BackCmd::Fpromote(dst, scalar, value),
                        6 => BackCmd::Fdemote(dst, scalar, value),
                        7 => BackCmd::SToF(dst, scalar, value),
                        8 => BackCmd::UToF(dst, scalar, value),
                        9 => BackCmd::FToS(dst, scalar, value),
                        10 => BackCmd::FToU(dst, scalar, value),
                        _ => return Err(MoonliftError(format!("unsupported cast op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                26 => { // CmdPtrOffset
                    let dst = self.pool_val(slots[0], "dst")?;
                    let base = self.decode_address_base(slots[1], slots[2], &format!("__binary:ptr:{}", dst.as_str()), &mut out)?;
                    let index = self.pool_val(slots[3], "ptr offset index")?;
                    let elem_size = slots[4];
                    let const_offset = ((slots[6] as u64) << 32) | (slots[5] as u64);
                    out.push(BackCmd::PtrOffset(dst, base, index, elem_size, const_offset as i64));
                }

                27 => { // CmdLoadInfo
                    let dst = self.pool_val(slots[0], "dst")?;
                    let prefix = format!("__binary:load:{}", dst.as_str());
                    let scalar = self.read_scalar(slots[2], "load scalar")?;
                    let addr = self.decode_address(slots[4], slots[5], slots[6], &prefix, &mut out)?;
                    let mem = self.decode_memory(&slots, 7)?;
                    if let Some(vec) = self.read_shape(slots[1], slots[2], slots[3])? {
                        out.push(BackCmd::VecLoadInfo(dst, vec, addr, mem));
                    } else {
                        out.push(BackCmd::LoadInfo(dst, scalar, addr, mem));
                    }
                }

                28 => { // CmdStoreInfo
                    let prefix = format!("__binary:store:{}", slots[5]);
                    let scalar = self.read_scalar(slots[1], "store scalar")?;
                    let addr = self.decode_address(slots[3], slots[4], slots[5], &prefix, &mut out)?;
                    let value = self.pool_val(slots[6], "store value")?;
                    let mem = self.decode_memory(&slots, 7)?;
                    if let Some(vec) = self.read_shape(slots[0], slots[1], slots[2])? {
                        out.push(BackCmd::VecStoreInfo(vec, addr, value, mem));
                    } else {
                        out.push(BackCmd::StoreInfo(scalar, addr, value, mem));
                    }
                }

                29 => { // CmdAtomicLoad
                    let dst = self.pool_val(slots[0], "dst")?;
                    let prefix = format!("__binary:atomic_load:{}", dst.as_str());
                    let scalar = self.read_scalar(slots[1], "atomic load scalar")?;
                    let addr = self.decode_address(slots[2], slots[3], slots[4], &prefix, &mut out)?;
                    let mem = self.decode_memory(&slots, 5)?;
                    let ordering = read_binary_atomic_ordering(slots[13])?;
                    out.push(BackCmd::AtomicLoad(dst, scalar, addr, mem, ordering));
                }

                30 => { // CmdAtomicStore
                    let prefix = format!("__binary:atomic_store:{}", slots[4]);
                    let scalar = self.read_scalar(slots[0], "atomic store scalar")?;
                    let addr = self.decode_address(slots[1], slots[2], slots[3], &prefix, &mut out)?;
                    let value = self.pool_val(slots[4], "atomic store value")?;
                    let mem = self.decode_memory(&slots, 5)?;
                    let ordering = read_binary_atomic_ordering(slots[13])?;
                    out.push(BackCmd::AtomicStore(scalar, addr, value, mem, ordering));
                }

                31 => { // CmdAtomicRmw
                    let dst = self.pool_val(slots[0], "dst")?;
                    let prefix = format!("__binary:atomic_rmw:{}", dst.as_str());
                    let op = read_binary_atomic_rmw_op(slots[1])?;
                    let scalar = self.read_scalar(slots[2], "atomic rmw scalar")?;
                    let addr = self.decode_address(slots[3], slots[4], slots[5], &prefix, &mut out)?;
                    let value = self.pool_val(slots[6], "atomic rmw value")?;
                    let mem = self.decode_memory(&slots, 7)?;
                    let ordering = read_binary_atomic_ordering(slots[15])?;
                    out.push(BackCmd::AtomicRmw(dst, op, scalar, addr, value, mem, ordering));
                }

                32 => { // CmdAtomicCas
                    let dst = self.pool_val(slots[0], "dst")?;
                    let prefix = format!("__binary:atomic_cas:{}", dst.as_str());
                    let scalar = self.read_scalar(slots[1], "atomic cas scalar")?;
                    let addr = self.decode_address(slots[2], slots[3], slots[4], &prefix, &mut out)?;
                    let expected = self.pool_val(slots[5], "atomic cas expected")?;
                    let replacement = self.pool_val(slots[6], "atomic cas replacement")?;
                    let mem = self.decode_memory(&slots, 7)?;
                    let ordering = read_binary_atomic_ordering(slots[15])?;
                    out.push(BackCmd::AtomicCas(dst, scalar, addr, expected, replacement, mem, ordering));
                }

                33 => { // CmdAtomicFence
                    out.push(BackCmd::AtomicFence(read_binary_atomic_ordering(slots[0])?));
                }

                34 => { // CmdIntBinary
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "int binary scalar")?;
                    let sem = read_int_semantics(slots[3], slots[4])?;
                    let lhs = self.pool_val(slots[5], "int binary lhs")?;
                    let rhs = self.pool_val(slots[6], "int binary rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Iadd(dst, scalar, sem, lhs, rhs),
                        2 => BackCmd::Isub(dst, scalar, sem, lhs, rhs),
                        3 => BackCmd::Imul(dst, scalar, sem, lhs, rhs),
                        4 => BackCmd::Sdiv(dst, scalar, sem, lhs, rhs),
                        5 => BackCmd::Udiv(dst, scalar, sem, lhs, rhs),
                        6 => BackCmd::Srem(dst, scalar, sem, lhs, rhs),
                        7 => BackCmd::Urem(dst, scalar, sem, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported int op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                35 => { // CmdBitBinary
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "bit binary scalar")?;
                    let lhs = self.pool_val(slots[3], "bit binary lhs")?;
                    let rhs = self.pool_val(slots[4], "bit binary rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Band(dst, scalar, lhs, rhs),
                        2 => BackCmd::Bor(dst, scalar, lhs, rhs),
                        3 => BackCmd::Bxor(dst, scalar, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported bit op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                36 => { // CmdBitNot
                    out.push(BackCmd::Bnot(self.pool_val(slots[0], "dst")?, self.read_scalar(slots[1], "bitnot scalar")?, self.pool_val(slots[2], "bitnot value")?));
                }

                37 => { // CmdShift
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "shift scalar")?;
                    let lhs = self.pool_val(slots[3], "shift lhs")?;
                    let rhs = self.pool_val(slots[4], "shift rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Ishl(dst, scalar, lhs, rhs),
                        2 => BackCmd::Ushr(dst, scalar, lhs, rhs),
                        3 => BackCmd::Sshr(dst, scalar, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported shift op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                38 => { // CmdRotate
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "rotate scalar")?;
                    let lhs = self.pool_val(slots[3], "rotate lhs")?;
                    let rhs = self.pool_val(slots[4], "rotate rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Rotl(dst, scalar, lhs, rhs),
                        2 => BackCmd::Rotr(dst, scalar, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported rotate op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                39 => { // CmdFloatBinary
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "float binary scalar")?;
                    let sem = read_float_semantics(slots[3])?;
                    let lhs = self.pool_val(slots[4], "float binary lhs")?;
                    let rhs = self.pool_val(slots[5], "float binary rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::Fadd(dst, scalar, sem, lhs, rhs),
                        2 => BackCmd::Fsub(dst, scalar, sem, lhs, rhs),
                        3 => BackCmd::Fmul(dst, scalar, sem, lhs, rhs),
                        4 => BackCmd::Fdiv(dst, scalar, sem, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported float op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                40 => { out.push(BackCmd::Memcpy(self.pool_val(slots[0], "dst")?, self.pool_val(slots[1], "src")?, self.pool_val(slots[2], "len")?)); }
                41 => { out.push(BackCmd::Memset(self.pool_val(slots[0], "dst")?, self.pool_val(slots[1], "byte")?, self.pool_val(slots[2], "len")?)); }

                42 => { // CmdSelect
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[2], "select scalar")?;
                    out.push(BackCmd::Select(dst, scalar, self.pool_val(slots[4], "cond")?, self.pool_val(slots[5], "then")?, self.pool_val(slots[6], "else")?));
                }

                43 => { // CmdFma
                    let dst = self.pool_val(slots[0], "dst")?;
                    let scalar = self.read_scalar(slots[1], "fma scalar")?;
                    let sem = read_float_semantics(slots[2])?;
                    out.push(BackCmd::Fma(dst, scalar, sem, self.pool_val(slots[3], "a")?, self.pool_val(slots[4], "b")?, self.pool_val(slots[5], "c")?));
                }

                44 => { // CmdVecSplat
                    out.push(BackCmd::VecSplat(self.pool_val(slots[0], "dst")?, BackVec::new(self.read_scalar(slots[1], "splat elem")?, slots[2]), self.pool_val(slots[3], "splat value")?));
                }

                45 => { // CmdVecBinary
                    let dst = self.pool_val(slots[0], "dst")?;
                    let vec = BackVec::new(self.read_scalar(slots[2], "vec elem")?, slots[3]);
                    let lhs = self.pool_val(slots[4], "vec lhs")?;
                    let rhs = self.pool_val(slots[5], "vec rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::VecIadd(dst, vec, lhs, rhs),
                        2 => BackCmd::VecIsub(dst, vec, lhs, rhs),
                        3 => BackCmd::VecImul(dst, vec, lhs, rhs),
                        4 => BackCmd::VecBand(dst, vec, lhs, rhs),
                        5 => BackCmd::VecBor(dst, vec, lhs, rhs),
                        6 => BackCmd::VecBxor(dst, vec, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported vec binary op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                46 => { // CmdVecCompare
                    let dst = self.pool_val(slots[0], "dst")?;
                    let vec = BackVec::new(self.read_scalar(slots[2], "vec elem")?, slots[3]);
                    let lhs = self.pool_val(slots[4], "vec lhs")?;
                    let rhs = self.pool_val(slots[5], "vec rhs")?;
                    let cmd = match slots[1] {
                        1 => BackCmd::VecIcmpEq(dst, vec, lhs, rhs),
                        2 => BackCmd::VecIcmpNe(dst, vec, lhs, rhs),
                        3 => BackCmd::VecSIcmpLt(dst, vec, lhs, rhs),
                        4 => BackCmd::VecSIcmpLe(dst, vec, lhs, rhs),
                        5 => BackCmd::VecSIcmpGt(dst, vec, lhs, rhs),
                        6 => BackCmd::VecSIcmpGe(dst, vec, lhs, rhs),
                        7 => BackCmd::VecUIcmpLt(dst, vec, lhs, rhs),
                        8 => BackCmd::VecUIcmpLe(dst, vec, lhs, rhs),
                        9 => BackCmd::VecUIcmpGt(dst, vec, lhs, rhs),
                        10 => BackCmd::VecUIcmpGe(dst, vec, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported vec compare op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                47 => { // CmdVecSelect
                    let dst = self.pool_val(slots[0], "dst")?;
                    let vec = BackVec::new(self.read_scalar(slots[1], "vec elem")?, slots[2]);
                    out.push(BackCmd::VecSelect(dst, vec, self.pool_val(slots[3], "mask")?, self.pool_val(slots[4], "then")?, self.pool_val(slots[5], "else")?));
                }

                48 => { // CmdVecMask
                    let dst = self.pool_val(slots[0], "dst")?;
                    let vec = BackVec::new(self.read_scalar(slots[2], "vec elem")?, slots[3]);
                    let args = self.aux_vals(slots[4], slots[5], "vec mask args")?;
                    let lhs = args[0].clone();
                    let rhs = args.get(1).cloned().unwrap_or_else(|| lhs.clone());
                    let cmd = match slots[1] {
                        1 => BackCmd::VecMaskNot(dst, vec, lhs),
                        2 => BackCmd::VecMaskAnd(dst, vec, lhs, rhs),
                        3 => BackCmd::VecMaskOr(dst, vec, lhs, rhs),
                        _ => return Err(MoonliftError(format!("unsupported vec mask op {}", slots[1]))),
                    };
                    out.push(cmd);
                }

                49 => { // CmdVecInsertLane
                    let dst = self.pool_val(slots[0], "dst")?;
                    let vec = BackVec::new(self.read_scalar(slots[1], "vec elem")?, slots[2]);
                    out.push(BackCmd::VecInsertLane(dst, vec, self.pool_val(slots[3], "value")?, self.pool_val(slots[4], "lane value")?, slots[5]));
                }

                50 => { // CmdVecExtractLane
                    out.push(BackCmd::VecExtractLane(self.pool_val(slots[0], "dst")?, self.read_scalar(slots[1], "extract scalar")?, self.pool_val(slots[2], "value")?, slots[3]));
                }

                51 => { // CmdVecLoadInfo
                    let dst = self.pool_val(slots[0], "dst")?;
                    let prefix = format!("__binary:vec_load:{}", dst.as_str());
                    let vec = BackVec::new(self.read_scalar(slots[1], "vec elem")?, slots[2]);
                    let addr = self.decode_address(slots[3], slots[4], slots[5], &prefix, &mut out)?;
                    let mem = self.decode_memory(&slots, 6)?;
                    out.push(BackCmd::VecLoadInfo(dst, vec, addr, mem));
                }

                52 => { // CmdVecStoreInfo
                    let prefix = format!("__binary:vec_store:{}", slots[5]);
                    let vec = BackVec::new(self.read_scalar(slots[0], "vec elem")?, slots[1]);
                    let addr = self.decode_address(slots[2], slots[3], slots[4], &prefix, &mut out)?;
                    let value = self.pool_val(slots[5], "store value")?;
                    let mem = self.decode_memory(&slots, 6)?;
                    out.push(BackCmd::VecStoreInfo(vec, addr, value, mem));
                }

                53 => { // CmdCall
                    let result_tag = slots[0];
                    let result_dst = slots[1];
                    let result_scalar = slots[2];
                    let target_tag = slots[3];
                    let target_id = slots[4];
                    let sig = self.pool_sig(slots[5], "call sig")?;
                    let args = self.aux_vals(slots[6], slots[7], "call args")?;
                    let cmd = match (result_tag, target_tag) {
                        (1, 0) => BackCmd::CallValueDirect(self.pool_val(result_dst, "call dst")?, self.read_scalar(result_scalar, "call result scalar")?, self.pool_func(target_id, "call func")?, sig, args),
                        (0, 0) => BackCmd::CallStmtDirect(self.pool_func(target_id, "call func")?, sig, args),
                        (1, 1) => BackCmd::CallValueExtern(self.pool_val(result_dst, "call dst")?, self.read_scalar(result_scalar, "call result scalar")?, self.pool_extern(target_id, "call extern")?, sig, args),
                        (0, 1) => BackCmd::CallStmtExtern(self.pool_extern(target_id, "call extern")?, sig, args),
                        (1, 2) => BackCmd::CallValueIndirect(self.pool_val(result_dst, "call dst")?, self.read_scalar(result_scalar, "call result scalar")?, self.pool_val(target_id, "call callee")?, sig, args),
                        (0, 2) => BackCmd::CallStmtIndirect(self.pool_val(target_id, "call callee")?, sig, args),
                        _ => return Err(MoonliftError(format!("unsupported call {result_tag}/{target_tag}"))),
                    };
                    out.push(cmd);
                }

                54 => { // CmdJump
                    let dest = self.pool_block(slots[0], "jump dest")?;
                    let args = self.aux_vals(slots[1], slots[2], "jump args")?;
                    out.push(BackCmd::Jump(dest, args));
                }

                55 => { // CmdBrIf
                    let cond = self.pool_val(slots[0], "brif cond")?;
                    let then_block = self.pool_block(slots[1], "brif then")?;
                    let then_args = self.aux_vals(slots[2], slots[3], "brif then args")?;
                    let else_block = self.pool_block(slots[4], "brif else")?;
                    let else_args = self.aux_vals(slots[5], slots[6], "brif else args")?;
                    out.push(BackCmd::BrIf(cond, then_block, then_args, else_block, else_args));
                }

                56 => { // CmdSwitchInt
                    let value = self.pool_val(slots[0], "switch value")?;
                    let ty = self.read_scalar(slots[1], "switch scalar")?;
                    let n_cases = slots[3] as usize;
                    let aux_data = self.aux_slice(slots[2], "switch cases")?;
                    if aux_data.len() < n_cases * 12 {
                        return Err(MoonliftError(format!("switch cases aux too short: {} < {}", aux_data.len(), n_cases * 12)));
                    }
                    let mut cases = Vec::with_capacity(n_cases);
                    for i in 0..n_cases {
                        let lo = u32::from_le_bytes(aux_data[i * 12..i * 12 + 4].try_into().unwrap());
                        let hi = u32::from_le_bytes(aux_data[i * 12 + 4..i * 12 + 8].try_into().unwrap());
                        let dest_idx = u32::from_le_bytes(aux_data[i * 12 + 8..i * 12 + 12].try_into().unwrap());
                        let raw = binary_int_literal_raw(ty, lo, hi);
                        let dest = self.pool_block(dest_idx, "switch case dest")?;
                        cases.push(BackSwitchCase::new(raw, dest));
                    }
                    let default = self.pool_block(slots[4], "switch default")?;
                    out.push(BackCmd::SwitchInt(value, ty, cases, default));
                }

                57 => { out.push(BackCmd::ReturnVoid); }
                58 => { out.push(BackCmd::ReturnValue(self.pool_val(slots[0], "return value")?)); }
                59 => { out.push(BackCmd::Trap); }
                60 => { out.push(BackCmd::FinishFunc(self.pool_func(slots[0], "func")?)); }
                61 => { out.push(BackCmd::FinalizeModule); }

                _ => return Err(MoonliftError(format!("unsupported binary command tag {tag}"))),
            }
        }
        Ok(out)
    }
}

fn binary_u64(lo: u32, hi: u32) -> u64 {
    (lo as u64) | ((hi as u64) << 32)
}

fn binary_int_literal_raw(scalar: BackScalar, lo: u32, hi: u32) -> String {
    let bits = binary_u64(lo, hi);
    match scalar {
        BackScalar::I8 | BackScalar::I16 | BackScalar::I32 | BackScalar::I64 => (bits as i64).to_string(),
        _ => bits.to_string(),
    }
}

fn read_scalar_code(code: u32, what: &str) -> Result<BackScalar, MoonliftError> {
    match code {
        1 => Ok(BackScalar::Bool),
        2 => Ok(BackScalar::I8),
        3 => Ok(BackScalar::I16),
        4 => Ok(BackScalar::I32),
        5 => Ok(BackScalar::I64),
        6 => Ok(BackScalar::U8),
        7 => Ok(BackScalar::U16),
        8 => Ok(BackScalar::U32),
        9 => Ok(BackScalar::U64),
        10 => Ok(BackScalar::F32),
        11 => Ok(BackScalar::F64),
        12 => Ok(BackScalar::Ptr),
        13 => Ok(BackScalar::Index),
        _ => Err(MoonliftError(format!("unknown {what} scalar code {code}"))),
    }
}

fn read_binary_atomic_ordering(code: u32) -> Result<BackAtomicOrdering, MoonliftError> {
    match code {
        1 => Ok(BackAtomicOrdering::SeqCst),
        _ => Err(MoonliftError(format!("unknown atomic ordering code {code}"))),
    }
}

fn read_binary_atomic_rmw_op(code: u32) -> Result<BackAtomicRmwOp, MoonliftError> {
    match code {
        1 => Ok(BackAtomicRmwOp::Add),
        2 => Ok(BackAtomicRmwOp::Sub),
        3 => Ok(BackAtomicRmwOp::And),
        4 => Ok(BackAtomicRmwOp::Or),
        5 => Ok(BackAtomicRmwOp::Xor),
        6 => Ok(BackAtomicRmwOp::Xchg),
        _ => Err(MoonliftError(format!("unknown atomic rmw op code {code}"))),
    }
}

pub(crate) fn parse_back_command_binary(data: &[u8]) -> Result<Vec<BackCmd>, MoonliftError> {
    let reader = BinaryReader::new(data)?;
    reader.decode_commands()
}

// =========================================================================
// Binary FFI entry points
// =========================================================================

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_compile_binary(
    jit: *mut moonlift_jit_t,
    data: *const u8,
    len: usize,
) -> *mut moonlift_artifact_t {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        if data.is_null() {
            return Err(MoonliftError("binary data pointer was null".to_string()));
        }
        let buf = unsafe { std::slice::from_raw_parts(data, len) };
        let cmds = parse_back_command_binary(buf)?;
        let artifact = jit.inner.compile(&BackProgram::new(cmds))?;
        Ok(Box::into_raw(Box::new(moonlift_artifact_t { inner: artifact })))
    })();
    match result {
        Ok(ptr) => { clear_last_error(); ptr }
        Err(err) => fail_ptr(err.0),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_object_compile_binary(
    data: *const u8,
    len: usize,
    module_name: *const c_char,
    out: *mut moonlift_bytes_t,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let out = unsafe { out.as_mut() }
            .ok_or_else(|| MoonliftError("moonlift_bytes_t output pointer was null".to_string()))?;
        if data.is_null() {
            return Err(MoonliftError("binary data pointer was null".to_string()));
        }
        let buf = unsafe { std::slice::from_raw_parts(data, len) };
        let module_name = if module_name.is_null() {
            "moonlift_object".to_string()
        } else {
            read_cstr(module_name, "object module name")?
        };
        let cmds = parse_back_command_binary(buf)?;
        let artifact = compile_object(&BackProgram::new(cmds), &module_name)?;
        let mut bytes = artifact.into_bytes().into_boxed_slice();
        out.data = bytes.as_mut_ptr();
        out.len = bytes.len();
        std::mem::forget(bytes);
        Ok(())
    })();
    match result {
        Ok(()) => ok_int(),
        Err(err) => fail_int(err.0),
    }
}
