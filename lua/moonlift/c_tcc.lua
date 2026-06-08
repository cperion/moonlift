-- Optional libtcc LuaJIT FFI runner for Moonlift-emitted C.
--
-- This module is intentionally self-contained and optional: requiring it must not
-- fail just because libtcc is not installed.  Call available() to probe, and use
-- compile() to build C in memory when libtcc is present.

local ok_ffi, ffi = pcall(require, "ffi")

local M = {}

local TCC_OUTPUT_MEMORY = 1
local last_session = nil

local function diag(code, message, extra)
    local d = extra or {}
    d.ok = false
    d.code = code
    d.message = message
    return d
end

local function listify(v)
    if v == nil then return {} end
    if type(v) == "table" then return v end
    return { v }
end

local function join_errors(errors)
    if errors and #errors > 0 then return table.concat(errors, "\n") end
    return nil
end

local function first_nonempty(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and tostring(v) ~= "" then return v end
    end
    return nil
end

local cdef_done = false
local function ensure_cdef()
    if cdef_done then return true end
    if not ok_ffi then return false end
    local ok, err = pcall(ffi.cdef, [[
typedef struct TCCState TCCState;
TCCState *tcc_new(void);
void tcc_delete(TCCState *s);
void tcc_set_lib_path(TCCState *s, const char *path);
void tcc_set_error_func(TCCState *s, void *error_opaque, void (*error_func)(void *opaque, const char *msg));
void tcc_set_options(TCCState *s, const char *str);
int tcc_add_include_path(TCCState *s, const char *pathname);
int tcc_add_sysinclude_path(TCCState *s, const char *pathname);
void tcc_define_symbol(TCCState *s, const char *sym, const char *value);
void tcc_undefine_symbol(TCCState *s, const char *sym);
int tcc_add_file(TCCState *s, const char *filename);
int tcc_compile_string(TCCState *s, const char *buf);
int tcc_set_output_type(TCCState *s, int output_type);
int tcc_add_library_path(TCCState *s, const char *pathname);
int tcc_add_library(TCCState *s, const char *libraryname);
int tcc_add_symbol(TCCState *s, const char *name, const void *val);
int tcc_relocate(TCCState *s);
void *tcc_get_symbol(TCCState *s, const char *name);
]])
    -- Duplicate cdefs are harmless in practice, but LuaJIT reports them as
    -- errors.  Treat either outcome as initialized because the declarations are
    -- process-global and may have been installed by another module/test.
    cdef_done = true
    return ok or tostring(err):match("redefinition") ~= nil
end

local function candidate_names(opts)
    opts = opts or {}
    local names = {}
    local explicit = first_nonempty(opts.lib, opts.lib_path, opts.library, os.getenv("MOONLIFT_LIBTCC"))
    if explicit then names[#names + 1] = explicit end
    if ok_ffi then
        if ffi.os == "Windows" then
            names[#names + 1] = "tcc.dll"
            names[#names + 1] = "libtcc.dll"
        elseif ffi.os == "OSX" then
            names[#names + 1] = "libtcc.dylib"
            names[#names + 1] = "tcc"
        else
            names[#names + 1] = "tcc"
            names[#names + 1] = "libtcc.so.1"
            names[#names + 1] = "libtcc.so"
            names[#names + 1] = "/usr/local/lib/libtcc.so"
            names[#names + 1] = "/usr/lib/libtcc.so"
        end
    end
    return names
end

local cached_key, cached_lib, cached_err
local function load_libtcc(opts)
    opts = opts or {}
    if not ok_ffi then
        return nil, diag("ffi_unavailable", "LuaJIT ffi is unavailable; libtcc in-memory runner is disabled")
    end
    if not ensure_cdef() then
        return nil, diag("ffi_cdef_failed", "could not register libtcc ffi declarations")
    end
    local names = candidate_names(opts)
    local key = table.concat(names, "\0")
    if cached_lib ~= nil and cached_key == key then return cached_lib end
    if cached_key == key and cached_err ~= nil then return nil, cached_err end

    local last_err
    for i = 1, #names do
        local ok, lib = pcall(ffi.load, names[i])
        if ok then
            cached_key, cached_lib, cached_err = key, lib, nil
            return lib
        end
        last_err = tostring(lib)
    end
    cached_key, cached_lib = key, nil
    cached_err = diag("libtcc_unavailable", "libtcc not available; install libtcc or set MOONLIFT_LIBTCC", {
        skip = true,
        candidates = names,
        detail = last_err,
    })
    return nil, cached_err
end

function M.available(opts)
    local lib, err = load_libtcc(opts)
    if lib then return true, nil end
    return false, err
end

local Session = {}
Session.__index = Session

function Session:free()
    if self._freed then return true end
    if self._state ~= nil then
        self._lib.tcc_delete(self._state)
        self._state = nil
    end
    if self._err_cb ~= nil then
        self._err_cb:free()
        self._err_cb = nil
    end
    self._freed = true
    if last_session == self then last_session = nil end
    return true
end

function Session:symbol(name, ctype)
    assert(type(name) == "string" and name ~= "", "libtcc symbol name must be a non-empty string")
    if self._freed or self._state == nil then
        return nil, diag("session_freed", "libtcc session has been freed")
    end
    local ptr = self._lib.tcc_get_symbol(self._state, name)
    if ptr == nil then
        return nil, diag("symbol_not_found", "libtcc symbol not found: " .. name)
    end
    if ctype ~= nil then return ffi.cast(ctype, ptr) end
    return ptr
end

local function check_rc(rc, stage, errors)
    if tonumber(rc) < 0 then
        return nil, diag("libtcc_error", "libtcc " .. stage .. " failed" .. (join_errors(errors) and (": " .. join_errors(errors)) or ""), {
            stage = stage,
            errors = errors,
        })
    end
    return true
end

local function apply_defines(lib, state, defines)
    if defines == nil then return end
    for k, v in pairs(defines) do
        if type(k) == "number" then
            lib.tcc_define_symbol(state, tostring(v), "1")
        elseif v == false or v == nil then
            lib.tcc_undefine_symbol(state, tostring(k))
        else
            lib.tcc_define_symbol(state, tostring(k), tostring(v))
        end
    end
end

local function apply_host_symbols(lib, state, symbols)
    if symbols == nil then return true end
    for name, value in pairs(symbols) do
        local ok, err = check_rc(lib.tcc_add_symbol(state, tostring(name), value), "add_symbol(" .. tostring(name) .. ")")
        if not ok then return nil, err end
    end
    return true
end

local function add_each(lib, state, values, fn_name, stage)
    for _, value in ipairs(listify(values)) do
        local ok, err = check_rc(lib[fn_name](state, tostring(value)), stage .. "(" .. tostring(value) .. ")")
        if not ok then return nil, err end
    end
    return true
end

function M.compile(c_source, opts)
    opts = opts or {}
    assert(type(c_source) == "string", "moonlift.c_tcc.compile expects C source string")
    local lib, avail_err = load_libtcc(opts)
    if not lib then return nil, avail_err end

    local state = lib.tcc_new()
    if state == nil then
        return nil, diag("libtcc_error", "libtcc tcc_new failed")
    end

    local errors = {}
    local err_cb = ffi.cast("void (*)(void *, const char *)", function(_, msg)
        errors[#errors + 1] = msg ~= nil and ffi.string(msg) or "<nil libtcc error>"
    end)
    lib.tcc_set_error_func(state, nil, err_cb)

    local session = setmetatable({ _lib = lib, _state = state, _err_cb = err_cb, _errors = errors, _freed = false }, Session)
    local function fail(err)
        session:free()
        return nil, err
    end

    if opts.lib_path then lib.tcc_set_lib_path(state, tostring(opts.lib_path)) end
    if opts.options or opts.tcc_options then lib.tcc_set_options(state, tostring(opts.options or opts.tcc_options)) end

    local ok, err
    ok, err = add_each(lib, state, opts.include_paths or opts.include_path, "tcc_add_include_path", "add_include_path")
    if not ok then return fail(err) end
    ok, err = add_each(lib, state, opts.sysinclude_paths or opts.sysinclude_path, "tcc_add_sysinclude_path", "add_sysinclude_path")
    if not ok then return fail(err) end
    ok, err = add_each(lib, state, opts.library_paths or opts.library_path, "tcc_add_library_path", "add_library_path")
    if not ok then return fail(err) end
    apply_defines(lib, state, opts.defines)
    for _, name in ipairs(listify(opts.undefines)) do lib.tcc_undefine_symbol(state, tostring(name)) end
    ok, err = apply_host_symbols(lib, state, opts.host_symbols or opts.add_symbols)
    if not ok then return fail(err) end

    ok, err = check_rc(lib.tcc_set_output_type(state, opts.output_type or TCC_OUTPUT_MEMORY), "set_output_type", errors)
    if not ok then return fail(err) end
    ok, err = check_rc(lib.tcc_compile_string(state, c_source), "compile_string", errors)
    if not ok then return fail(err) end
    ok, err = add_each(lib, state, opts.libraries or opts.library_names, "tcc_add_library", "add_library")
    if not ok then return fail(err) end

    if opts.relocate ~= false then
        ok, err = check_rc(lib.tcc_relocate(state), "relocate", errors)
        if not ok then return fail(err) end
        session._relocated = true
    end

    last_session = session
    return session
end

function M.symbol(name, ctype)
    if last_session == nil then
        return nil, diag("no_session", "no active libtcc session; call moonlift.c_tcc.compile first")
    end
    return last_session:symbol(name, ctype)
end

function M.free()
    if last_session == nil then return true end
    return last_session:free()
end

M.Session = Session
M.TCC_OUTPUT_MEMORY = TCC_OUTPUT_MEMORY
M.TCC_RELOCATE_AUTO = ok_ffi and ffi.cast("void *", 1) or nil

return M
