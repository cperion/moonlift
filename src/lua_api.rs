use std::alloc::{Layout, alloc_zeroed, dealloc};
use std::ffi::{c_char, c_int, c_void};
use std::cell::RefCell;

unsafe extern "C" {
    fn memcmp(s1: *const c_void, s2: *const c_void, n: usize) -> c_int;
}

thread_local! {
    static SCRATCH: RefCell<Vec<Vec<u8>>> = RefCell::new(Vec::new());
}

// Single generic scratch function. Returns ptr(u8) to zeroed memory,
// auto-freed on function return (thread-local, reused per slot).
//   slot: arena index (0..N, auto-grows)
//   elem_size: bytes per element
//   count: number of elements
#[unsafe(no_mangle)]
pub extern "C" fn moonlift_scratch_raw(slot: i32, elem_size: i32, count: i32) -> *mut u8 {
    if slot < 0 || elem_size <= 0 || count <= 0 {
        return std::ptr::null_mut();
    }
    let slot = slot as usize;
    let byte_count = (elem_size as usize).saturating_mul(count as usize);
    if byte_count == 0 {
        return std::ptr::null_mut();
    }
    SCRATCH.with(|scratch| {
        let mut scratch = scratch.borrow_mut();
        if scratch.len() <= slot {
            scratch.resize(slot + 1, Vec::new());
        }
        let buf = &mut scratch[slot];
        if buf.len() < byte_count {
            buf.resize(byte_count, 0);
        } else {
            buf[..byte_count].fill(0);
        }
        buf.as_mut_ptr()
    })
}

pub extern "C" fn moonlift_alloc_i32(count: i32) -> *mut i32 {
    if count <= 0 {
        return std::ptr::null_mut();
    }
    let Ok(layout) = Layout::array::<i32>(count as usize) else {
        return std::ptr::null_mut();
    };
    unsafe { alloc_zeroed(layout).cast::<i32>() }
}

pub extern "C" fn moonlift_free_i32(ptr: *mut i32, count: i32) -> c_int {
    if ptr.is_null() || count <= 0 {
        return 1;
    }
    if let Ok(layout) = Layout::array::<i32>(count as usize) {
        unsafe { dealloc(ptr.cast::<u8>(), layout) };
    }
    1
}

pub extern "C" fn moonlift_lua_arg_lstring_ptr(l: *mut mlua::ffi::lua_State, idx: c_int) -> *const u8 {
    let mut len = 0usize;
    unsafe { mlua::ffi::lua_tolstring(l, idx, &mut len).cast::<u8>() }
}

pub extern "C" fn moonlift_lua_arg_lstring_len(l: *mut mlua::ffi::lua_State, idx: c_int) -> isize {
    let mut len = 0usize;
    unsafe {
        let ptr = mlua::ffi::lua_tolstring(l, idx, &mut len);
        if ptr.is_null() { -1 } else { len as isize }
    }
}

pub extern "C" fn moonlift_lua_raw_gettop(l: *mut mlua::ffi::lua_State) -> c_int {
    unsafe { mlua::ffi::lua_gettop(l) }
}

pub extern "C" fn moonlift_lua_raw_settop(l: *mut mlua::ffi::lua_State, idx: c_int) {
    unsafe { mlua::ffi::lua_settop(l, idx) };
}

pub extern "C" fn moonlift_lua_raw_type(l: *mut mlua::ffi::lua_State, idx: c_int) -> c_int {
    unsafe { mlua::ffi::lua_type(l, idx) }
}

pub extern "C" fn moonlift_lua_raw_tolstring(l: *mut mlua::ffi::lua_State, idx: c_int, len: *mut usize) -> *const u8 {
    unsafe { mlua::ffi::lua_tolstring(l, idx, len).cast::<u8>() }
}

pub extern "C" fn moonlift_lua_raw_toboolean(l: *mut mlua::ffi::lua_State, idx: c_int) -> c_int {
    unsafe { mlua::ffi::lua_toboolean(l, idx) }
}

pub extern "C" fn moonlift_lua_raw_tonumber(l: *mut mlua::ffi::lua_State, idx: c_int) -> f64 {
    unsafe { mlua::ffi::lua_tonumber(l, idx) }
}

pub extern "C" fn moonlift_lua_raw_pushvalue(l: *mut mlua::ffi::lua_State, idx: c_int) {
    unsafe { mlua::ffi::lua_pushvalue(l, idx) };
}

pub extern "C" fn moonlift_lua_raw_pushnil(l: *mut mlua::ffi::lua_State) {
    unsafe { mlua::ffi::lua_pushnil(l) };
}

pub extern "C" fn moonlift_lua_raw_pushboolean(l: *mut mlua::ffi::lua_State, b: c_int) {
    unsafe { mlua::ffi::lua_pushboolean(l, b) };
}

pub extern "C" fn moonlift_lua_raw_pushnumber(l: *mut mlua::ffi::lua_State, n: f64) {
    unsafe { mlua::ffi::lua_pushnumber(l, n) };
}

pub extern "C" fn moonlift_lua_raw_pushlstring(l: *mut mlua::ffi::lua_State, s: *const c_char, len: usize) {
    unsafe { mlua::ffi::lua_pushlstring_(l, s, len) };
}

pub extern "C" fn moonlift_lua_raw_rawgeti(l: *mut mlua::ffi::lua_State, idx: c_int, n: c_int) {
    unsafe { mlua::ffi::lua_rawgeti_(l, idx, n) };
}

pub extern "C" fn moonlift_lua_raw_rawseti(l: *mut mlua::ffi::lua_State, idx: c_int, n: c_int) {
    unsafe { mlua::ffi::lua_rawseti_(l, idx, n) };
}

pub extern "C" fn moonlift_lua_raw_lref(l: *mut mlua::ffi::lua_State, t: c_int) -> c_int {
    unsafe { mlua::ffi::luaL_ref(l, t) }
}

pub extern "C" fn moonlift_lua_raw_lunref(l: *mut mlua::ffi::lua_State, t: c_int, r: c_int) {
    unsafe { mlua::ffi::luaL_unref(l, t, r) };
}

pub extern "C" fn moonlift_lua_raw_pcall(l: *mut mlua::ffi::lua_State, nargs: c_int, nresults: c_int, errfunc: c_int) -> c_int {
    unsafe { mlua::ffi::lua_pcall(l, nargs, nresults, errfunc) }
}

pub extern "C" fn moonlift_lua_settop(l: *mut mlua::ffi::lua_State, idx: c_int) -> c_int {
    unsafe { mlua::ffi::lua_settop(l, idx) };
    1
}

pub extern "C" fn moonlift_lua_createtable(l: *mut mlua::ffi::lua_State, narr: c_int, nrec: c_int) -> c_int {
    unsafe { mlua::ffi::lua_createtable(l, narr, nrec) };
    1
}

pub extern "C" fn moonlift_lua_pushlstring(l: *mut mlua::ffi::lua_State, s: *const c_char, len: usize) -> c_int {
    unsafe { mlua::ffi::lua_pushlstring_(l, s, len) };
    1
}

pub extern "C" fn moonlift_lua_pushnumber(l: *mut mlua::ffi::lua_State, n: f64) -> c_int {
    unsafe { mlua::ffi::lua_pushnumber(l, n) };
    1
}

pub extern "C" fn moonlift_lua_pushboolean(l: *mut mlua::ffi::lua_State, b: c_int) -> c_int {
    unsafe { mlua::ffi::lua_pushboolean(l, b) };
    1
}

pub extern "C" fn moonlift_lua_pushnil(l: *mut mlua::ffi::lua_State) -> c_int {
    unsafe { mlua::ffi::lua_pushnil(l) };
    1
}

pub extern "C" fn moonlift_lua_settable(l: *mut mlua::ffi::lua_State, idx: c_int) -> c_int {
    unsafe { mlua::ffi::lua_settable(l, idx) };
    1
}

pub extern "C" fn moonlift_lua_rawseti(l: *mut mlua::ffi::lua_State, idx: c_int, n: c_int) -> c_int {
    unsafe { mlua::ffi::lua_rawseti_(l, idx, n) };
    1
}

pub extern "C" fn moonlift_lua_setfield(l: *mut mlua::ffi::lua_State, idx: c_int, k: *const c_char) -> c_int {
    unsafe { mlua::ffi::lua_setfield(l, idx, k) };
    1
}

pub fn register_symbols(jit: &mut crate::Jit) {
    macro_rules! sym {
        ($name:literal, $func:path) => {
            jit.symbol($name, ($func as *const ()).cast::<u8>());
        };
    }

    sym!("lua_gettop", mlua::ffi::lua_gettop);
    sym!("lua_settop", moonlift_lua_settop);
    sym!("lua_createtable", moonlift_lua_createtable);
    sym!("lua_pushlstring", moonlift_lua_pushlstring);
    sym!("lua_pushnumber", moonlift_lua_pushnumber);
    sym!("lua_pushboolean", moonlift_lua_pushboolean);
    sym!("lua_pushnil", moonlift_lua_pushnil);
    sym!("lua_setfield", moonlift_lua_setfield);
    sym!("lua_settable", moonlift_lua_settable);
    sym!("lua_rawseti", moonlift_lua_rawseti);

    sym!("moonlift_lua_raw_gettop", moonlift_lua_raw_gettop);
    sym!("moonlift_lua_raw_settop", moonlift_lua_raw_settop);
    sym!("moonlift_lua_raw_type", moonlift_lua_raw_type);
    sym!("moonlift_lua_raw_tolstring", moonlift_lua_raw_tolstring);
    sym!("moonlift_lua_raw_toboolean", moonlift_lua_raw_toboolean);
    sym!("moonlift_lua_raw_tonumber", moonlift_lua_raw_tonumber);
    sym!("moonlift_lua_raw_pushvalue", moonlift_lua_raw_pushvalue);
    sym!("moonlift_lua_raw_pushnil", moonlift_lua_raw_pushnil);
    sym!("moonlift_lua_raw_pushboolean", moonlift_lua_raw_pushboolean);
    sym!("moonlift_lua_raw_pushnumber", moonlift_lua_raw_pushnumber);
    sym!("moonlift_lua_raw_pushlstring", moonlift_lua_raw_pushlstring);
    sym!("moonlift_lua_raw_rawgeti", moonlift_lua_raw_rawgeti);
    sym!("moonlift_lua_raw_rawseti", moonlift_lua_raw_rawseti);
    sym!("moonlift_lua_raw_lref", moonlift_lua_raw_lref);
    sym!("moonlift_lua_raw_lunref", moonlift_lua_raw_lunref);
    sym!("moonlift_lua_raw_pcall", moonlift_lua_raw_pcall);

    sym!("moonlift_scratch_raw", moonlift_scratch_raw);
    sym!("moonlift_alloc_i32", moonlift_alloc_i32);
    sym!("moonlift_free_i32", moonlift_free_i32);
    sym!("moonlift_lua_arg_lstring_ptr", moonlift_lua_arg_lstring_ptr);
    sym!("moonlift_lua_arg_lstring_len", moonlift_lua_arg_lstring_len);

    sym!("moonlift_jit_new", crate::ffi::moonlift_jit_new);
    sym!("moonlift_jit_free", crate::ffi::moonlift_jit_free);
    sym!("moonlift_jit_compile_binary", crate::ffi::moonlift_jit_compile_binary);
    sym!("moonlift_artifact_getpointer", crate::ffi::moonlift_artifact_getpointer);
    sym!("moonlift_artifact_free", crate::ffi::moonlift_artifact_free);

    sym!("memcmp", memcmp);

    sym!("__ml_memcpy", crate::rt::__ml_memcpy);
    sym!("__ml_memset", crate::rt::__ml_memset);
    sym!("__ml_memcmp", crate::rt::__ml_memcmp);
    sym!("__ml_alloc", crate::rt::__ml_alloc);
    sym!("__ml_free", crate::rt::__ml_free);
    sym!("__ml_realloc", crate::rt::__ml_realloc);
}
