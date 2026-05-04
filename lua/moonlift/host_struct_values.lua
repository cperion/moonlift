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

    function api.variant(name, ty)
        assert_name(name, "variant")
        local tv = api.as_type_value(ty or api.void, "variant expects a type value")
        return { kind = "variant", name = name, type = tv, decl = Ty.VariantDecl(name, tv.ty) }
    end

    function api.struct(name, fields)
        return make_struct(name, fields, nil)
    end

    function api.union(name, fields)
        return make_union(name, fields, nil)
    end

    function api._module_struct(module_value, name, fields)
        return make_struct(name, fields, module_value)
    end

    function api._module_union(module_value, name, fields)
        return make_union(name, fields, module_value)
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
end

return M
