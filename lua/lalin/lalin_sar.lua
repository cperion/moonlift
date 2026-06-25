-- lalin_sar.lua
--
-- Scope / Arena / Resource for Lalin + LuaJIT.
--
-- This file deliberately does NOT recreate Lalin primitives:
-- no mem.i32, no mem.struct, no mem.ptr, no mem.view, no libc wrapper layer.
--
-- It only provides LuaJIT-side mechanisms:
--   scope     dynamic rooting + defer stack
--   arena     bump allocation over rooted LuaJIT cdata
--   resource  explicit close/defer discipline
--   borrow    callable ptr/len lending objects
--
-- API grammar:
--   sar.scope(function(S) ... end)
--   local A = sar.arena(S, "1mb")
--   local b = A:bytes("64kb")
--   local xs = A:array("int32_t", 1024)
--
--   b(fn, ...)
--     calls fn(b.ptr, b.len, lowered(...))
--
--   xs(fn, other)
--     calls fn(xs.ptr, xs.len, other.ptr, other.len)
--
--   r(fn, ...)
--     calls fn(r.handle, lowered(...))
--
-- Raw escape hatch stays visible:
--   lalin_func(b.ptr, b.len)

local ffi = require("ffi")
local unpack = table.unpack or unpack

local M = { _VERSION = "lalin.sar 0.1.0" }

local Scope = {}
Scope.__index = Scope

local Arena = {}
Arena.__index = Arena

local Borrow = {}
Borrow.__index = Borrow

local Resource = {}
Resource.__index = Resource

local BorrowMT
local ResourceMT

M.Scope = Scope
M.Arena = Arena
M.Borrow = Borrow
M.Resource = Resource

local DEFAULT_ALIGN = 8

local function fail(msg, level)
    error(msg, (level or 1) + 1)
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function check_integer(n, name)
    if type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0 then
        fail("sar: " .. name .. " must be a non-negative integer", 3)
    end
end

local function parse_size(x)
    if type(x) == "number" then
        check_integer(x, "size")
        return x
    end

    if type(x) ~= "string" then
        fail("sar: size must be a number or string", 3)
    end

    local n, unit = x:match("^%s*(%d+)%s*([kKmMgG]?[bB]?)%s*$")
    if not n then
        fail("sar: invalid size string: " .. tostring(x), 3)
    end

    n = tonumber(n)
    unit = unit:lower()

    if unit == "" or unit == "b" then
        return n
    elseif unit == "k" or unit == "kb" then
        return n * 1024
    elseif unit == "m" or unit == "mb" then
        return n * 1024 * 1024
    elseif unit == "g" or unit == "gb" then
        return n * 1024 * 1024 * 1024
    end

    fail("sar: invalid size unit: " .. tostring(unit), 3)
end

M.size = parse_size

local function align_up(x, align)
    align = align or DEFAULT_ALIGN
    check_integer(align, "alignment")
    if align <= 0 then
        fail("sar: alignment must be positive", 3)
    end

    local rem = x % align
    if rem == 0 then
        return x
    end
    return x + (align - rem)
end

local function is_scope(x)
    return getmetatable(x) == Scope
end

local function is_arena(x)
    return getmetatable(x) == Arena
end

local function check_scope(S)
    if not is_scope(S) or S.closed then
        fail("sar: use after scope close", 3)
    end
end

local function check_arena(A)
    if not is_arena(A) or A.closed then
        fail("sar: use after arena close", 3)
    end
end

local function ffi_typeof(ctype)
    if type(ctype) == "string" then
        return ffi.typeof(ctype)
    end
    return ctype
end

local function ptr_typeof(ctype)
    return ffi.typeof("$ *", ffi_typeof(ctype))
end

local function raw_ptr(x)
    if type(x) == "table" then
        return x.ptr or x.handle or x
    end
    return x
end

local function raw_len(x)
    if type(x) == "table" then
        return x.bytes or x.len
    end
    return nil
end

function M.lower_into(out, x)
    local mt = getmetatable(x)
    if mt ~= nil and mt.__sar_lower ~= nil then
        mt.__sar_lower(x, out)
    else
        out[#out + 1] = x
    end
end

function M.lower(...)
    local out = {}
    local args = pack(...)
    for i = 1, args.n do
        M.lower_into(out, args[i])
    end
    return unpack(out, 1, #out)
end

function M.owner(x)
    local mt = getmetatable(x)
    if mt ~= nil and mt.__sar_owner ~= nil then
        return mt.__sar_owner(x)
    end
    return x
end

local function call_lent(self, fn, ...)
    -- Lalin/JIT functions may be LuaJIT FFI cdata callables, so avoid
    -- rejecting non-Lua-function values here. Let LuaJIT perform the call check.
    if fn == nil then
        fail("sar: borrow target is nil", 2)
    end

    local out = {}
    M.lower_into(out, self)

    local args = pack(...)
    for i = 1, args.n do
        M.lower_into(out, args[i])
    end

    return fn(unpack(out, 1, #out))
end

BorrowMT = {
    __index = Borrow,
    __call = call_lent,
    __sar_lower = function(self, out)
        self:check()
        out[#out + 1] = self.ptr
        out[#out + 1] = self.len
    end,
    __sar_owner = function(self)
        return self.owner
    end,
}

ResourceMT = {
    __index = Resource,
    __call = call_lent,
    __sar_lower = function(self, out)
        self:check()
        out[#out + 1] = self.handle
    end,
    __sar_owner = function(self)
        return self
    end,
}

-- Scope ---------------------------------------------------------------------

function M.scope(fn, ...)
    if type(fn) ~= "function" then
        fail("sar: scope callback must be a function", 2)
    end

    local args = pack(...)
    local S = setmetatable({
        roots = {},
        defers = {},
        closed = false,
    }, Scope)

    local result = pack(xpcall(function()
        return fn(S, unpack(args, 1, args.n))
    end, debug.traceback))

    local close_ok, close_err = pcall(function()
        S:close()
    end)

    if not result[1] then
        if not close_ok then
            error(tostring(result[2]) .. "\nsar scope cleanup error:\n" .. tostring(close_err), 0)
        end
        error(result[2], 0)
    end

    if not close_ok then
        error(close_err, 0)
    end

    return unpack(result, 2, result.n)
end

function Scope:pin(owner)
    check_scope(self)
    if owner == nil then
        fail("sar: cannot pin nil", 2)
    end

    self.roots[#self.roots + 1] = owner
    return owner
end

function Scope:defer(fn)
    check_scope(self)
    if type(fn) ~= "function" then
        fail("sar: deferred value must be a function", 2)
    end

    self.defers[#self.defers + 1] = fn
    return fn
end

function Scope:owned(owner, cleanup)
    check_scope(self)
    if owner == nil then
        fail("sar: cannot own nil", 2)
    end
    if type(cleanup) ~= "function" then
        fail("sar: cleanup must be a function", 2)
    end

    self:pin(owner)
    self:defer(function()
        cleanup(owner)
    end)
    return owner
end

function Scope:resource(handle, cleanup)
    local r = M.resource(handle, cleanup)
    self:pin(r)
    self:defer(function()
        r:close()
    end)
    return r
end

function Scope:arena(size, opts)
    return M.arena(self, size, opts)
end

function Scope:borrow(owner, ptr, len)
    check_scope(self)
    if owner == nil then
        fail("sar: cannot borrow nil owner", 2)
    end

    self:pin(owner)
    return setmetatable({
        owner = owner,
        scope = self,
        arena = nil,
        ptr = ptr or owner,
        len = len or 0,
        bytes = len or 0,
        generation = nil,
        end_offset = nil,
    }, BorrowMT)
end

function Scope:close()
    if self.closed then
        return
    end

    local errors
    local defers = self.defers
    if defers ~= nil then
        for i = #defers, 1, -1 do
            local ok, err = pcall(defers[i])
            if not ok then
                errors = errors or {}
                errors[#errors + 1] = tostring(err)
            end
        end
    end

    self.closed = true
    self.roots = nil
    self.defers = nil

    if errors ~= nil then
        error(table.concat(errors, "\n"), 2)
    end
end

-- Resource ------------------------------------------------------------------

function M.resource(handle, cleanup)
    if cleanup ~= nil and type(cleanup) ~= "function" then
        fail("sar: cleanup must be a function", 2)
    end

    return setmetatable({
        handle = handle,
        cleanup = cleanup,
        closed = false,
    }, ResourceMT)
end

function Resource:check()
    if self.closed then
        fail("sar: use after resource close", 3)
    end
end

function Resource:close()
    if self.closed then
        return
    end

    self.closed = true

    local handle = self.handle
    self.handle = nil

    if handle ~= nil and self.cleanup ~= nil then
        return self.cleanup(handle)
    end
end

function Resource:forget()
    self:check()
    self.closed = true

    local handle = self.handle
    self.handle = nil

    return handle
end

-- Arena ---------------------------------------------------------------------

local function parse_arena_args(a, b, c)
    -- sar.arena(size [, opts])
    -- sar.arena(scope, size [, opts])
    if is_scope(a) then
        return a, parse_size(b), c or {}
    end
    return nil, parse_size(a), b or {}
end

function M.arena(a, b, c)
    local scope, size, opts = parse_arena_args(a, b, c)

    local default_align = opts.align or DEFAULT_ALIGN
    check_integer(default_align, "alignment")
    if default_align <= 0 then
        fail("sar: arena alignment must be positive", 2)
    end

    local buffer = ffi.new("uint8_t[?]", size)

    local A = setmetatable({
        owner = buffer,
        ptr = ffi.cast("uint8_t *", buffer),
        len = size,
        bytes = size,
        offset = 0,
        default_align = default_align,
        debug = opts.debug and true or false,
        zero = opts.zero and true or false,
        generation = 0,
        closed = false,
        scope = scope,
    }, Arena)

    if scope ~= nil then
        scope:pin(A)
    end

    return A
end

function M.debug_arena(a, b, c)
    local scope, size, opts = parse_arena_args(a, b, c)
    opts.debug = true
    if scope ~= nil then
        return M.arena(scope, size, opts)
    end
    return M.arena(size, opts)
end

function Arena:close()
    if self.closed then
        return
    end

    self.closed = true
    self.generation = self.generation + 1
    self.owner = nil
    self.ptr = nil
    self.scope = nil
end

function Arena:capacity()
    check_arena(self)
    return self.bytes
end

function Arena:used()
    check_arena(self)
    return self.offset
end

function Arena:remaining()
    check_arena(self)
    return self.bytes - self.offset
end

function Arena:empty()
    check_arena(self)
    return self.offset == 0
end

function Arena:mark()
    check_arena(self)
    return {
        arena = self,
        offset = self.offset,
        generation = self.generation,
    }
end

function Arena:rewind(mark)
    check_arena(self)
    if type(mark) ~= "table" or mark.arena ~= self then
        fail("sar: invalid arena mark", 2)
    end
    if mark.generation ~= self.generation then
        fail("sar: stale arena mark", 2)
    end
    if mark.offset > self.offset then
        fail("sar: mark is ahead of current arena offset", 2)
    end

    self.offset = mark.offset
    if self.debug then
        self.generation = self.generation + 1
    end
end

function Arena:reset()
    check_arena(self)
    self.offset = 0
    if self.debug then
        self.generation = self.generation + 1
    end
end

function Arena:_alloc_raw(n, align)
    check_arena(self)
    check_integer(n, "allocation size")

    align = align or self.default_align
    check_integer(align, "alignment")
    if align <= 0 then
        fail("sar: allocation alignment must be positive", 3)
    end

    local off = align_up(self.offset, align)
    local new_off = off + n
    if new_off > self.bytes then
        fail(("sar: arena out of memory: requested %d bytes, %d bytes remaining"):format(
            n,
            self.bytes - self.offset
        ), 3)
    end

    self.offset = new_off

    local ptr = self.ptr + off
    if self.zero and n > 0 then
        ffi.fill(ptr, n, 0)
    end

    return ptr, off
end

local function make_borrow(A, ptr, len, bytes, off, ctype, elem_count)
    return setmetatable({
        owner = A,
        scope = A.scope,
        arena = A,
        ptr = ptr,
        len = elem_count or len or 0,
        bytes = bytes or len or 0,
        offset = off or 0,
        end_offset = (off or 0) + (bytes or len or 0),
        ctype = ctype,
        generation = A.generation,
    }, BorrowMT)
end

function Arena:bytes(n, align)
    n = parse_size(n)
    local ptr, off = self:_alloc_raw(n, align or 1)
    return make_borrow(self, ptr, n, n, off, "uint8_t", n)
end

function Arena:zeroed_bytes(n, align)
    local b = self:bytes(n, align)
    ffi.fill(b.ptr, b.bytes, 0)
    return b
end

function Arena:array(ctype, n, align)
    check_integer(n, "array length")

    local ct = ffi_typeof(ctype)
    local elem_size = ffi.sizeof(ct)
    local elem_align = align or math.min(math.max(elem_size, 1), 16)
    local total = elem_size * n

    local raw, off = self:_alloc_raw(total, elem_align)
    local ptr = ffi.cast(ptr_typeof(ct), raw)

    return make_borrow(self, ptr, n, total, off, ctype, n)
end

function Arena:zeroed_array(ctype, n, align)
    local a = self:array(ctype, n, align)
    ffi.fill(a.ptr, a.bytes, 0)
    return a
end

function Arena:new(ctype, ...)
    local a = self:array(ctype, 1)
    if select("#", ...) > 0 then
        local tmp = ffi.new(ffi_typeof(ctype), ...)
        a.ptr[0] = tmp
    end
    return a
end

function Arena:string(s, opts)
    check_arena(self)
    if type(s) ~= "string" then
        fail("sar: arena:string expects a Lua string", 2)
    end

    opts = opts or {}
    local n = #s
    local extra = opts.nul and 1 or 0
    local b = self:bytes(n + extra, 1)

    if n > 0 then
        ffi.copy(b.ptr, s, n)
    end
    if extra == 1 then
        b.ptr[n] = 0
    end

    b.len = n
    b.bytes = n + extra
    b.nul = opts.nul and true or false

    return b
end

function Arena:cstring(s)
    return self:string(s, { nul = true })
end

function Arena:copy(s)
    return self:string(s, { nul = false })
end

function Arena:temp(fn, ...)
    check_arena(self)
    if type(fn) ~= "function" then
        fail("sar: arena temp callback must be a function", 2)
    end

    local mark = self:mark()
    local args = pack(...)
    local out

    local ok, err = xpcall(function()
        out = pack(fn(self, unpack(args, 1, args.n)))
    end, debug.traceback)

    local rewind_ok, rewind_err = pcall(function()
        self:rewind(mark)
    end)

    if not ok then
        if not rewind_ok then
            error(tostring(err) .. "\nsar arena rewind error:\n" .. tostring(rewind_err), 0)
        end
        error(err, 0)
    end

    if not rewind_ok then
        error(rewind_err, 0)
    end

    return unpack(out, 1, out.n)
end

function Arena:contains(ptr)
    check_arena(self)

    local p = tonumber(ffi.cast("uintptr_t", ptr))
    local lo = tonumber(ffi.cast("uintptr_t", self.ptr))
    local hi = lo + self.bytes

    return p >= lo and p < hi
end

function Arena:offset_of(ptr)
    check_arena(self)

    local p = tonumber(ffi.cast("uintptr_t", ptr))
    local lo = tonumber(ffi.cast("uintptr_t", self.ptr))
    local off = p - lo

    if off < 0 or off >= self.bytes then
        fail("sar: pointer does not belong to arena", 2)
    end

    return off
end

function Arena:borrow(ptr, len)
    check_arena(self)
    if not self:contains(ptr) then
        fail("sar: borrowed pointer is outside arena", 2)
    end

    local off = self:offset_of(ptr)
    return make_borrow(self, ptr, len or 0, len or 0, off, nil, len or 0)
end

-- Borrow --------------------------------------------------------------------

function Borrow:check()
    if self.scope ~= nil then
        check_scope(self.scope)
    end

    if self.arena ~= nil then
        check_arena(self.arena)
        if self.arena.debug then
            if self.generation ~= self.arena.generation then
                fail("sar: arena allocation invalidated by reset/rewind", 3)
            end
            if self.end_offset > self.arena.offset then
                fail("sar: arena allocation invalidated by rewind", 3)
            end
        end
    end

    return true
end

function Borrow:checked_ptr()
    self:check()
    return self.ptr
end

function Borrow:string(n)
    self:check()
    return ffi.string(self.ptr, n or self.bytes or self.len)
end

function Borrow:fill(byte, n)
    self:check()
    ffi.fill(self.ptr, n or self.bytes or self.len, byte or 0)
    return self
end

function Borrow:copy_from(src, n)
    self:check()

    local sptr = raw_ptr(src)
    local bytes = n or raw_len(src)
    if bytes == nil then
        fail("sar: copy_from requires byte count for raw pointers", 2)
    end
    if bytes > self.bytes then
        fail("sar: copy_from source is larger than destination", 2)
    end

    ffi.copy(self.ptr, sptr, bytes)
    return self
end

function Borrow:as(ctype)
    self:check()

    return setmetatable({
        owner = self.owner,
        scope = self.scope,
        arena = self.arena,
        ptr = ffi.cast(ptr_typeof(ctype), self.ptr),
        len = self.len,
        bytes = self.bytes,
        offset = self.offset,
        end_offset = self.end_offset,
        ctype = ctype,
        generation = self.generation,
    }, BorrowMT)
end

-- Utility memory ops --------------------------------------------------------

function M.fill(dst, byte, n)
    local p = raw_ptr(dst)
    local bytes = n or raw_len(dst)
    if bytes == nil then
        fail("sar: fill requires byte count for raw pointers", 2)
    end

    ffi.fill(p, bytes, byte or 0)
    return dst
end

function M.copy(dst, src, n)
    local dp = raw_ptr(dst)
    local sp = raw_ptr(src)
    local bytes = n

    if bytes == nil then
        local dl = raw_len(dst)
        local sl = raw_len(src)
        if dl == nil or sl == nil then
            fail("sar: copy requires byte count for raw pointers", 2)
        end
        bytes = math.min(dl, sl)
    end

    ffi.copy(dp, sp, bytes)
    return dst
end

function M.string(src, n)
    local p = raw_ptr(src)
    local bytes = n or raw_len(src)
    if bytes == nil then
        fail("sar: string requires byte count for raw pointers", 2)
    end

    return ffi.string(p, bytes)
end

return M
