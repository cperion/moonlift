-- Native executable runner for v0 stencil fixtures.
--
-- This is deliberately tiny and test-oriented.  It turns a StencilFixture into
-- a callable x86-64 SysV function by wrapping the snippet:
--
--   push r14
--   mov  r14, rdi     ; first C arg is Value* base
--   <materialized fixture bytes>
--   pop  r14
--   ret
--
-- The production JIT will enter with pinned registers already established and
-- will not need this C-call wrapper.  The wrapper is only for native stencil
-- correctness/microbench tests from LuaJIT FFI.

local ffi = require("ffi")
local fixtures = require("experiments.lua_interpreter_vm.src.jit.stencil_fixtures")

local M = {}

M.supported = ffi.os == "Linux" and ffi.arch == "x64"

ffi.cdef [[
typedef struct JitValue {
    uint32_t tag;
    uint32_t aux;
    uint64_t bits;
} JitValue;

typedef struct NativeJitOutcome {
    uint32_t status;
    uint32_t exit_id;
    uint64_t pc;
} NativeJitOutcome;

typedef void (*moonlift_jit_stencil_fn)(JitValue *base);
typedef void (*moonlift_jit_block_fn)(JitValue *base, NativeJitOutcome *out);

void *mmap(void *addr, size_t length, int prot, int flags, int fd, int64_t offset);
int mprotect(void *addr, size_t len, int prot);
int munmap(void *addr, size_t length);
]]

local PROT_READ  = 0x1
local PROT_WRITE = 0x2
local PROT_EXEC  = 0x4
local MAP_PRIVATE = 0x02
local MAP_ANONYMOUS = 0x20
local PAGE = 4096

local function round_page(n)
    return math.floor((n + PAGE - 1) / PAGE) * PAGE
end

local function byte_string(bytes)
    local chars = {}
    for i, b in ipairs(bytes) do chars[i] = string.char(b) end
    return table.concat(chars)
end

local function write_le(bytes, offset, width, value)
    if value < 0 then value = value + 2 ^ (width * 8) end
    for i = 1, width do
        bytes[offset + i] = value % 256
        value = math.floor(value / 256)
    end
end

local function alloc_exec(bytes)
    assert(M.supported, "native stencil runner currently supports Linux x64 only")
    local size = round_page(#bytes)
    local p = ffi.C.mmap(nil, size, PROT_READ + PROT_WRITE, MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    if p == ffi.cast("void *", -1) then error("mmap failed") end
    ffi.copy(p, byte_string(bytes), #bytes)
    if ffi.C.mprotect(p, size, PROT_READ + PROT_EXEC) ~= 0 then
        ffi.C.munmap(p, size)
        error("mprotect RX failed")
    end
    return p, size
end

local function wrapped_bytes(body)
    local out = {}
    local function emit(...)
        for _, b in ipairs { ... } do out[#out + 1] = b end
    end
    emit(0x41, 0x56)       -- push r14
    emit(0x49, 0x89, 0xfe) -- mov r14, rdi
    for _, b in ipairs(body) do out[#out + 1] = b end
    emit(0x41, 0x5e)       -- pop r14
    emit(0xc3)             -- ret
    return out
end

local function wrapped_bytes_with_outcome(body)
    local out = {}
    local function emit(...)
        for _, b in ipairs { ... } do out[#out + 1] = b end
    end
    emit(0x41, 0x56)       -- push r14
    emit(0x41, 0x55)       -- push r13
    emit(0x49, 0x89, 0xfe) -- mov r14, rdi  ; Value* base
    emit(0x49, 0x89, 0xf5) -- mov r13, rsi  ; NativeJitOutcome* out
    for _, b in ipairs(body) do out[#out + 1] = b end
    emit(0x41, 0x5d)       -- pop r13
    emit(0x41, 0x5e)       -- pop r14
    emit(0xc3)             -- ret
    return out
end

function M.build_callable(fixture, stamps, fixups)
    local mat = fixtures.materialize(fixture, stamps or {}, fixups or {})
    local code = wrapped_bytes(mat.bytes)
    local p, size = alloc_exec(code)
    local unit = {
        kind = "NativeStencilUnit",
        fixture = fixture,
        materialized = mat,
        code_size = #code,
        mapping_size = size,
        ptr = p,
        fn = ffi.cast("moonlift_jit_stencil_fn", p),
    }
    return unit
end

local function dummy_fixups_for(fixture)
    local out = {}
    for _, r in ipairs(fixture.relocs or {}) do
        if r.required then out[r.name] = 0 end
    end
    return out
end

local function assemble_body(nodes)
    assert(type(nodes) == "table" and #nodes > 0, "block nodes required")
    local body, placed = {}, {}
    local offset = 0
    for i, node in ipairs(nodes) do
        local fixture = node.fixture or fixtures.first_fixture(assert(node.spec, "node.spec required"))
        assert(fixture, "missing fixture for " .. tostring(node.spec))
        local mat = fixtures.materialize(fixture, node.stamps or {}, dummy_fixups_for(fixture))
        placed[i] = { node = node, fixture = fixture, offset = offset, size = #mat.bytes }
        for _, b in ipairs(mat.bytes) do body[#body + 1] = b end
        offset = offset + #mat.bytes
    end

    local labels = { side_exit = #body, end_block = #body }
    for i, p in ipairs(placed) do
        labels["node" .. tostring(i)] = p.offset
        if p.node.label then labels[p.node.label] = p.offset end
    end

    for _, p in ipairs(placed) do
        local node_fixups = p.node.fixups or {}
        for _, r in ipairs(p.fixture.relocs or {}) do
            local target = node_fixups[r.name]
            if target == nil and r.name:match("^side_exit") then target = "side_exit" end
            if target ~= nil then
                local value
                if type(target) == "string" then
                    local target_off = assert(labels[target], "unknown block label " .. target)
                    value = target_off - (p.offset + r.offset + r.width)
                else
                    value = target
                end
                write_le(body, p.offset + r.offset, r.width, value)
            elseif r.required then
                error("missing block fixup " .. r.name .. " for " .. p.fixture.spec_name)
            end
        end
    end
    return body, placed, labels
end

-- Build one callable native block from multiple stencil nodes.  This is the
-- first executable-unit shape: one C-call wrapper, many copied stencil bodies.
function M.build_block(nodes)
    local body, placed = assemble_body(nodes)
    local code = wrapped_bytes(body)
    local ptr, size = alloc_exec(code)
    return {
        kind = "NativeStencilBlock",
        nodes = nodes,
        placed = placed,
        body_size = #body,
        code_size = #code,
        mapping_size = size,
        ptr = ptr,
        fn = ffi.cast("moonlift_jit_stencil_fn", ptr),
    }
end

function M.build_block_with_outcome(nodes)
    local body, placed = assemble_body(nodes)
    local code = wrapped_bytes_with_outcome(body)
    local ptr, size = alloc_exec(code)
    return {
        kind = "NativeStencilOutcomeBlock",
        nodes = nodes,
        placed = placed,
        body_size = #body,
        code_size = #code,
        mapping_size = size,
        ptr = ptr,
        fn = ffi.cast("moonlift_jit_block_fn", ptr),
    }
end

function M.free(unit)
    if unit and unit.ptr ~= nil then
        ffi.C.munmap(unit.ptr, unit.mapping_size)
        unit.ptr = nil
        unit.fn = nil
    end
end

function M.new_values(n)
    return ffi.new("JitValue[?]", n)
end

function M.new_outcome()
    return ffi.new("NativeJitOutcome[1]")
end

M.OutcomeStatus = {
    OK = 0,
    SIDE_EXIT = 1,
    RETURN = 2,
    ERROR = 3,
    CALL_BOUNDARY = 4,
}

return M
