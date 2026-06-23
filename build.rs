use std::collections::HashSet;
use std::fmt::Write;
use std::path::{Path, PathBuf};

fn module_name(path: &Path, base: &Path) -> String {
    let rel = path.strip_prefix(base).unwrap().with_extension("");
    let mut s = rel.to_string_lossy().replace('/', ".");
    if s.ends_with(".init") {
        s.truncate(s.len() - 5);
    }
    if s.is_empty() {
        s = base.file_name().unwrap().to_string_lossy().to_string();
    }
    s
}

fn collect(dir: &Path, base: &Path, ext: &str, out: &mut Vec<(String, String)>) {
    for entry in std::fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.is_dir() {
            collect(&path, base, ext, out);
        } else if path.extension().is_some_and(|e| e == ext) {
            out.push((module_name(&path, base), path.to_string_lossy().to_string()));
        }
    }
}

fn validate_schema_sources(lua_modules: &[(String, String)], asdl_modules: &[(String, String)]) {
    for (name, path) in lua_modules {
        if path.starts_with("lua/moonlift/schema/") && path != "lua/moonlift/schema/init.lua" {
            panic!(
                "stale Lua schema builder module under lua/moonlift/schema/: {path} ({name}); schemas in this directory must be .asdl text"
            );
        }
    }

    let mut schema_preloads = HashSet::new();
    for (name, path) in asdl_modules {
        if !path.starts_with("lua/moonlift/schema/") { continue; }
        let stem = Path::new(path)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or_else(|| panic!("invalid schema ASDL path: {path}"));
        let expected_name = format!("moonlift.schema.{stem}");
        if name != &expected_name {
            panic!("schema ASDL {path} collected as {name}, expected {expected_name}");
        }
        let preload_name = format!("{name}_asdl");
        let expected_preload = format!("moonlift.schema.{stem}_asdl");
        if preload_name != expected_preload {
            panic!("schema ASDL {path} would generate preload {preload_name}, expected {expected_preload}");
        }
        if !schema_preloads.insert(preload_name) {
            panic!("duplicate schema ASDL preload generated for {path}");
        }
    }
}

fn build_luajit() -> PathBuf {
    let src = Path::new(".vendor/LuaJIT/src");
    let abs = std::fs::canonicalize(src).unwrap();

    // Force clean rebuild to ensure PIC is applied
    std::process::Command::new("make")
        .args(["-C", &abs.to_string_lossy(), "clean"])
        .status().ok();
    let status = std::process::Command::new("make")
        .args([
            "-C", &abs.to_string_lossy(),
            "-j", &std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).to_string(),
        ])
        .env("CFLAGS", "-fPIC")
        .status()
        .unwrap();
    assert!(status.success(), "LuaJIT build failed");

    // Create a symlink so mlua-sys can find it as libluajit-5.1.a
    let symlink = abs.join("libluajit-5.1.a");
    if !symlink.exists() {
        std::os::unix::fs::symlink(abs.join("libluajit.a"), &symlink).ok();
    }

    println!("cargo:rustc-link-search={}", abs.display());
    println!("cargo:rustc-link-lib=static=luajit");
    abs
}

fn embed_file_name(name: &str, suffix: &str) -> String {
    let mut out = String::new();
    for ch in name.chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    out.push_str(suffix);
    out
}

fn bytecompile_lua(luajit_src: &Path, input: &Path, output: &Path) {
    let lua_path = format!(
        "{}/?.lua;{}/jit/?.lua;;",
        luajit_src.display(),
        luajit_src.display()
    );
    let status = std::process::Command::new(luajit_src.join("luajit"))
        .args(["-bg", &input.to_string_lossy(), &output.to_string_lossy()])
        .env("LUA_PATH", lua_path)
        .status()
        .unwrap_or_else(|err| panic!("failed to run LuaJIT bytecode compiler for {}: {err}", input.display()));
    assert!(
        status.success(),
        "LuaJIT bytecode compiler failed for {}",
        input.display()
    );
}

fn main() {
    println!("cargo::rerun-if-changed=lua/");
    println!("cargo::rerun-if-changed=.vendor/LuaJIT/src");
    println!("cargo::rerun-if-env-changed=CFLAGS");

    let luajit_src = build_luajit();
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let bytecode_dir = out_dir.join("embedded_lua_bytecode");
    std::fs::create_dir_all(&bytecode_dir).unwrap();

    let lua_dir = Path::new("lua");
    let mut lua_modules = Vec::new();
    collect(lua_dir, lua_dir, "lua", &mut lua_modules);
    lua_modules.sort_by(|a, b| a.0.cmp(&b.0));

    let mut asdl_modules = Vec::new();
    collect(lua_dir, lua_dir, "asdl", &mut asdl_modules);
    asdl_modules.sort_by(|a, b| a.0.cmp(&b.0));
    validate_schema_sources(&lua_modules, &asdl_modules);

    let mut modules: Vec<(String, String, bool)> = Vec::new();
    for (name, path) in lua_modules {
        modules.push((name, path, false));
    }
    for (name, path) in asdl_modules {
        modules.push((format!("{}_asdl", name), path, true));
    }
    modules.sort_by(|a, b| a.0.cmp(&b.0));

    let mut code = String::new();
    code.push_str("// Auto-generated by build.rs — do not edit.\n");
    code.push_str("pub fn embedded_modules() -> Vec<(&'static str, &'static [u8])> {\n");
    code.push_str("    vec![\n");
    for (name, path, as_text) in &modules {
        let path_ref = Path::new(path);
        if *as_text {
            let lua_source = format!("return {:?}", std::fs::read_to_string(path).unwrap());
            let temp_source = bytecode_dir.join(embed_file_name(name, ".asdl_wrapper.lua"));
            let bytecode = bytecode_dir.join(embed_file_name(name, ".ljbc"));
            std::fs::write(&temp_source, lua_source).unwrap();
            bytecompile_lua(&luajit_src, &temp_source, &bytecode);
            write!(
                code,
                "        ({:?}, include_bytes!(concat!(env!(\"OUT_DIR\"), {:?})).as_slice()),\n",
                name,
                format!("/embedded_lua_bytecode/{}", bytecode.file_name().unwrap().to_string_lossy())
            ).unwrap();
        } else if path_ref.extension().is_some_and(|e| e == "lua") {
            let bytecode = bytecode_dir.join(embed_file_name(name, ".ljbc"));
            bytecompile_lua(&luajit_src, path_ref, &bytecode);
            write!(
                code,
                "        ({:?}, include_bytes!(concat!(env!(\"OUT_DIR\"), {:?})).as_slice()),\n",
                name,
                format!("/embedded_lua_bytecode/{}", bytecode.file_name().unwrap().to_string_lossy())
            ).unwrap();
        } else {
            let rel = format!("../{}", path);
            write!(code, "        ({:?}, include_bytes!({:?}).as_slice()),\n", name, rel).unwrap();
        }
    }
    code.push_str("    ]\n");
    code.push_str("}\n");

    std::fs::write("src/embedded_hosted_lua.rs", &code).unwrap();
}
