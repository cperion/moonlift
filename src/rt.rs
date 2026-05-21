// Moonlift built-in runtime
// No libc dependency — pure core::ptr operations.
// All functions are #[unsafe(no_mangle)] extern "C" for symbol resolution.

use core::ptr;
use core::sync::atomic::{AtomicUsize, Ordering};

const HEAP_SIZE: usize = 64 * 1024; // 64KB default bump page

#[repr(C, align(16))]
struct Heap([u8; HEAP_SIZE]);

static mut HEAP: Heap = Heap([0; HEAP_SIZE]);
static HEAP_OFFSET: AtomicUsize = AtomicUsize::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn __ml_alloc(size: usize, align: usize) -> *mut u8 {
    let align = if align == 0 { 1 } else { align };
    loop {
        let current = HEAP_OFFSET.load(Ordering::Relaxed);
        let misalignment = current % align;
        let adjusted = if misalignment == 0 {
            current
        } else {
            current + align - misalignment
        };
        let next = adjusted + size;
        if next > HEAP_SIZE {
            return ptr::null_mut(); // OOM
        }
        if HEAP_OFFSET
            .compare_exchange_weak(current, next, Ordering::Relaxed, Ordering::Relaxed)
            .is_ok()
        {
            unsafe { return (core::ptr::addr_of_mut!(HEAP) as *mut u8).add(adjusted) }
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn __ml_free(_ptr: *mut u8, _size: usize, _align: usize) {
    // no-op for bump allocator
}

#[unsafe(no_mangle)]
pub extern "C" fn __ml_realloc(
    ptr: *mut u8,
    old_size: usize,
    new_size: usize,
    align: usize,
) -> *mut u8 {
    let new_ptr = __ml_alloc(new_size, align);
    if new_ptr.is_null() {
        return ptr::null_mut();
    }
    let copy_size = if old_size < new_size { old_size } else { new_size };
    unsafe {
        ptr::copy_nonoverlapping(ptr, new_ptr, copy_size);
    }
    __ml_free(ptr, old_size, align);
    new_ptr
}

#[unsafe(no_mangle)]
pub extern "C" fn __ml_memcpy(dst: *mut u8, src: *const u8, n: usize) -> *mut u8 {
    unsafe {
        ptr::copy_nonoverlapping(src, dst, n);
    }
    dst
}

#[unsafe(no_mangle)]
pub extern "C" fn __ml_memset(dst: *mut u8, byte: i32, n: usize) -> *mut u8 {
    unsafe {
        ptr::write_bytes(dst, byte as u8, n);
    }
    dst
}

#[unsafe(no_mangle)]
pub extern "C" fn __ml_memcmp(left: *const u8, right: *const u8, n: usize) -> i32 {
    for i in 0..n {
        unsafe {
            let l = ptr::read(left.add(i));
            let r = ptr::read(right.add(i));
            if l != r {
                return if l < r { -1 } else { 1 };
            }
        }
    }
    0
}
