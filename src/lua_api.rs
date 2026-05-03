use std::alloc::{Layout, alloc_zeroed, dealloc};
use std::ffi::{c_char, c_int};
use std::slice;

thread_local! {
    static SCRATCH_I32: std::cell::RefCell<Vec<Vec<i32>>> = std::cell::RefCell::new(vec![Vec::new(); 8]);
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

fn push_lstring(l: *mut mlua::ffi::lua_State, bytes: &[u8]) {
    unsafe { mlua::ffi::lua_pushlstring_(l, bytes.as_ptr().cast::<c_char>(), bytes.len()) }
}

pub extern "C" fn moonlift_lua_push_json_number(
    l: *mut mlua::ffi::lua_State,
    p: *const u8,
    len: isize,
) -> c_int {
    if p.is_null() || len < 0 {
        return 0;
    }
    let bytes = unsafe { slice::from_raw_parts(p, len as usize) };
    let Ok(text) = std::str::from_utf8(bytes) else { return 0 };
    let Ok(n) = text.parse::<f64>() else { return 0 };
    unsafe { mlua::ffi::lua_pushnumber(l, n) };
    1
}

fn hex_val(b: u8) -> Option<u16> {
    match b {
        b'0'..=b'9' => Some((b - b'0') as u16),
        b'a'..=b'f' => Some((b - b'a' + 10) as u16),
        b'A'..=b'F' => Some((b - b'A' + 10) as u16),
        _ => None,
    }
}

fn read_u16_escape(bytes: &[u8], i: usize) -> Option<u16> {
    if i + 4 > bytes.len() {
        return None;
    }
    let mut out = 0u16;
    for j in 0..4 {
        out = (out << 4) | hex_val(bytes[i + j])?;
    }
    Some(out)
}

fn push_utf8(out: &mut Vec<u8>, cp: u32) -> bool {
    let Some(ch) = char::from_u32(cp) else { return false };
    let mut buf = [0u8; 4];
    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
    true
}

fn decode_json_string(bytes: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        if b != b'\\' {
            if b < 0x20 {
                return None;
            }
            out.push(b);
            i += 1;
            continue;
        }
        i += 1;
        if i >= bytes.len() {
            return None;
        }
        match bytes[i] {
            b'"' => out.push(b'"'),
            b'\\' => out.push(b'\\'),
            b'/' => out.push(b'/'),
            b'b' => out.push(8),
            b'f' => out.push(12),
            b'n' => out.push(b'\n'),
            b'r' => out.push(b'\r'),
            b't' => out.push(b'\t'),
            b'u' => {
                i += 1;
                let u = read_u16_escape(bytes, i)?;
                i += 3;
                let cp = if (0xD800..=0xDBFF).contains(&u) {
                    if i + 6 >= bytes.len() || bytes[i + 1] != b'\\' || bytes[i + 2] != b'u' {
                        return None;
                    }
                    let lo = read_u16_escape(bytes, i + 3)?;
                    if !(0xDC00..=0xDFFF).contains(&lo) {
                        return None;
                    }
                    i += 6;
                    0x10000 + ((((u - 0xD800) as u32) << 10) | ((lo - 0xDC00) as u32))
                } else if (0xDC00..=0xDFFF).contains(&u) {
                    return None;
                } else {
                    u as u32
                };
                if !push_utf8(&mut out, cp) {
                    return None;
                }
            }
            _ => return None,
        }
        i += 1;
    }
    Some(out)
}

pub extern "C" fn moonlift_lua_push_json_string(
    l: *mut mlua::ffi::lua_State,
    p: *const u8,
    len: isize,
) -> c_int {
    if p.is_null() || len < 0 {
        return 0;
    }
    let bytes = unsafe { slice::from_raw_parts(p, len as usize) };
    if !bytes.contains(&b'\\') {
        push_lstring(l, bytes);
        return 1;
    }
    let Some(decoded) = decode_json_string(bytes) else { return 0 };
    push_lstring(l, &decoded);
    1
}

pub extern "C" fn moonlift_lua_push_json_number_at(
    l: *mut mlua::ffi::lua_State,
    p: *const u8,
    offset: i32,
    len: i32,
) -> c_int {
    if p.is_null() || offset < 0 || len < 0 {
        return 0;
    }
    unsafe { moonlift_lua_push_json_number(l, p.add(offset as usize), len as isize) }
}

pub extern "C" fn moonlift_lua_push_json_string_at(
    l: *mut mlua::ffi::lua_State,
    p: *const u8,
    offset: i32,
    len: i32,
) -> c_int {
    if p.is_null() || offset < 0 || len < 0 {
        return 0;
    }
    unsafe { moonlift_lua_push_json_string(l, p.add(offset as usize), len as isize) }
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
    sym!("moonlift_alloc_i32", moonlift_alloc_i32);
    sym!("moonlift_free_i32", moonlift_free_i32);
    sym!("moonlift_lua_arg_lstring_ptr", moonlift_lua_arg_lstring_ptr);
    sym!("moonlift_lua_arg_lstring_len", moonlift_lua_arg_lstring_len);
    sym!("moonlift_lua_push_json_number", moonlift_lua_push_json_number);
    sym!("moonlift_lua_push_json_string", moonlift_lua_push_json_string);
    sym!("moonlift_lua_push_json_number_at", moonlift_lua_push_json_number_at);
    sym!("moonlift_lua_push_json_string_at", moonlift_lua_push_json_string_at);
}
