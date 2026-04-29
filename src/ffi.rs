use crate::{
    Artifact, BackAccessId, BackAccessMode, BackAlignment, BackBlockId, BackCmd, BackDataId,
    BackDereference, BackExternId, BackFloatSemantics, BackFuncId, BackIntExact,
    BackIntOverflow, BackIntSemantics, BackMemoryInfo, BackMotion, BackProgram, BackScalar,
    BackSigId, BackStackSlotId, BackSwitchCase, BackTrap, BackValId, BackVec, Jit, MoonliftError,
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
pub struct moonlift_program_t {
    cmds: Vec<BackCmd>,
}

#[repr(C)]
pub struct moonlift_artifact_t {
    inner: Artifact,
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

fn read_memory_info(
    access: *const c_char,
    alignment_kind: u32,
    alignment_bytes: u32,
    dereference_kind: u32,
    dereference_bytes: u32,
    trap_kind: u32,
    motion_kind: u32,
    mode_kind: u32,
) -> Result<BackMemoryInfo, MoonliftError> {
    Ok(BackMemoryInfo::new(
        BackAccessId::from(read_cstr(access, "memory access id")?),
        read_alignment(alignment_kind, alignment_bytes)?,
        read_dereference(dereference_kind, dereference_bytes)?,
        read_trap(trap_kind)?,
        read_motion(motion_kind)?,
        read_access_mode(mode_kind)?,
    ))
}

fn read_scalar_slice(ptr: *const u32, len: usize, what: &str) -> Result<Vec<BackScalar>, MoonliftError> {
    if len == 0 {
        return Ok(Vec::new());
    }
    if ptr.is_null() {
        return Err(MoonliftError(format!("{what} array pointer was null with len={len}")));
    }
    let raw = unsafe { std::slice::from_raw_parts(ptr, len) };
    raw.iter().map(|code| read_scalar(*code)).collect()
}

fn read_string_array(ptr: *const *const c_char, len: usize, what: &str) -> Result<Vec<String>, MoonliftError> {
    if len == 0 {
        return Ok(Vec::new());
    }
    if ptr.is_null() {
        return Err(MoonliftError(format!("{what} pointer array was null with len={len}")));
    }
    let raw = unsafe { std::slice::from_raw_parts(ptr, len) };
    raw.iter()
        .enumerate()
        .map(|(i, p)| read_cstr(*p, &format!("{what}[{i}]")))
        .collect()
}

fn val_ids(ptr: *const *const c_char, len: usize, what: &str) -> Result<Vec<BackValId>, MoonliftError> {
    Ok(read_string_array(ptr, len, what)?
        .into_iter()
        .map(BackValId::from)
        .collect())
}

fn read_switch_cases(
    raw_ptr: *const *const c_char,
    dest_ptr: *const *const c_char,
    len: usize,
) -> Result<Vec<BackSwitchCase>, MoonliftError> {
    let raws = read_string_array(raw_ptr, len, "switch case raws")?;
    let dests = read_string_array(dest_ptr, len, "switch case dests")?;
    let mut cases = Vec::with_capacity(len);
    for i in 0..len {
        cases.push(BackSwitchCase::new(raws[i].clone(), BackBlockId::from(dests[i].clone())));
    }
    Ok(cases)
}

fn push_cmd(program: &mut moonlift_program_t, cmd: BackCmd) {
    program.cmds.push(cmd);
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

fn parse_back_command_tape(payload: &str) -> Result<Vec<BackCmd>, MoonliftError> {
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
    Box::into_raw(Box::new(moonlift_jit_t { inner: Jit::new() }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_jit_free(ptr: *mut moonlift_jit_t) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_new() -> *mut moonlift_program_t {
    clear_last_error();
    Box::into_raw(Box::new(moonlift_program_t { cmds: Vec::new() }))
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_free(ptr: *mut moonlift_program_t) {
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
pub extern "C" fn moonlift_jit_compile(
    jit: *mut moonlift_jit_t,
    program: *const moonlift_program_t,
) -> *mut moonlift_artifact_t {
    let result: Result<_, MoonliftError> = (|| {
        let jit = require_ptr(jit, "moonlift_jit_t")?;
        let program = unsafe { program.as_ref() }
            .ok_or_else(|| MoonliftError("moonlift_program_t pointer was null".to_string()))?;
        let artifact = jit.inner.compile(&BackProgram::new(program.cmds.clone()))?;
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

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_create_sig(
    program: *mut moonlift_program_t,
    sig: *const c_char,
    params: *const u32,
    params_len: usize,
    results: *const u32,
    results_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let sig = read_cstr(sig, "signature id")?;
        let params = read_scalar_slice(params, params_len, "signature params")?;
        let results = read_scalar_slice(results, results_len, "signature results")?;
        push_cmd(program, BackCmd::CreateSig(BackSigId::from(sig), params, results));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_data(
    program: *mut moonlift_program_t,
    data: *const c_char,
    size: u32,
    align: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareData(BackDataId::from(read_cstr(data, "data id")?), size, align));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_zero(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    size: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitZero(BackDataId::from(read_cstr(data, "data id")?), offset, size));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_int(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    ty: u32,
    raw: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitInt(
            BackDataId::from(read_cstr(data, "data id")?),
            offset,
            read_scalar(ty)?,
            read_cstr(raw, "integer literal")?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_float(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    ty: u32,
    raw: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitFloat(
            BackDataId::from(read_cstr(data, "data id")?),
            offset,
            read_scalar(ty)?,
            read_cstr(raw, "float literal")?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_init_bool(
    program: *mut moonlift_program_t,
    data: *const c_char,
    offset: u32,
    value: c_int,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataInitBool(BackDataId::from(read_cstr(data, "data id")?), offset, value != 0));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_func_local(
    program: *mut moonlift_program_t,
    func: *const c_char,
    sig: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareFuncLocal(BackFuncId::from(read_cstr(func, "function id")?), BackSigId::from(read_cstr(sig, "signature id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_func_export(
    program: *mut moonlift_program_t,
    func: *const c_char,
    sig: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareFuncExport(BackFuncId::from(read_cstr(func, "function id")?), BackSigId::from(read_cstr(sig, "signature id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_declare_func_extern(
    program: *mut moonlift_program_t,
    func: *const c_char,
    symbol: *const c_char,
    sig: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DeclareFuncExtern(
            BackExternId::from(read_cstr(func, "extern id")?),
            read_cstr(symbol, "extern symbol")?,
            BackSigId::from(read_cstr(sig, "signature id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_begin_func(program: *mut moonlift_program_t, func: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::BeginFunc(BackFuncId::from(read_cstr(func, "function id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_create_block(program: *mut moonlift_program_t, block: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::CreateBlock(BackBlockId::from(read_cstr(block, "block id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_switch_to_block(program: *mut moonlift_program_t, block: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::SwitchToBlock(BackBlockId::from(read_cstr(block, "block id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_seal_block(program: *mut moonlift_program_t, block: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::SealBlock(BackBlockId::from(read_cstr(block, "block id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_bind_entry_params(
    program: *mut moonlift_program_t,
    block: *const c_char,
    values: *const *const c_char,
    values_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::BindEntryParams(BackBlockId::from(read_cstr(block, "block id")?), val_ids(values, values_len, "entry params")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_append_block_param(
    program: *mut moonlift_program_t,
    block: *const c_char,
    value: *const c_char,
    ty: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::AppendBlockParam(
            BackBlockId::from(read_cstr(block, "block id")?),
            BackValId::from(read_cstr(value, "value id")?),
            read_scalar(ty)?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_append_vec_block_param(
    program: *mut moonlift_program_t,
    block: *const c_char,
    value: *const c_char,
    elem: u32,
    lanes: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::AppendVecBlockParam(
            BackBlockId::from(read_cstr(block, "block id")?),
            BackValId::from(read_cstr(value, "value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_create_stack_slot(
    program: *mut moonlift_program_t,
    slot: *const c_char,
    size: u32,
    align: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::CreateStackSlot(BackStackSlotId::from(read_cstr(slot, "stack slot id")?), size, align));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_alias(program: *mut moonlift_program_t, dst: *const c_char, src: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Alias(BackValId::from(read_cstr(dst, "dst value id")?), BackValId::from(read_cstr(src, "src value id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_stack_addr(program: *mut moonlift_program_t, dst: *const c_char, slot: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::StackAddr(BackValId::from(read_cstr(dst, "dst value id")?), BackStackSlotId::from(read_cstr(slot, "stack slot id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_data_addr(program: *mut moonlift_program_t, dst: *const c_char, data: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::DataAddr(BackValId::from(read_cstr(dst, "dst value id")?), BackDataId::from(read_cstr(data, "data id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_func_addr(program: *mut moonlift_program_t, dst: *const c_char, func: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::FuncAddr(BackValId::from(read_cstr(dst, "dst value id")?), BackFuncId::from(read_cstr(func, "function id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_extern_addr(program: *mut moonlift_program_t, dst: *const c_char, func: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ExternAddr(BackValId::from(read_cstr(dst, "dst value id")?), BackExternId::from(read_cstr(func, "extern id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_int(program: *mut moonlift_program_t, dst: *const c_char, ty: u32, raw: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstInt(BackValId::from(read_cstr(dst, "dst value id")?), read_scalar(ty)?, read_cstr(raw, "integer literal")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_float(program: *mut moonlift_program_t, dst: *const c_char, ty: u32, raw: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstFloat(BackValId::from(read_cstr(dst, "dst value id")?), read_scalar(ty)?, read_cstr(raw, "float literal")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_bool(program: *mut moonlift_program_t, dst: *const c_char, value: c_int) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstBool(BackValId::from(read_cstr(dst, "dst value id")?), value != 0));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_const_null(program: *mut moonlift_program_t, dst: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ConstNull(BackValId::from(read_cstr(dst, "dst value id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn unary_cmd(op: u32, dst: BackValId, ty: BackScalar, value: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Ineg(dst, ty, value)),
        2 => Ok(BackCmd::Fneg(dst, ty, value)),
        3 => Ok(BackCmd::Bnot(dst, ty, value)),
        4 => Ok(BackCmd::BoolNot(dst, value)),
        5 => Ok(BackCmd::Popcount(dst, ty, value)),
        6 => Ok(BackCmd::Clz(dst, ty, value)),
        7 => Ok(BackCmd::Ctz(dst, ty, value)),
        8 => Ok(BackCmd::Bswap(dst, ty, value)),
        9 => Ok(BackCmd::Sqrt(dst, ty, value)),
        10 => Ok(BackCmd::Abs(dst, ty, value)),
        11 => Ok(BackCmd::Floor(dst, ty, value)),
        12 => Ok(BackCmd::Ceil(dst, ty, value)),
        13 => Ok(BackCmd::TruncFloat(dst, ty, value)),
        14 => Ok(BackCmd::Round(dst, ty, value)),
        _ => Err(MoonliftError(format!("unknown unary opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_unary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = unary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(value, "input value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn vector_binary_cmd(op: u32, dst: BackValId, vec: BackVec, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::VecIadd(dst, vec, lhs, rhs)),
        4 => Ok(BackCmd::VecIsub(dst, vec, lhs, rhs)),
        2 => Ok(BackCmd::VecImul(dst, vec, lhs, rhs)),
        3 => Ok(BackCmd::VecBand(dst, vec, lhs, rhs)),
        5 => Ok(BackCmd::VecBor(dst, vec, lhs, rhs)),
        6 => Ok(BackCmd::VecBxor(dst, vec, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown vector binary opcode {op}"))),
    }
}

fn vector_compare_cmd(op: u32, dst: BackValId, vec: BackVec, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::VecIcmpEq(dst, vec, lhs, rhs)),
        2 => Ok(BackCmd::VecIcmpNe(dst, vec, lhs, rhs)),
        3 => Ok(BackCmd::VecSIcmpLt(dst, vec, lhs, rhs)),
        4 => Ok(BackCmd::VecSIcmpLe(dst, vec, lhs, rhs)),
        5 => Ok(BackCmd::VecSIcmpGt(dst, vec, lhs, rhs)),
        6 => Ok(BackCmd::VecSIcmpGe(dst, vec, lhs, rhs)),
        7 => Ok(BackCmd::VecUIcmpLt(dst, vec, lhs, rhs)),
        8 => Ok(BackCmd::VecUIcmpLe(dst, vec, lhs, rhs)),
        9 => Ok(BackCmd::VecUIcmpGt(dst, vec, lhs, rhs)),
        10 => Ok(BackCmd::VecUIcmpGe(dst, vec, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown vector compare opcode {op}"))),
    }
}

fn vector_mask_cmd(op: u32, dst: BackValId, vec: BackVec, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::VecMaskNot(dst, vec, lhs)),
        2 => Ok(BackCmd::VecMaskAnd(dst, vec, lhs, rhs)),
        3 => Ok(BackCmd::VecMaskOr(dst, vec, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown vector mask opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_splat(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::VecSplat(
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(value, "input value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_binary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = vector_binary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_compare(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = vector_compare_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_select(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    mask: *const c_char,
    then_value: *const c_char,
    else_value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::VecSelect(
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(mask, "mask value id")?),
            BackValId::from(read_cstr(then_value, "then value id")?),
            BackValId::from(read_cstr(else_value, "else value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_mask(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = vector_mask_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_insert_lane(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    value: *const c_char,
    lane_value: *const c_char,
    lane: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::VecInsertLane(
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(value, "input vector value id")?),
            BackValId::from(read_cstr(lane_value, "lane value id")?),
            lane,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_extract_lane(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    elem: u32,
    value: *const c_char,
    lane: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::VecExtractLane(
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(elem)?,
            BackValId::from(read_cstr(value, "input vector value id")?),
            lane,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn compare_cmd(op: u32, dst: BackValId, ty: BackScalar, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::IcmpEq(dst, ty, lhs, rhs)),
        2 => Ok(BackCmd::IcmpNe(dst, ty, lhs, rhs)),
        3 => Ok(BackCmd::SIcmpLt(dst, ty, lhs, rhs)),
        4 => Ok(BackCmd::SIcmpLe(dst, ty, lhs, rhs)),
        5 => Ok(BackCmd::SIcmpGt(dst, ty, lhs, rhs)),
        6 => Ok(BackCmd::SIcmpGe(dst, ty, lhs, rhs)),
        7 => Ok(BackCmd::UIcmpLt(dst, ty, lhs, rhs)),
        8 => Ok(BackCmd::UIcmpLe(dst, ty, lhs, rhs)),
        9 => Ok(BackCmd::UIcmpGt(dst, ty, lhs, rhs)),
        10 => Ok(BackCmd::UIcmpGe(dst, ty, lhs, rhs)),
        11 => Ok(BackCmd::FCmpEq(dst, ty, lhs, rhs)),
        12 => Ok(BackCmd::FCmpNe(dst, ty, lhs, rhs)),
        13 => Ok(BackCmd::FCmpLt(dst, ty, lhs, rhs)),
        14 => Ok(BackCmd::FCmpLe(dst, ty, lhs, rhs)),
        15 => Ok(BackCmd::FCmpGt(dst, ty, lhs, rhs)),
        16 => Ok(BackCmd::FCmpGe(dst, ty, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown compare opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_compare(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = compare_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_ptr_add(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    base: *const c_char,
    byte_offset: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::PtrAdd(
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackValId::from(read_cstr(base, "base value id")?),
            BackValId::from(read_cstr(byte_offset, "byte offset value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_ptr_offset(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    base: *const c_char,
    index: *const c_char,
    elem_size: u32,
    const_offset: i64,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::PtrOffset(
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackValId::from(read_cstr(base, "base value id")?),
            BackValId::from(read_cstr(index, "index value id")?),
            elem_size,
            const_offset,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn int_binary_cmd(op: u32, dst: BackValId, ty: BackScalar, semantics: BackIntSemantics, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Iadd(dst, ty, semantics, lhs, rhs)),
        2 => Ok(BackCmd::Isub(dst, ty, semantics, lhs, rhs)),
        3 => Ok(BackCmd::Imul(dst, ty, semantics, lhs, rhs)),
        4 => Ok(BackCmd::Sdiv(dst, ty, semantics, lhs, rhs)),
        5 => Ok(BackCmd::Udiv(dst, ty, semantics, lhs, rhs)),
        6 => Ok(BackCmd::Srem(dst, ty, semantics, lhs, rhs)),
        7 => Ok(BackCmd::Urem(dst, ty, semantics, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown int binary opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_int_binary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    overflow_kind: u32,
    exact_kind: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let semantics = read_int_semantics(overflow_kind, exact_kind)?;
        let cmd = int_binary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            semantics,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn bit_binary_cmd(op: u32, dst: BackValId, ty: BackScalar, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Band(dst, ty, lhs, rhs)),
        2 => Ok(BackCmd::Bor(dst, ty, lhs, rhs)),
        3 => Ok(BackCmd::Bxor(dst, ty, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown bit binary opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_bit_binary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = bit_binary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn shift_cmd(op: u32, dst: BackValId, ty: BackScalar, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Ishl(dst, ty, lhs, rhs)),
        2 => Ok(BackCmd::Ushr(dst, ty, lhs, rhs)),
        3 => Ok(BackCmd::Sshr(dst, ty, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown shift opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_shift(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = shift_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn rotate_cmd(op: u32, dst: BackValId, ty: BackScalar, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Rotl(dst, ty, lhs, rhs)),
        2 => Ok(BackCmd::Rotr(dst, ty, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown rotate opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_rotate(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = rotate_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn float_binary_cmd(op: u32, dst: BackValId, ty: BackScalar, semantics: BackFloatSemantics, lhs: BackValId, rhs: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Fadd(dst, ty, semantics, lhs, rhs)),
        2 => Ok(BackCmd::Fsub(dst, ty, semantics, lhs, rhs)),
        3 => Ok(BackCmd::Fmul(dst, ty, semantics, lhs, rhs)),
        4 => Ok(BackCmd::Fdiv(dst, ty, semantics, lhs, rhs)),
        _ => Err(MoonliftError(format!("unknown float binary opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_float_binary(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    semantics_kind: u32,
    lhs: *const c_char,
    rhs: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = float_binary_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            read_float_semantics(semantics_kind)?,
            BackValId::from(read_cstr(lhs, "lhs value id")?),
            BackValId::from(read_cstr(rhs, "rhs value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

fn cast_cmd(op: u32, dst: BackValId, ty: BackScalar, value: BackValId) -> Result<BackCmd, MoonliftError> {
    match op {
        1 => Ok(BackCmd::Bitcast(dst, ty, value)),
        2 => Ok(BackCmd::Ireduce(dst, ty, value)),
        3 => Ok(BackCmd::Sextend(dst, ty, value)),
        4 => Ok(BackCmd::Uextend(dst, ty, value)),
        5 => Ok(BackCmd::Fpromote(dst, ty, value)),
        6 => Ok(BackCmd::Fdemote(dst, ty, value)),
        7 => Ok(BackCmd::SToF(dst, ty, value)),
        8 => Ok(BackCmd::UToF(dst, ty, value)),
        9 => Ok(BackCmd::FToS(dst, ty, value)),
        10 => Ok(BackCmd::FToU(dst, ty, value)),
        _ => Err(MoonliftError(format!("unknown cast opcode {op}"))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_fma(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    ty: u32,
    semantics_kind: u32,
    a: *const c_char,
    b: *const c_char,
    c: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Fma(
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            read_float_semantics(semantics_kind)?,
            BackValId::from(read_cstr(a, "ternary arg a")?),
            BackValId::from(read_cstr(b, "ternary arg b")?),
            BackValId::from(read_cstr(c, "ternary arg c")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_cast(
    program: *mut moonlift_program_t,
    op: u32,
    dst: *const c_char,
    ty: u32,
    value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let cmd = cast_cmd(
            op,
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(value, "input value id")?),
        )?;
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_load_info(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    ty: u32,
    addr: *const c_char,
    access: *const c_char,
    alignment_kind: u32,
    alignment_bytes: u32,
    dereference_kind: u32,
    dereference_bytes: u32,
    trap_kind: u32,
    motion_kind: u32,
    mode_kind: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let memory = read_memory_info(access, alignment_kind, alignment_bytes, dereference_kind, dereference_bytes, trap_kind, motion_kind, mode_kind)?;
        push_cmd(program, BackCmd::LoadInfo(
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(addr, "address value id")?),
            memory,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_store_info(
    program: *mut moonlift_program_t,
    ty: u32,
    addr: *const c_char,
    value: *const c_char,
    access: *const c_char,
    alignment_kind: u32,
    alignment_bytes: u32,
    dereference_kind: u32,
    dereference_bytes: u32,
    trap_kind: u32,
    motion_kind: u32,
    mode_kind: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let memory = read_memory_info(access, alignment_kind, alignment_bytes, dereference_kind, dereference_bytes, trap_kind, motion_kind, mode_kind)?;
        push_cmd(program, BackCmd::StoreInfo(
            read_scalar(ty)?,
            BackValId::from(read_cstr(addr, "address value id")?),
            BackValId::from(read_cstr(value, "stored value id")?),
            memory,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_load_info(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    elem: u32,
    lanes: u32,
    addr: *const c_char,
    access: *const c_char,
    alignment_kind: u32,
    alignment_bytes: u32,
    dereference_kind: u32,
    dereference_bytes: u32,
    trap_kind: u32,
    motion_kind: u32,
    mode_kind: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let memory = read_memory_info(access, alignment_kind, alignment_bytes, dereference_kind, dereference_bytes, trap_kind, motion_kind, mode_kind)?;
        push_cmd(program, BackCmd::VecLoadInfo(
            BackValId::from(read_cstr(dst, "dst value id")?),
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(addr, "address value id")?),
            memory,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_vec_store_info(
    program: *mut moonlift_program_t,
    elem: u32,
    lanes: u32,
    addr: *const c_char,
    value: *const c_char,
    access: *const c_char,
    alignment_kind: u32,
    alignment_bytes: u32,
    dereference_kind: u32,
    dereference_bytes: u32,
    trap_kind: u32,
    motion_kind: u32,
    mode_kind: u32,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let memory = read_memory_info(access, alignment_kind, alignment_bytes, dereference_kind, dereference_bytes, trap_kind, motion_kind, mode_kind)?;
        push_cmd(program, BackCmd::VecStoreInfo(
            BackVec::new(read_scalar(elem)?, lanes),
            BackValId::from(read_cstr(addr, "address value id")?),
            BackValId::from(read_cstr(value, "stored value id")?),
            memory,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_memcpy(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    src: *const c_char,
    len: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Memcpy(
            BackValId::from(read_cstr(dst, "memcpy dst value id")?),
            BackValId::from(read_cstr(src, "memcpy src value id")?),
            BackValId::from(read_cstr(len, "memcpy len value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_memset(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    byte: *const c_char,
    len: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Memset(
            BackValId::from(read_cstr(dst, "memset dst value id")?),
            BackValId::from(read_cstr(byte, "memset byte value id")?),
            BackValId::from(read_cstr(len, "memset len value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_select(
    program: *mut moonlift_program_t,
    dst: *const c_char,
    ty: u32,
    cond: *const c_char,
    then_value: *const c_char,
    else_value: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Select(
            BackValId::from(read_cstr(dst, "dst value id")?),
            read_scalar(ty)?,
            BackValId::from(read_cstr(cond, "condition value id")?),
            BackValId::from(read_cstr(then_value, "then value id")?),
            BackValId::from(read_cstr(else_value, "else value id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_call_value(
    program: *mut moonlift_program_t,
    kind: u32,
    dst: *const c_char,
    ty: u32,
    target: *const c_char,
    sig: *const c_char,
    args: *const *const c_char,
    args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let dst = BackValId::from(read_cstr(dst, "dst value id")?);
        let ty = read_scalar(ty)?;
        let target = read_cstr(target, "call target id")?;
        let sig = BackSigId::from(read_cstr(sig, "signature id")?);
        let args = val_ids(args, args_len, "call args")?;
        let cmd = match kind {
            1 => BackCmd::CallValueDirect(dst, ty, BackFuncId::from(target), sig, args),
            2 => BackCmd::CallValueExtern(dst, ty, BackExternId::from(target), sig, args),
            3 => BackCmd::CallValueIndirect(dst, ty, BackValId::from(target), sig, args),
            _ => return Err(MoonliftError(format!("unknown call kind {kind}"))),
        };
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_call_stmt(
    program: *mut moonlift_program_t,
    kind: u32,
    target: *const c_char,
    sig: *const c_char,
    args: *const *const c_char,
    args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let target = read_cstr(target, "call target id")?;
        let sig = BackSigId::from(read_cstr(sig, "signature id")?);
        let args = val_ids(args, args_len, "call args")?;
        let cmd = match kind {
            1 => BackCmd::CallStmtDirect(BackFuncId::from(target), sig, args),
            2 => BackCmd::CallStmtExtern(BackExternId::from(target), sig, args),
            3 => BackCmd::CallStmtIndirect(BackValId::from(target), sig, args),
            _ => return Err(MoonliftError(format!("unknown call kind {kind}"))),
        };
        push_cmd(program, cmd);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_jump(
    program: *mut moonlift_program_t,
    dest: *const c_char,
    args: *const *const c_char,
    args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Jump(BackBlockId::from(read_cstr(dest, "destination block id")?), val_ids(args, args_len, "jump args")?));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_brif(
    program: *mut moonlift_program_t,
    cond: *const c_char,
    then_block: *const c_char,
    then_args: *const *const c_char,
    then_args_len: usize,
    else_block: *const c_char,
    else_args: *const *const c_char,
    else_args_len: usize,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::BrIf(
            BackValId::from(read_cstr(cond, "condition value id")?),
            BackBlockId::from(read_cstr(then_block, "then block id")?),
            val_ids(then_args, then_args_len, "then args")?,
            BackBlockId::from(read_cstr(else_block, "else block id")?),
            val_ids(else_args, else_args_len, "else args")?,
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_switch_int(
    program: *mut moonlift_program_t,
    value: *const c_char,
    ty_code: u32,
    case_raws: *const *const c_char,
    case_dests: *const *const c_char,
    cases_len: usize,
    default_dest: *const c_char,
) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        let ty = read_scalar(ty_code)?;
        let cases = read_switch_cases(case_raws, case_dests, cases_len)?;
        push_cmd(program, BackCmd::SwitchInt(
            BackValId::from(read_cstr(value, "switch value id")?),
            ty,
            cases,
            BackBlockId::from(read_cstr(default_dest, "switch default block id")?),
        ));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_return_void(program: *mut moonlift_program_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ReturnVoid);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_return_value(program: *mut moonlift_program_t, value: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::ReturnValue(BackValId::from(read_cstr(value, "return value id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_trap(program: *mut moonlift_program_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::Trap);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_finish_func(program: *mut moonlift_program_t, func: *const c_char) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::FinishFunc(BackFuncId::from(read_cstr(func, "function id")?)));
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}

#[unsafe(no_mangle)]
pub extern "C" fn moonlift_program_cmd_finalize_module(program: *mut moonlift_program_t) -> c_int {
    let result: Result<_, MoonliftError> = (|| {
        let program = require_ptr(program, "moonlift_program_t")?;
        push_cmd(program, BackCmd::FinalizeModule);
        Ok(())
    })();
    match result { Ok(()) => ok_int(), Err(err) => fail_int(err.0) }
}
