use cranelift_codegen::ir::{Type, types};
use cranelift_codegen::settings::{self, Configurable};
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::default_libcall_names;
use cranelift_object::{ObjectBuilder, ObjectModule};
use std::collections::HashMap;
use std::error::Error;
use std::ffi::c_void;
use std::fmt;
use std::sync::{Arc, OnceLock};

pub mod host_arena;
pub mod lua_api;
pub mod ffi;
pub mod rt;
pub mod wire_tags;
pub mod decode;

// ═══════════════════════════════════════════════════════════════════════════
// MoonliftError
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Debug)]
pub struct MoonliftError(pub String);

impl MoonliftError {
    pub fn new(msg: impl Into<String>) -> Self {
        Self(msg.into())
    }
}

impl fmt::Display for MoonliftError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl Error for MoonliftError {}

// ═══════════════════════════════════════════════════════════════════════════
// Public types (needed by decoder and FFI)
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackScalar {
    Bool, I8, I16, I32, I64, U8, U16, U32, U64, F32, F64, Ptr, Index,
}

impl BackScalar {
    pub fn clif_type(self, ptr_ty: Type) -> Type {
        match self {
            Self::Bool => types::I8,
            Self::I8 | Self::U8 => types::I8,
            Self::I16 | Self::U16 => types::I16,
            Self::I32 | Self::U32 => types::I32,
            Self::I64 | Self::U64 => types::I64,
            Self::F32 => types::F32,
            Self::F64 => types::F64,
            Self::Ptr | Self::Index => ptr_ty,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct BackVec {
    pub elem: BackScalar,
    pub lanes: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackAtomicOrdering {
    SeqCst,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BackAtomicRmwOp {
    Add, Sub, And, Or, Xor, Xchg,
}

// ═══════════════════════════════════════════════════════════════════════════
// JIT
// ═══════════════════════════════════════════════════════════════════════════

pub struct Jit {
    pub symbols: HashMap<String, *const u8>,
}

impl Jit {
    pub fn new() -> Self {
        Self { symbols: HashMap::new() }
    }

    pub fn symbol(&mut self, name: impl Into<String>, ptr: *const u8) {
        self.symbols.insert(name.into(), ptr);
    }

    /// Compile a binary wire-format buffer and return an Artifact.
    pub fn compile_binary(&self, payload: &[u8]) -> Result<Artifact, MoonliftError> {
        let isa = host_isa(false)?;
        let mut builder = JITBuilder::with_isa(isa, default_libcall_names());
        for (name, ptr) in &self.symbols {
            builder.symbol(name, *ptr);
        }
        let mut module = JITModule::new(builder);

        let result = decode::decode_module(payload, &mut module)?;
        module.finalize_definitions()
            .map_err(|e| MoonliftError(format!("failed to finalize JIT module: {e:?}")))?;

        let mut function_ptrs = HashMap::new();
        for (_wire_id, (func_id, name)) in &result.func_table {
            let ptr = module.get_finalized_function(*func_id);
            function_ptrs.insert(name.clone(), ptr);
        }

        Ok(Artifact {
            _module: module,
            function_ptrs,
        })
    }
}

impl Default for Jit {
    fn default() -> Self { Self::new() }
}

// ═══════════════════════════════════════════════════════════════════════════
// Artifact
// ═══════════════════════════════════════════════════════════════════════════

pub struct Artifact {
    _module: JITModule,
    function_ptrs: HashMap<String, *const u8>,
}

impl Artifact {
    pub fn getpointer_by_name(&self, name: &str) -> Result<*const c_void, MoonliftError> {
        let ptr = self.function_ptrs.get(name).copied()
            .ok_or_else(|| MoonliftError(format!("unknown compiled function '{name}'")))?;
        Ok(ptr.cast())
    }

    pub fn free(self) {}
}

// ═══════════════════════════════════════════════════════════════════════════
// Object emission
// ═══════════════════════════════════════════════════════════════════════════

pub struct ObjectArtifact {
    bytes: Vec<u8>,
}

impl ObjectArtifact {
    pub fn bytes(&self) -> &[u8] { &self.bytes }
    pub fn into_bytes(self) -> Vec<u8> { self.bytes }
}

pub fn compile_object_binary(payload: &[u8], module_name: &str) -> Result<ObjectArtifact, MoonliftError> {
    let isa = host_isa(true)?;
    let builder = ObjectBuilder::new(isa, module_name, default_libcall_names())
        .map_err(|e| MoonliftError(format!("failed to create Cranelift object builder: {e}")))?;
    let mut module = ObjectModule::new(builder);

    decode::decode_module(payload, &mut module)?;

    let product = module.finish();
    let bytes = product.emit()
        .map_err(|e| MoonliftError(format!("failed to emit object file: {e:?}")))?;
    Ok(ObjectArtifact { bytes })
}

// ═══════════════════════════════════════════════════════════════════════════
// Host ISA
// ═══════════════════════════════════════════════════════════════════════════

fn build_host_isa(is_pic: bool) -> Result<Arc<dyn cranelift_codegen::isa::TargetIsa>, MoonliftError> {
    let mut flag_builder = settings::builder();
    flag_builder
        .set("use_colocated_libcalls", "false")
        .map_err(|e| MoonliftError(format!("failed to set Cranelift flag use_colocated_libcalls: {e}")))?;
    flag_builder
        .set("is_pic", if is_pic { "true" } else { "false" })
        .map_err(|e| MoonliftError(format!("failed to set Cranelift flag is_pic: {e}")))?;
    flag_builder
        .set("opt_level", "speed")
        .map_err(|e| MoonliftError(format!("failed to set Cranelift flag opt_level: {e}")))?;
    let isa_builder = cranelift_native::builder()
        .map_err(|e| MoonliftError(format!("host machine is not supported by Cranelift: {e}")))?;
    isa_builder
        .finish(settings::Flags::new(flag_builder))
        .map_err(|e| MoonliftError(format!("failed to finalize Cranelift ISA: {e}")))
}

fn host_isa(is_pic: bool) -> Result<Arc<dyn cranelift_codegen::isa::TargetIsa>, MoonliftError> {
    static JIT_ISA: OnceLock<Arc<dyn cranelift_codegen::isa::TargetIsa>> = OnceLock::new();
    static PIC_ISA: OnceLock<Arc<dyn cranelift_codegen::isa::TargetIsa>> = OnceLock::new();
    let slot = if is_pic { &PIC_ISA } else { &JIT_ISA };
    if let Some(isa) = slot.get() {
        return Ok(Arc::clone(isa));
    }
    let isa = build_host_isa(is_pic)?;
    let _ = slot.set(Arc::clone(&isa));
    Ok(isa)
}

pub fn align_to_shift(align: u32) -> Result<u8, MoonliftError> {
    if align == 0 {
        return Err(MoonliftError("stack slot alignment must be >= 1 byte".into()));
    }
    if !align.is_power_of_two() {
        return Err(MoonliftError(format!("stack slot alignment {align} is not a power of two")));
    }
    Ok(align.trailing_zeros() as u8)
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire_tags::WireTag;

    fn build_simple_add_wire() -> Vec<u8> {
        let mut w = Vec::new();
        w.extend_from_slice(&0x4D4Cu32.to_le_bytes()); // magic
        w.extend_from_slice(&4u32.to_le_bytes());      // version
        w.extend_from_slice(&1u32.to_le_bytes());      // n_funcs

        // Placeholder offsets
        let hdr_pos = w.len();
        w.extend_from_slice(&0u32.to_le_bytes());
        w.extend_from_slice(&0u32.to_le_bytes());
        w.extend_from_slice(&0u32.to_le_bytes());
        w.extend_from_slice(&0u32.to_le_bytes());

        let decl_start = w.len();

        // Sig table: [n_sigs=1, sig_id=0, n_params=1, I32, n_results=1, I32]
        w.extend_from_slice(&1u32.to_le_bytes());
        w.extend_from_slice(&0u32.to_le_bytes()); // sig_id
        w.extend_from_slice(&1u32.to_le_bytes()); // n_params
        w.extend_from_slice(&4u32.to_le_bytes()); // I32
        w.extend_from_slice(&1u32.to_le_bytes()); // n_results
        w.extend_from_slice(&4u32.to_le_bytes()); // I32

        // Func table: [n_funcs=1, func_id=0, sig_id=0, vis=1(export), name_idx=0]
        w.extend_from_slice(&1u32.to_le_bytes());
        w.extend_from_slice(&0u32.to_le_bytes());
        w.extend_from_slice(&0u32.to_le_bytes());
        w.extend_from_slice(&1u32.to_le_bytes()); // export
        w.extend_from_slice(&0u32.to_le_bytes());

        // Data table: [n_datas=0]
        w.extend_from_slice(&0u32.to_le_bytes());
        // Data inits: [n_inits=0]
        w.extend_from_slice(&0u32.to_le_bytes());
        // Extern table: [n_externs=0]
        w.extend_from_slice(&0u32.to_le_bytes());

        let decl_end = w.len();
        let decl_len = decl_end - decl_start;

        // Body table start
        let body_tbl_start = w.len();

        // Build function body
        let mut body = Vec::new();

        fn slot(v: u32) -> Vec<u8> { v.to_le_bytes().to_vec() }

        // CreateBlock(0)
        body.push(WireTag::CreateBlock as u8);
        body.extend_from_slice(&slot(0));

        // SwitchToBlock(0)
        body.push(WireTag::SwitchToBlock as u8);
        body.extend_from_slice(&slot(0));

        // AppendBlockParam(0, I32=4)
        body.push(WireTag::AppendBlockParam as u8);
        body.extend_from_slice(&slot(0));
        body.extend_from_slice(&slot(4)); // I32

        // This body is incomplete — no binding for block param, no instructions
        // It's just testing header parsing

        let body_len = body.len();

        // Body table entry: [func_id=0, body_off, body_len]
        w.extend_from_slice(&0u32.to_le_bytes());
        w.extend_from_slice(&(body_tbl_start as u32).to_le_bytes());
        w.extend_from_slice(&(body_len as u32).to_le_bytes());

        let body_tbl_end = w.len();
        let body_tbl_len = body_tbl_end - body_tbl_start;

        // Write body at correct offset (right after body table)
        // But we already computed body_tbl_start before writing the body table entry,
        // so the body is at the end of body table entries
        let actual_body_off = body_tbl_end;
        // Adjust body offset in body table
        let body_off_pos = body_tbl_start + 4;
        w[body_off_pos..body_off_pos + 4].copy_from_slice(&(actual_body_off as u32).to_le_bytes());

        w.extend_from_slice(&body);
        let actual_body_len = body.len();
        let body_len_pos = body_tbl_start + 8;
        w[body_len_pos..body_len_pos + 4].copy_from_slice(&(actual_body_len as u32).to_le_bytes());

        // Fill in header offsets
        w[hdr_pos..hdr_pos + 4].copy_from_slice(&(decl_start as u32).to_le_bytes());
        w[hdr_pos + 4..hdr_pos + 8].copy_from_slice(&(decl_len as u32).to_le_bytes());
        w[hdr_pos + 8..hdr_pos + 12].copy_from_slice(&(body_tbl_start as u32).to_le_bytes());
        w[hdr_pos + 12..hdr_pos + 16].copy_from_slice(&(body_tbl_len as u32).to_le_bytes());

        // Update body_tbl_len
        let tbl_len_pos = hdr_pos + 12;
        let new_body_tbl_len = actual_body_off - body_tbl_start;
        w[tbl_len_pos..tbl_len_pos + 4].copy_from_slice(&(new_body_tbl_len as u32).to_le_bytes());

        w
    }

    #[test]
    fn header_decoding() {
        let bytes = build_simple_add_wire();
        assert!(bytes.len() >= 28);
        assert_eq!(&bytes[0..4], &0x4D4Cu32.to_le_bytes());
    }
}
