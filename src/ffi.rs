use crate::{
    Artifact, BackAccessId, BackAccessMode, BackAlignment, BackBlockId, BackCmd, BackDataId,
    BackDereference, BackExternId, BackFloatSemantics, BackFuncId, BackIntExact,
    BackIntOverflow, BackIntSemantics, BackMemoryInfo, BackMotion, BackProgram, BackScalar,
    BackSigId, BackStackSlotId, BackSwitchCase, BackTrap, BackValId, BackVec, Jit, MoonliftError,
    compile_object,
};
use crate::host_arena::{HostSession, MoonHostFieldInit, MoonHostPtr, MoonHostRecordSpec, MoonHostRef};
use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::ptr;

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
