use std::alloc::{Layout, alloc_zeroed, dealloc};
use std::ptr::NonNull;
use std::sync::atomic::{AtomicU64, Ordering};

pub const HOST_KIND_RECORD: u32 = 1;

pub const HOST_FIELD_BOOL: u32 = 1;
pub const HOST_FIELD_I8: u32 = 2;
pub const HOST_FIELD_I16: u32 = 3;
pub const HOST_FIELD_I32: u32 = 4;
pub const HOST_FIELD_I64: u32 = 5;
pub const HOST_FIELD_U8: u32 = 6;
pub const HOST_FIELD_U16: u32 = 7;
pub const HOST_FIELD_U32: u32 = 8;
pub const HOST_FIELD_U64: u32 = 9;
pub const HOST_FIELD_F32: u32 = 10;
pub const HOST_FIELD_F64: u32 = 11;

static NEXT_SESSION_ID: AtomicU64 = AtomicU64::new(1);

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct MoonHostRef {
    pub session_id: u64,
    pub generation: u32,
    pub kind: u32,
    pub type_id: u32,
    pub tag: u32,
    pub offset: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct MoonHostPtr {
    pub ptr: *mut u8,
    pub session_id: u64,
    pub generation: u32,
    pub kind: u32,
    pub type_id: u32,
    pub tag: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct MoonHostRecordSpec {
    pub type_id: u32,
    pub tag: u32,
    pub size: usize,
    pub align: usize,
    pub first_field: usize,
    pub field_count: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct MoonHostFieldInit {
    pub kind: u32,
    pub offset: usize,
    pub i64_value: i64,
    pub u64_value: u64,
    pub f64_value: f64,
}

impl Default for MoonHostPtr {
    fn default() -> Self {
        Self {
            ptr: std::ptr::null_mut(),
            session_id: 0,
            generation: 0,
            kind: 0,
            type_id: 0,
            tag: 0,
        }
    }
}

struct HostBlock {
    ptr: NonNull<u8>,
    layout: Layout,
    kind: u32,
    type_id: u32,
    tag: u32,
}

impl Drop for HostBlock {
    fn drop(&mut self) {
        unsafe { dealloc(self.ptr.as_ptr(), self.layout); }
    }
}

pub struct HostSession {
    session_id: u64,
    generation: u32,
    blocks: Vec<HostBlock>,
}

fn write_at<T: Copy>(block: &mut HostBlock, offset: usize, value: T) -> Result<(), String> {
    let size = std::mem::size_of::<T>();
    let align = std::mem::align_of::<T>();
    let Some(end) = offset.checked_add(size) else {
        return Err(format!("host field write offset overflow: offset={offset} size={size}"));
    };
    if end > block.layout.size() {
        return Err(format!(
            "host field write out of bounds: offset={offset} size={size} block_size={}",
            block.layout.size()
        ));
    }
    let addr = unsafe { block.ptr.as_ptr().add(offset) };
    if (addr as usize) % align != 0 {
        return Err(format!("host field write is misaligned: offset={offset} align={align}"));
    }
    unsafe { (addr as *mut T).write(value); }
    Ok(())
}

fn write_field_to_block(block: &mut HostBlock, field: MoonHostFieldInit) -> Result<(), String> {
    match field.kind {
        HOST_FIELD_BOOL => write_at::<u8>(block, field.offset, if field.u64_value == 0 { 0 } else { 1 }),
        HOST_FIELD_I8 => write_at::<i8>(block, field.offset, field.i64_value as i8),
        HOST_FIELD_I16 => write_at::<i16>(block, field.offset, field.i64_value as i16),
        HOST_FIELD_I32 => write_at::<i32>(block, field.offset, field.i64_value as i32),
        HOST_FIELD_I64 => write_at::<i64>(block, field.offset, field.i64_value),
        HOST_FIELD_U8 => write_at::<u8>(block, field.offset, field.u64_value as u8),
        HOST_FIELD_U16 => write_at::<u16>(block, field.offset, field.u64_value as u16),
        HOST_FIELD_U32 => write_at::<u32>(block, field.offset, field.u64_value as u32),
        HOST_FIELD_U64 => write_at::<u64>(block, field.offset, field.u64_value),
        HOST_FIELD_F32 => write_at::<f32>(block, field.offset, field.f64_value as f32),
        HOST_FIELD_F64 => write_at::<f64>(block, field.offset, field.f64_value),
        other => Err(format!("unknown host field init kind {other}")),
    }
}

impl HostSession {
    pub fn new() -> Self {
        Self {
            session_id: NEXT_SESSION_ID.fetch_add(1, Ordering::Relaxed),
            generation: 1,
            blocks: Vec::new(),
        }
    }

    pub fn session_id(&self) -> u64 {
        self.session_id
    }

    pub fn generation(&self) -> u32 {
        self.generation
    }

    pub fn reset(&mut self) {
        self.blocks.clear();
        self.generation = self.generation.wrapping_add(1).max(1);
    }

    pub fn alloc_record(
        &mut self,
        type_id: u32,
        tag: u32,
        size: usize,
        align: usize,
    ) -> Result<(MoonHostRef, MoonHostPtr), String> {
        let layout = Layout::from_size_align(size, align)
            .map_err(|e| format!("invalid host record layout size={size} align={align}: {e}"))?;
        let raw = unsafe { alloc_zeroed(layout) };
        let ptr = NonNull::new(raw)
            .ok_or_else(|| format!("failed to allocate host record size={size} align={align}"))?;
        let index = self.blocks.len();
        self.blocks.push(HostBlock {
            ptr,
            layout,
            kind: HOST_KIND_RECORD,
            type_id,
            tag,
        });
        let r = MoonHostRef {
            session_id: self.session_id,
            generation: self.generation,
            kind: HOST_KIND_RECORD,
            type_id,
            tag,
            offset: index as u64,
        };
        let p = MoonHostPtr {
            ptr: ptr.as_ptr(),
            session_id: self.session_id,
            generation: self.generation,
            kind: HOST_KIND_RECORD,
            type_id,
            tag,
        };
        Ok((r, p))
    }

    pub fn write_field(&mut self, r: MoonHostRef, field: MoonHostFieldInit) -> Result<(), String> {
        let block = self.block_for_ref_mut(r)?;
        write_field_to_block(block, field)
    }

    pub fn ptr_for_ref(&self, r: MoonHostRef) -> Result<MoonHostPtr, String> {
        let block = self.block_for_ref(r)?;
        Ok(MoonHostPtr {
            ptr: block.ptr.as_ptr(),
            session_id: self.session_id,
            generation: self.generation,
            kind: block.kind,
            type_id: block.type_id,
            tag: block.tag,
        })
    }

    fn block_for_ref(&self, r: MoonHostRef) -> Result<&HostBlock, String> {
        if r.session_id != self.session_id {
            return Err(format!("host ref belongs to session {}, not {}", r.session_id, self.session_id));
        }
        if r.generation != self.generation {
            return Err(format!("stale host ref generation {}, current {}", r.generation, self.generation));
        }
        let block = self.blocks.get(r.offset as usize)
            .ok_or_else(|| format!("host ref offset {} is out of range", r.offset))?;
        if block.kind != r.kind || block.type_id != r.type_id || block.tag != r.tag {
            return Err("host ref metadata does not match arena block".to_string());
        }
        Ok(block)
    }

    fn block_for_ref_mut(&mut self, r: MoonHostRef) -> Result<&mut HostBlock, String> {
        if r.session_id != self.session_id {
            return Err(format!("host ref belongs to session {}, not {}", r.session_id, self.session_id));
        }
        if r.generation != self.generation {
            return Err(format!("stale host ref generation {}, current {}", r.generation, self.generation));
        }
        let block = self.blocks.get_mut(r.offset as usize)
            .ok_or_else(|| format!("host ref offset {} is out of range", r.offset))?;
        if block.kind != r.kind || block.type_id != r.type_id || block.tag != r.tag {
            return Err("host ref metadata does not match arena block".to_string());
        }
        Ok(block)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn alloc_record_returns_stable_ref_and_ptr() {
        let mut session = HostSession::new();
        let (r, p) = session.alloc_record(7, 3, 32, 8).expect("alloc record");
        assert_eq!(r.session_id, session.session_id());
        assert_eq!(r.generation, session.generation());
        assert_eq!(r.kind, HOST_KIND_RECORD);
        assert_eq!(r.type_id, 7);
        assert_eq!(r.tag, 3);
        assert_eq!(r.offset, 0);
        assert!(!p.ptr.is_null());

        let p2 = session.ptr_for_ref(r).expect("ptr for ref");
        assert_eq!(p2.ptr, p.ptr);
    }

    #[test]
    fn reset_rejects_stale_ref() {
        let mut session = HostSession::new();
        let (r, _) = session.alloc_record(1, 0, 16, 8).expect("alloc record");
        session.reset();
        assert!(session.ptr_for_ref(r).unwrap_err().contains("stale"));
        let (r2, _) = session.alloc_record(1, 0, 16, 8).expect("alloc after reset");
        assert_eq!(r2.offset, 0);
        assert_eq!(r2.generation, session.generation());
    }

    #[test]
    fn writes_scalar_fields_by_offset() {
        #[repr(C)]
        struct TestRecord {
            id: i32,
            active: u8,
            _pad: [u8; 3],
            score: f64,
        }

        let mut session = HostSession::new();
        let (r, p) = session.alloc_record(
            9,
            0,
            std::mem::size_of::<TestRecord>(),
            std::mem::align_of::<TestRecord>(),
        ).expect("alloc record");
        session.write_field(r, MoonHostFieldInit {
            kind: HOST_FIELD_I32,
            offset: 0,
            i64_value: 42,
            u64_value: 0,
            f64_value: 0.0,
        }).expect("write id");
        session.write_field(r, MoonHostFieldInit {
            kind: HOST_FIELD_BOOL,
            offset: 4,
            i64_value: 0,
            u64_value: 1,
            f64_value: 0.0,
        }).expect("write active");
        session.write_field(r, MoonHostFieldInit {
            kind: HOST_FIELD_F64,
            offset: 8,
            i64_value: 0,
            u64_value: 0,
            f64_value: 3.5,
        }).expect("write score");

        let rec = unsafe { &*(p.ptr as *const TestRecord) };
        assert_eq!(rec.id, 42);
        assert_eq!(rec.active, 1);
        assert_eq!(rec.score, 3.5);
    }
}
