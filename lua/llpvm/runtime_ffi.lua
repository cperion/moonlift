local ffi = require("ffi")

local M = {}

local Runtime = {}
Runtime.__index = Runtime

local Vm = {}
Vm.__index = Vm

local Status = {}
Status.__index = Status

local cdef_loaded = false

local function cdef()
    if cdef_loaded then return end
    ffi.cdef [[
typedef long ml_index;

typedef struct {
    int32_t code;
    int32_t detail;
    ml_index at;
    ml_index needed;
} llpvm_runtime_LlStatus;

typedef struct {
    void* allocator;
    ml_index initial_symbol_cap;
    ml_index initial_diagnostic_cap;
    ml_index initial_type_cap;
    ml_index initial_schema_cap;
    ml_index initial_abi_cap;
    ml_index initial_world_cap;
    ml_index initial_op_cap;
    ml_index initial_buffer_cap;
    ml_index initial_stream_cap;
    ml_index initial_program_cap;
    ml_index initial_args_cap;
    ml_index initial_machine_cap;
    ml_index initial_phase_cap;
    ml_index initial_recording_cap;
    ml_index initial_cache_cap;
    ml_index cache_bytes;
    uint32_t flags;
} llpvm_runtime_LlVmConfig;

typedef struct {
    ml_index abis;
    ml_index worlds;
    ml_index ops;
    ml_index buffers;
    ml_index streams;
    ml_index machines;
    ml_index phases;
    ml_index recordings;
    ml_index cache_entries;
    ml_index cache_bytes;
} llpvm_runtime_LlVmReport;

llpvm_runtime_LlStatus llpvm_open(void* config, void* out);
llpvm_runtime_LlStatus llpvm_close(uint32_t vm);
llpvm_runtime_LlStatus llpvm_load_program(uint32_t vm, void* bytes, ml_index len, void* out);
llpvm_runtime_LlStatus llpvm_apply_phase(uint32_t vm, uint32_t phase, uint32_t input, uint32_t args, void* out);
llpvm_runtime_LlStatus llpvm_drain(uint32_t vm, uint32_t stream, void* out);
llpvm_runtime_LlStatus llpvm_drain_count(uint32_t vm, uint32_t stream, void* out);
llpvm_runtime_LlStatus llpvm_report(uint32_t vm, void* out);
]]
    cdef_loaded = true
end

local status_names = {
    [0] = "ok",
    [1] = "invalid_config",
    [2] = "stale_handle",
    [3] = "missing_handle",
    [4] = "live_leases",
    [5] = "live_recordings",
    [6] = "wrong_world",
    [7] = "invalid_schema",
    [8] = "invalid_payload",
    [9] = "oom",
    [10] = "failed",
    [11] = "unsupported_image",
}

local function wrap_status(st)
    return setmetatable({
        code = tonumber(st.code),
        name = status_names[tonumber(st.code)] or "unknown",
        detail = tonumber(st.detail),
        at = tonumber(st.at),
        needed = tonumber(st.needed),
    }, Status)
end

local function require_handle(value, what)
    if type(value) == "table" and rawget(value, "__llpvm_node") ~= nil then
        error("LLPVM runtime " .. what .. " expects a native VM handle, not an authored ASDL proxy; encode/load a bytecode program first", 3)
    end
    local n = tonumber(value or 0)
    assert(n ~= nil, "LLPVM runtime " .. what .. " expects a numeric native handle")
    return n
end

function Status:ok()
    return self.code == 0
end

function Status:assert(context)
    if self.code ~= 0 then
        error((context or "llpvm runtime call") .. " failed: " .. self.name .. " (" .. tostring(self.code) .. ")", 2)
    end
    return self
end

local function config_from(opts)
    opts = opts or {}
    local cfg = ffi.new("llpvm_runtime_LlVmConfig[1]")
    cfg[0].allocator = opts.allocator
    cfg[0].initial_symbol_cap = opts.initial_symbol_cap or 0
    cfg[0].initial_diagnostic_cap = opts.initial_diagnostic_cap or 0
    cfg[0].initial_type_cap = opts.initial_type_cap or 0
    cfg[0].initial_schema_cap = opts.initial_schema_cap or 0
    cfg[0].initial_abi_cap = opts.initial_abi_cap or 0
    cfg[0].initial_world_cap = opts.initial_world_cap or 0
    cfg[0].initial_op_cap = opts.initial_op_cap or 0
    cfg[0].initial_buffer_cap = opts.initial_buffer_cap or 0
    cfg[0].initial_stream_cap = opts.initial_stream_cap or 0
    cfg[0].initial_program_cap = opts.initial_program_cap or 0
    cfg[0].initial_args_cap = opts.initial_args_cap or 0
    cfg[0].initial_machine_cap = opts.initial_machine_cap or 0
    cfg[0].initial_phase_cap = opts.initial_phase_cap or 0
    cfg[0].initial_recording_cap = opts.initial_recording_cap or 0
    cfg[0].initial_cache_cap = opts.initial_cache_cap or 0
    cfg[0].cache_bytes = opts.cache_bytes or 0
    cfg[0].flags = opts.flags or 0
    return cfg
end

function M.load(path, opts)
    opts = opts or {}
    cdef()
    local lib = ffi.load(path)
    return setmetatable({ lib = lib, path = path, opts = opts }, Runtime)
end

function M.build(opts)
    opts = opts or {}
    local Build = require("experiments.llpvm.llpvm_build_c")
    local base = opts.base or os.tmpname()
    local result = Build.build_shared {
        name = opts.name or "llpvm_runtime",
        c_path = opts.c_path or (base .. ".c"),
        h_path = opts.h_path or (base .. ".h"),
        so_path = opts.so_path or (base .. ".so"),
        cc = opts.cc,
        cflags = opts.cflags or "-O3 -std=c99 -fPIC -shared -Iexperiments/llpvm",
    }
    local runtime = M.load(result.so_path, opts)
    runtime.build = result
    runtime.cleanup = opts.cleanup ~= false
    return runtime
end

function Runtime:open(opts)
    local cfg = config_from(opts)
    local out = ffi.new("uint32_t[1]")
    local status = wrap_status(self.lib.llpvm_open(cfg, out))
    status:assert("llpvm_open")
    return setmetatable({
        runtime = self,
        ref = tonumber(out[0]),
        closed = false,
        _report = ffi.new("llpvm_runtime_LlVmReport[1]"),
        _u32 = ffi.new("uint32_t[1]"),
        _index = ffi.new("ml_index[1]"),
    }, Vm)
end

function Runtime:close()
    if self.cleanup and self.build then
        os.remove(self.build.c_path)
        os.remove(self.build.h_path)
        os.remove(self.build.so_path)
        self.cleanup = false
    end
end

function Vm:report()
    local out = self._report
    local status = wrap_status(self.runtime.lib.llpvm_report(self.ref, out))
    status:assert("llpvm_report")
    return {
        abis = tonumber(out[0].abis),
        worlds = tonumber(out[0].worlds),
        ops = tonumber(out[0].ops),
        buffers = tonumber(out[0].buffers),
        streams = tonumber(out[0].streams),
        machines = tonumber(out[0].machines),
        phases = tonumber(out[0].phases),
        recordings = tonumber(out[0].recordings),
        cache_entries = tonumber(out[0].cache_entries),
        cache_bytes = tonumber(out[0].cache_bytes),
    }
end

function Vm:report_raw()
    local out = self._report
    local status = wrap_status(self.runtime.lib.llpvm_report(self.ref, out))
    status:assert("llpvm_report")
    return out[0]
end

function Vm:apply_phase(phase, input, args)
    local out = self._u32
    out[0] = 0
    local st = wrap_status(self.runtime.lib.llpvm_apply_phase(
        self.ref,
        require_handle(phase, "phase"),
        require_handle(input, "input stream"),
        require_handle(args, "args"),
        out
    ))
    return st, tonumber(out[0])
end

function Vm:drain(stream)
    local out = self._u32
    out[0] = 0
    local st = wrap_status(self.runtime.lib.llpvm_drain(self.ref, require_handle(stream, "stream"), out))
    return st, tonumber(out[0])
end

function Vm:drain_count(stream)
    local out = self._index
    out[0] = 0
    local st = wrap_status(self.runtime.lib.llpvm_drain_count(self.ref, require_handle(stream, "stream"), out))
    return st, tonumber(out[0])
end

function Vm:load_program_buffer(bytes, len)
    assert(bytes ~= nil, "LLPVM runtime load_program_buffer expects byte pointer")
    len = tonumber(len)
    assert(len and len >= 0, "LLPVM runtime load_program_buffer expects byte length")
    local out = self._u32
    out[0] = 0
    local st = wrap_status(self.runtime.lib.llpvm_load_program(self.ref, bytes, len, out))
    return st, tonumber(out[0])
end

function Vm:close()
    if self.closed then return wrap_status(ffi.new("llpvm_runtime_LlStatus", { 0, 0, 0, 0 })) end
    local st = wrap_status(self.runtime.lib.llpvm_close(self.ref))
    st:assert("llpvm_close")
    self.closed = true
    return st
end

return M
