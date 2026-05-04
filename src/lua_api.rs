use std::alloc::{Layout, alloc_zeroed, dealloc};
use std::ffi::{c_char, c_int};

thread_local! {
    static SCRATCH_I32: std::cell::RefCell<Vec<Vec<i32>>> = std::cell::RefCell::new(vec![Vec::new(); 8]);
    static SCRATCH_U8: std::cell::RefCell<Vec<Vec<u8>>> = std::cell::RefCell::new(vec![Vec::new(); 8]);
}

pub extern "C" fn moonlift_scratch_i32(slot: i32, count: i32) -> *mut i32 {
    if !(0..8).contains(&slot) || count <= 0 {
        return std::ptr::null_mut();
    }
    SCRATCH_I32.with(|scratch| {
        let mut scratch = scratch.borrow_mut();
        let buf = &mut scratch[slot as usize];
        if buf.len() < count as usize {
            buf.resize(count as usize, 0);
        } else {
            buf[..count as usize].fill(0);
        }
        buf.as_mut_ptr()
    })
}

pub extern "C" fn moonlift_scratch_u8(slot: i32, count: i32) -> *mut u8 {
    if !(0..8).contains(&slot) || count <= 0 {
        return std::ptr::null_mut();
    }
    SCRATCH_U8.with(|scratch| {
        let mut scratch = scratch.borrow_mut();
        let buf = &mut scratch[slot as usize];
        if buf.len() < count as usize {
            buf.resize(count as usize, 0);
        } else {
            buf[..count as usize].fill(0);
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

    sym!("moonlift_scratch_i32", moonlift_scratch_i32);
    sym!("moonlift_scratch_u8", moonlift_scratch_u8);
    sym!("moonlift_alloc_i32", moonlift_alloc_i32);
    sym!("moonlift_free_i32", moonlift_free_i32);
    sym!("moonlift_lua_arg_lstring_ptr", moonlift_lua_arg_lstring_ptr);
    sym!("moonlift_lua_arg_lstring_len", moonlift_lua_arg_lstring_len);
}
