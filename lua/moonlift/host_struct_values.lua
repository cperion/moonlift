local M = {}

local FieldValue = {}
FieldValue.__index = FieldValue

local StructValue = {}
StructValue.__index = StructValue
StructValue.__moonlift_host_type_value = true

local TypeDeclValue = {}
TypeDeclValue.__index = TypeDeclValue

local DraftStructValue = {}
DraftStructValue.__index = DraftStructValue
DraftStructValue.__moonlift_host_type_value = true

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
end

function StructValue:as_type_value()
    return self.type
end

function StructValue:as_moonlift_type()
    return self.type.ty
end

function StructValue:moonlift_splice_source()
    return self.type.source_hint
end

function StructValue:__tostring()
    return "MoonStructValue(" .. self.name .. ")"
end

function TypeDeclValue:as_item()
    return self.item
end

function DraftStructValue:as_type_value()
    return self.type
end

function DraftStructValue:as_moonlift_type()
    return self.type.ty
end

function DraftStructValue:moonlift_splice_source()
    return self.type.source_hint
end

function DraftStructValue:add_field(name, ty)
    if self.sealed then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueSealedMutation(self.name)) end
    assert_name(name, "struct field")
    if self.fields_by_name[name] ~= nil then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueDuplicateField(self.name, name)) end
    local f = self.api.field(name, ty)
    self.fields[#self.fields + 1] = f
    self.fields_by_name[name] = f.type
    self.type.fields_by_name = self.fields_by_name
    return self
end

function DraftStructValue:seal()
    if self.sealed then self.api.raise_host_issue(self.session.T.MoonHost.HostIssueAlreadySealed(self.name)) end
    local decls = {}
    for i = 1, #self.fields do decls[i] = self.fields[i].decl end
    local Tr = self.session.T.MoonTree
    self.decl = Tr.TypeDeclStruct(self.name, decls)
    self.item = Tr.ItemType(self.decl)
    self.sealed = true
    self.owner_module.items[#self.owner_module.items + 1] = self.item
    self.owner_module.type_values[#self.owner_module.type_values + 1] = self
    return self
end

function DraftStructValue:__tostring()
    return "MoonDraftStructValue(" .. self.name .. (self.sealed and ":sealed" or ":open") .. ")"
end

local function list_has_duplicate_field(fields)
    local seen = {}
    for i = 1, #fields do
        local name = fields[i].name
        if seen[name] then return name end
        seen[name] = true
    end
    return nil
end

function M.Install(api, session)
    local T = session.T
    local C, Ty, Tr = T.MoonCore, T.MoonType, T.MoonTree

    local function as_field(v, site)
        if type(v) == "table" and getmetatable(v) == FieldValue then return v end
        error((site or "expected field value") .. ": got " .. type(v), 3)
    end

    local function normalize_fields(fields)
        assert(type(fields) == "table", "fields must be an ordered list")
        local out, by_name = {}, {}
        for i = 1, #fields do
            local f = as_field(fields[i], "struct field")
            out[#out + 1] = f
            by_name[f.name] = f.type
        end
        local dup = list_has_duplicate_field(out)
        if dup ~= nil then api.raise_host_issue(session.T.MoonHost.HostIssueDuplicateField("<type>", tostring(dup))) end
        return out, by_name
    end

    local function field_decls(fields)
        local out = {}
        for i = 1, #fields do out[i] = fields[i].decl end
        return out
    end

    local function make_struct(name, fields, owner_module)
        assert_name(name, "struct")
        local fs, by_name = normalize_fields(fields)
        local decl = Tr.TypeDeclStruct(name, field_decls(fs))
        local type_value
        if owner_module then
            type_value = api.type_from_asdl(Ty.TNamed(Ty.TypeRefGlobal(owner_module.name, name)), name, { fields_by_name = by_name })
        else
            type_value = api.path_named(name)
            type_value.fields_by_name = by_name
        end
        return setmetatable({
            kind = "struct",
            session = session,
            name = name,
            fields = fs,
            fields_by_name = by_name,
            decl = decl,
            item = Tr.ItemType(decl),
            type = type_value,
            owner_module = owner_module,
        }, StructValue)
    end

    local function make_union(name, fields, owner_module)
        assert_name(name, "union")
        local fs, by_name = normalize_fields(fields)
        local decl = Tr.TypeDeclUnion(name, field_decls(fs))
        local type_value
        if owner_module then
            type_value = api.type_from_asdl(Ty.TNamed(Ty.TypeRefGlobal(owner_module.name, name)), name, { fields_by_name = by_name })
        else
            type_value = api.path_named(name)
            type_value.fields_by_name = by_name
        end
        return setmetatable({ kind = "union", session = session, name = name, fields = fs, fields_by_name = by_name, decl = decl, item = Tr.ItemType(decl), type = type_value, owner_module = owner_module }, StructValue)
    end

    function api.field(name, ty)
        assert_name(name, "field")
        local tv = api.as_type_value(ty, "field expects a type value")
        return setmetatable({
            kind = "field",
            session = session,
            name = name,
            type = tv,
            decl = Ty.FieldDecl(name, tv.ty),
        }, FieldValue)
    end

    local function sorted_string_keys(t)
        local keys = {}
        for k in pairs(t) do
            if type(k) == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        return keys
    end

    local function field_from_spec(spec, site)
        if type(spec) == "table" and getmetatable(spec) == FieldValue then return spec end
        if type(spec) == "table" and spec.name ~= nil then
            return api.field(spec.name, spec.type)
        end
        if type(spec) == "table" and type(spec[1]) == "string" then
            return api.field(spec[1], spec[2])
        end
        error((site or "fields") .. " expects field specs as {name=..., type=...} or {\"name\", type}", 3)
    end

    function api.fields(specs)
        assert(type(specs) == "table", "moon.fields expects a table")
        local out = {}
        if #specs > 0 then
            for i = 1, #specs do
                out[i] = field_from_spec(specs[i], "fields element")
            end
            return out
        end
        -- Convenience map form: moon.fields { x = moon.i32, y = moon.i32 }.
        -- Lua 5.1 does not preserve literal table key order, so map keys are
        -- emitted in sorted order. Use list/pair form when layout order matters.
        local keys = sorted_string_keys(specs)
        for i = 1, #keys do
            out[i] = api.field(keys[i], specs[keys[i]])
        end
        return out
    end

    function api.variant(name, ty)
        assert_name(name, "variant")
        local tv = api.as_type_value(ty or api.void, "variant expects a type value")
        return { kind = "variant", name = name, type = tv, decl = Ty.VariantDecl(name, tv.ty, {}) }
    end

    local function variant_from_spec(spec, site)
        if type(spec) == "string" then return api.variant(spec, api.void) end
        if type(spec) == "table" and type(spec[1]) == "string" then
            return api.variant(spec[1], spec[2] or api.void)
        end
        if type(spec) ~= "table" or spec.name == nil then
            error((site or "variants") .. " expects variant specs as {name=..., payload=...}, {\"name\", payload}, or \"name\"", 3)
        end
        if spec.fields then
            local field_values = api.fields(spec.fields)
            local fields = {}
            for j = 1, #field_values do fields[j] = field_values[j].decl end
            return { kind = "variant", name = spec.name, payload = nil, fields = fields,
                     decl = Ty.VariantDecl(spec.name, api.void.ty, fields) }
        end
        return api.variant(spec.name, spec.payload or spec.type or api.void)
    end

    function api.variants(specs)
        assert(type(specs) == "table", "moon.variants expects a table")
        local out = {}
        if #specs > 0 then
            for i = 1, #specs do out[i] = variant_from_spec(specs[i], "variants element") end
            return out
        end
        -- Convenience map form: moon.variants { ok = T, err = E }.
        -- Keys are sorted; use list/pair form to control declaration order.
        local keys = sorted_string_keys(specs)
        for i = 1, #keys do out[i] = api.variant(keys[i], specs[keys[i]]) end
        return out
    end

    function api._module_struct(module_value, name, fields)
        return make_struct(name, fields, module_value)
    end

    function api.struct(name, fields)
        return make_struct(name, fields, nil)
    end

    function api._module_union(module_value, name, fields)
        return make_union(name, fields, module_value)
    end

    function api.union(name, fields)
        return make_union(name, fields, nil)
    end

    function api._module_enum(module_value, name, variants)
        assert_name(name, "enum")
        assert(type(variants) == "table", "enum variants must be an ordered list")
        local names = {}
        local seen = {}
        for i = 1, #variants do
            local v = variants[i]
            assert_name(v, "enum variant")
            assert(not seen[v], "duplicate enum variant: " .. v)
            seen[v] = true
            names[i] = C.Name(v)
        end
        local decl = Tr.TypeDeclEnumSugar(name, names)
        local type_value = api.type_from_asdl(Ty.TNamed(Ty.TypeRefGlobal(module_value.name, name)), name)
        return setmetatable({ kind = "enum", session = session, name = name, decl = decl, item = Tr.ItemType(decl), type = type_value, owner_module = module_value }, StructValue)
    end

    function api._module_tagged_union(module_value, name, variants)
        assert_name(name, "tagged_union")
        assert(type(variants) == "table", "tagged_union variants must be an ordered list")
        local decls = {}
        local seen = {}
        for i = 1, #variants do
            local v = variants[i]
            assert(type(v) == "table" and v.kind == "variant", "tagged_union expects variant values")
            assert(not seen[v.name], "duplicate tagged union variant: " .. v.name)
            seen[v.name] = true
            decls[i] = v.decl
        end
        local decl = Tr.TypeDeclTaggedUnionSugar(name, decls)
        local type_value = api.type_from_asdl(Ty.TNamed(Ty.TypeRefGlobal(module_value.name, name)), name)
        return setmetatable({ kind = "tagged_union", session = session, name = name, decl = decl, item = Tr.ItemType(decl), type = type_value, owner_module = module_value }, StructValue)
    end

    function api._module_newstruct(module_value, name)
        assert_name(name, "newstruct")
        local type_value = api.type_from_asdl(Ty.TNamed(Ty.TypeRefGlobal(module_value.name, name)), name, { fields_by_name = {} })
        local draft = setmetatable({
            kind = "struct_draft",
            session = session,
            api = api,
            name = name,
            fields = {},
            fields_by_name = {},
            type = type_value,
            owner_module = module_value,
            sealed = false,
        }, DraftStructValue)
        module_value.drafts[#module_value.drafts + 1] = draft
        return draft
    end

    api.FieldValue = FieldValue
    api.StructValue = StructValue
    api.DraftStructValue = DraftStructValue
    api.TypeDeclValue = TypeDeclValue

    -- ExitProtocol: unified exits for union variants and region continuations.
    -- Implements moonlift_splice(role) to dispatch to the right shape based on
    -- whether the splice is in union context (variant_list) or region context
    -- (cont_slot_list).
    local ExitProtocol = {}
    ExitProtocol.__index = ExitProtocol

    function ExitProtocol:moonlift_splice(role, session, site, slot)
        local O = session.T.MoonOpen
        if role == "variant_list" then
            local out = {}
            for _, e in ipairs(self.exits) do
                local name = e.name or e[1]
                local fields = e.fields or {}
                local decl
                if e.decl then
                    decl = e.decl
                elseif #fields > 0 then
                    decl = Ty.VariantDecl(name, Ty.TScalar(C.ScalarVoid), fields)
                else
                    local ty = api.as_type_value(e.ty or e.type or api.void, "exit type").ty
                    decl = Ty.VariantDecl(name, ty, {})
                end
                out[#out + 1] = decl
            end
            return O.SlotBinding(O.SlotRegion(slot), O.SlotValueVariants(out))
        end
        if role == "cont_slot_list" then
            local out = {}
            for _, e in ipairs(self.exits) do
                local slot_key = e.slot and e.slot.key or ("cont:" .. self._owner .. ":" .. (e.name or e[1]))
                local name = e.name or e[1]
                local params = {}
                -- Convert fields/payload to block params for continuation slots.
                if e.decl and e.decl.fields and #e.decl.fields > 0 then
                    for k = 1, #e.decl.fields do
                        local f = e.decl.fields[k]
                        params[#params + 1] = session.T.MoonTree.BlockParam(f.field_name, f.ty)
                    end
                elseif e.decl and e.decl.payload and tostring(e.decl.payload) ~= tostring(api.void.ty) then
                    params[#params + 1] = session.T.MoonTree.BlockParam("arg1", e.decl.payload)
                else
                    for k = 1, #(e.fields or e.params or {}) do
                        local f = e.fields[k] or e.params[k]
                        local fn = f.name or f.field_name or f[1]
                        local ft = (f.type or f.ty or f[2])
                        params[#params + 1] = session.T.MoonTree.BlockParam(fn, api.as_type_value(ft, "cont param").ty)
                    end
                end
                out[#out + 1] = O.ContSlot(slot_key, name, params)
            end
            return O.SlotBinding(O.SlotRegion(slot), O.SlotValueContSlots(out))
        end
        error((site or "splice") .. ": ExitProtocol cannot splice as " .. role, 2)
    end

    local ExitMetatable = {}
    ExitMetatable.__index = ExitProtocol

    function api.exit(name, ty)
        local tv = api.as_type_value(ty or api.void, "exit expects a type value")
        local fields = {}
        if ty ~= nil and ty ~= api.void then fields[1] = { name = "arg1", type = tv, ty = tv } end
        return { kind = "exit", name = name, ty = tv, type = tv, fields = fields, is_exit = true }
    end

    local function exit_from_spec(spec, site)
        if type(spec) == "string" then return api.exit(spec, api.void) end
        if type(spec) == "table" then
            if type(spec[1]) == "string" then return api.exit(spec[1], spec[2] or api.void) end
            if spec.name then return api.exit(spec.name, spec.payload or spec.type or api.void) end
        end
        error((site or "exits") .. " expects exit specs", 3)
    end

    function api.exits(specs)
        assert(type(specs) == "table", "moon.exits expects a table")
        local out = {}
        if #specs > 0 then
            for i = 1, #specs do out[i] = exit_from_spec(specs[i], "exits element") end
        else
            local keys = sorted_string_keys(specs)
            for i = 1, #keys do out[i] = api.exit(keys[i], specs[keys[i]]) end
        end
        return setmetatable({ kind = "exit_protocol", exits = out, _owner = "exits" }, ExitMetatable)
    end

    api.ExitProtocol = ExitProtocol
end

return M
