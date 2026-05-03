// MoonLift host binary — Terra-style hosted runtime.
//
// The binary owns the LuaJIT lua_State, hosts the MoonLift compiler, and exposes
// a direct Rust JIT bridge to Lua. Compiled MoonLift code can call Lua C API
// functions as regular native extern calls.
//
//   cargo run --bin moonlift -- path/to/file.mlua

use std::cell::RefCell;
use std::ffi::{c_int, c_void};
use std::rc::Rc;

use mlua::{Function, LightUserData, Lua, MultiValue, UserData, UserDataMethods, Value, Variadic};

type LuaCFunction = unsafe extern "C-unwind" fn(*mut mlua::ffi::lua_State) -> c_int;

struct HostedArtifact(Option<moonlift::Artifact>);

impl UserData for HostedArtifact {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("getpointer", |_lua, this, name: String| {
            let artifact = this
                .0
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("MoonLift artifact has been freed".to_string()))?;
            let ptr = artifact
                .getpointer_by_name(&name)
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
            Ok(ptr as usize)
        });

        methods.add_method("cfunction", |lua, this, name: String| {
            let artifact = this
                .0
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("MoonLift artifact has been freed".to_string()))?;
            let ptr = artifact
                .getpointer_by_name(&name)
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
            let func: LuaCFunction = unsafe { std::mem::transmute(ptr) };
            let lua_func: Function = unsafe { lua.create_c_function(func)? };
            Ok(lua_func)
        });

        methods.add_method("call", |lua, this, (name, args): (String, Variadic<Value>)| {
            let artifact = this
                .0
                .as_ref()
                .ok_or_else(|| mlua::Error::RuntimeError("MoonLift artifact has been freed".to_string()))?;
            let ptr = artifact
                .getpointer_by_name(&name)
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
            let func: LuaCFunction = unsafe { std::mem::transmute(ptr) };
            let nargs = args.len() as c_int;
            let values = MultiValue::from_vec(args.into_iter().collect());
            unsafe {
                lua.exec_raw::<MultiValue>(values, move |state| {
                    let base = mlua::ffi::lua_gettop(state) - nargs;
                    let nres = func(state);
                    if nres < 0 {
                        mlua::ffi::lua_settop(state, base);
                        return;
                    }
                    let top = mlua::ffi::lua_gettop(state);
                    let first = top - nres + 1;
                    for r in 0..nres {
                        mlua::ffi::lua_pushvalue(state, first + r);
                        mlua::ffi::lua_replace(state, base + 1 + r);
                    }
                    mlua::ffi::lua_settop(state, base + nres);
                })
            }
        });

        methods.add_method_mut("free", |_lua, this, ()| {
            this.0.take();
            Ok(())
        });
    }
}

fn install_host_api(lua: &Lua, jit: Rc<RefCell<moonlift::Jit>>) -> mlua::Result<()> {
    let symbol_jit = jit.clone();
    let symbol_fn = lua.create_function(move |_lua, (name, ptr): (String, usize)| {
        symbol_jit.borrow_mut().symbol(name, ptr as *const u8);
        Ok(())
    })?;
    lua.globals().set("_host_symbol", symbol_fn)?;

    let compile_jit = jit.clone();
    let compile_fn = lua.create_function(move |_lua, tape: String| {
        let artifact = compile_jit
            .borrow()
            .compile_tape(&tape)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        Ok(HostedArtifact(Some(artifact)))
    })?;
    lua.globals().set("_host_compile", compile_fn)?;
    Ok(())
}

fn init_lua(lua: &Lua, root: &str) -> Result<(), Box<dyn std::error::Error>> {
    lua.globals().set("MOONLIFT_ROOT", root)?;

    let mut lua_state = std::ptr::null_mut();
    unsafe {
        lua.exec_raw::<()>((), |state| {
            lua_state = state;
        })?;
    }
    lua.globals()
        .set("MOONLIFT_LUASTATE", LightUserData(lua_state.cast::<c_void>()))?;

    lua.load(
        r#"
        package.path = MOONLIFT_ROOT .. "/?.lua;" ..
                       MOONLIFT_ROOT .. "/?/init.lua;" ..
                       MOONLIFT_ROOT .. "/lua/?.lua;" ..
                       MOONLIFT_ROOT .. "/lua/?/init.lua;" ..
                       MOONLIFT_ROOT .. "/lib/?.lua;" ..
                       package.path

        local ffi = require("ffi")
        ffi.cdef[[
            void lua_createtable(void *L, int narr, int nrec);
            void lua_pushlstring(void *L, const char *s, size_t len);
            void lua_pushnumber(void *L, double n);
            void lua_pushboolean(void *L, int b);
            void lua_pushnil(void *L);
            void lua_setfield(void *L, int idx, const char *k);
            void lua_settable(void *L, int idx);
            void lua_rawseti(void *L, int idx, int i);
            int  lua_gettop(void *L);
            void lua_settop(void *L, int idx);
        ]]

        _M_HOSTED = true
        package.preload["moonlift.back_jit"] = function()
            return require("moonlift.hosted_jit")
        end
    "#,
    )
    .exec()?;

    Ok(())
}

fn run_mlua_file(lua: &Lua, path: &str) -> mlua::Result<()> {
    lua.globals().set("_MOONLIFT_RUN_PATH", path)?;
    lua.load(
        r#"
        local Host = require("moonlift.host_quote")
        local result = Host.dofile(_MOONLIFT_RUN_PATH)
        if result ~= nil then print(result) end
    "#,
    )
    .exec()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cwd = std::env::current_dir()?;
    let root = cwd.display().to_string();

    let lua = unsafe { Lua::unsafe_new() };
    init_lua(&lua, &root)?;

    let mut jit = moonlift::Jit::new();
    moonlift::lua_api::register_symbols(&mut jit);
    install_host_api(&lua, Rc::new(RefCell::new(jit)))?;

    lua.load(r#"require("moonlift.host_quote")"#).exec()?;

    if let Some(path) = std::env::args().nth(1) {
        run_mlua_file(&lua, &path)?;
    } else {
        println!("MoonLift host ready. usage: moonlift file.mlua");
    }

    Ok(())
}
