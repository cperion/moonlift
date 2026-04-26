local ffi = require("ffi")

local M = {}

if not rawget(_G, "__moonlift_value_proxy_cdef") then
    ffi.cdef[[
    typedef struct MoonliftValueRef {
        uint64_t session_id;
        uint32_t family_id;
        uint32_t type_id;
        uint32_t tag;
        uint32_t flags;
        uint64_t value_id;
        uint32_t index;
        uint32_t reserved;
    } MoonliftValueRef;
    ]]
    rawset(_G, "__moonlift_value_proxy_cdef", true)
end

local REF = {}
local PTR = {}
local OWNER = {}
local CACHE = {}

local families = {}
local family_by_name = {}

local Methods = {}
local MT = {}

local function family_for_id(id)
    local family = families[tonumber(id)]
    if not family then error("unknown Moonlift value proxy family " .. tostring(id), 3) end
    return family
end

function M.register_family(name, family)
    assert(type(name) == "string", "proxy family name must be a string")
    assert(type(family) == "table", "proxy family must be a table")
    local existing = family_by_name[name]
    if existing then
        family.id = existing
        families[existing] = family
        return existing
    end
    local id = #families + 1
    family.name = family.name or name
    family.id = id
    families[id] = family
    family_by_name[name] = id
    return id
end

function M.family_id(name)
    return family_by_name[name]
end

function M.family(id)
    return family_for_id(id)
end

function M.new_ref(family_id, opts)
    opts = opts or {}
    local ref = ffi.new("MoonliftValueRef[1]")
    ref[0].session_id = opts.session_id or 0
    ref[0].family_id = assert(family_id, "missing proxy family id")
    ref[0].type_id = opts.type_id or 0
    ref[0].tag = opts.tag or 0
    ref[0].flags = opts.flags or 0
    ref[0].value_id = opts.value_id or 0
    ref[0].index = opts.index or 0
    ref[0].reserved = opts.reserved or 0
    return ref
end

function M.wrap(ref, owner, opts)
    opts = opts or {}
    local value = {
        [REF] = ref,
        [OWNER] = owner,
    }
    if opts.ptr ~= nil then value[PTR] = opts.ptr end
    if opts.cache then value[CACHE] = {} end
    return setmetatable(value, MT)
end

function M.ref(value)
    return rawget(value, REF)
end

function M.owner(value)
    return rawget(value, OWNER)
end

function M.ptr(value)
    return rawget(value, PTR)
end

function M.cache(value)
    local cache = rawget(value, CACHE)
    if not cache then
        cache = {}
        rawset(value, CACHE, cache)
    end
    return cache
end

function M.is_proxy(value)
    return type(value) == "table" and rawget(value, REF) ~= nil
end

function Methods:raw_ref()
    return rawget(self, REF)
end

function Methods:owner()
    return rawget(self, OWNER)
end

function Methods:ptr()
    return rawget(self, PTR)
end

function Methods:pairs()
    local ref = rawget(self, REF)
    local family = family_for_id(ref[0].family_id)
    if family.pairs then return family.pairs(self, ref[0], rawget(self, OWNER)) end
    return function() return nil end
end

function Methods:ipairs()
    local ref = rawget(self, REF)
    local family = family_for_id(ref[0].family_id)
    if family.ipairs then return family.ipairs(self, ref[0], rawget(self, OWNER)) end
    return function() return nil end
end

function Methods:to_table()
    local ref = rawget(self, REF)
    local family = family_for_id(ref[0].family_id)
    if family.to_table then return family.to_table(self, ref[0], rawget(self, OWNER)) end
    error("Moonlift value proxy family '" .. tostring(family.name) .. "' cannot materialize to a Lua table")
end

function MT.__index(self, key)
    local method = Methods[key]
    if method then return method end
    local ref = rawget(self, REF)
    local family = family_for_id(ref[0].family_id)
    if family.index then return family.index(self, key, ref[0], rawget(self, OWNER)) end
    return nil
end

function MT.__newindex()
    error("Moonlift value proxies are immutable", 2)
end

function MT.__len(self)
    local ref = rawget(self, REF)
    local family = family_for_id(ref[0].family_id)
    if family.len then return family.len(self, ref[0], rawget(self, OWNER)) end
    error("Moonlift value proxy family '" .. tostring(family.name) .. "' has no length")
end

function MT.__tostring(self)
    local ref = rawget(self, REF)
    local family = family_for_id(ref[0].family_id)
    if family.tostring then return family.tostring(self, ref[0], rawget(self, OWNER)) end
    return "MoonliftValue(" .. tostring(family.name) .. ")"
end

M.REF = REF
M.PTR = PTR
M.OWNER = OWNER
M.CACHE = CACHE

return M
