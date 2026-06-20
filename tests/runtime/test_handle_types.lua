package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")
local T = pvm.context()
schema.Define(T)

local P = require("moonlift.parse").Define(T)
local TC = require("moonlift.tree_typecheck").Define(T)
local SL = require("moonlift.sem_layout_resolve").Define(T)
local CodeType = require("moonlift.code_type").Define(T)
local TypeLayout = require("moonlift.type_size_align").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)

local Ty = T.MoonType
local Tr = T.MoonTree
local C = T.MoonCore
local Sem = T.MoonSem

local parsed_handle = P.parse_handle("handle Texture : u32 invalid 0 end")
assert(#parsed_handle.issues == 0, parsed_handle.issues[1] and parsed_handle.issues[1].message)
assert(pvm.classof(parsed_handle.value.decl) == Tr.TypeDeclHandle)
assert(parsed_handle.value.decl.name == "Texture")
assert(pvm.classof(parsed_handle.value.decl.repr) == Ty.HandleReprScalar)
assert(parsed_handle.value.decl.repr.scalar == C.ScalarU32)
assert(pvm.classof(parsed_handle.value.decl.invalid) == Ty.HandleInvalidInt)

local parsed_handle_facts = P.parse_handle([[handle ComponentRef : u32 invalid 0
    domain ComponentStore
    target Component
end]])
assert(#parsed_handle_facts.issues == 0, parsed_handle_facts.issues[1] and parsed_handle_facts.issues[1].message)
assert(#parsed_handle_facts.value.decl.facts == 2, "handle domain/target facts should be explicit ASDL")
assert(pvm.classof(parsed_handle_facts.value.decl.facts[1]) == Ty.HandleDomain)
assert(pvm.classof(parsed_handle_facts.value.decl.facts[2]) == Ty.HandleTarget)

local lease_ty = P.parse_type("lease ptr(Texture)").value
assert(pvm.classof(lease_ty) == Ty.TLease)
assert(pvm.classof(lease_ty.base) == Ty.TPtr)
assert(pvm.classof(lease_ty.base.elem) == Ty.TNamed)

local handle_ty = Ty.THandle(Ty.TypeRefPath(C.Path({ C.Name("Texture") })), parsed_handle.value.decl.repr)
local layout = TypeLayout.result(handle_ty, Sem.LayoutEnv({}))
assert(layout.layout.size == 4 and layout.layout.align == 4)
assert(CodeType.code_type_key(CodeType.type_to_code(handle_ty, {})) == "handle_u32")

local bad_lease = P.parse_module([[func bad(x: lease i32): void
    return
end
]])
assert(#TC.check_module(bad_lease.module).issues > 0, "lease base must be ptr/view")

local bad_cast = P.parse_module([[handle Texture : u32 invalid 0 end
func bad_cast(t: Texture): u32
    return as(u32, t)
end
]])
assert(#TC.check_module(bad_cast.module).issues > 0, "handles are opaque and cannot cast to repr")

local module = P.parse_module([[handle Texture : u32 invalid 0 end
func id(t: Texture): Texture
    if t == Texture.invalid then return t end
    return t
end
func pack(t: Texture): u32
    return repr(t)
end
func unpack(raw: u32): Texture
    return Texture.from_repr(raw)
end
]])
assert(#module.issues == 0, module.issues[1] and module.issues[1].message)
local typed = TC.check_module(module.module)
assert(#typed.issues == 0)
local sem = SL.module(typed.module)
local code = TreeToCode.module(sem)
assert(#code.funcs == 3)
assert(code.sigs[1].id.text == "codesig_handle_u32_to_handle_u32")

local lease_escape = P.parse_module([[func bad_return(p: lease ptr(i32)): lease ptr(i32)
    return p
end
]])
assert(#TC.check_module(lease_escape.module).issues > 0, "leases must not escape through returns")

local lease_field = P.parse_module([[struct Bad
    p: lease ptr(i32)
end
]])
assert(#TC.check_module(lease_field.module).issues > 0, "leases must not be durable fields")

local lease_call = P.parse_module([[extern retain(p: ptr(i32)): void end
func bad_call(p: lease ptr(i32)): void
    retain(p)
end
]])
assert(#TC.check_module(lease_call.module).issues > 0, "leases must not pass to plain retaining ptr params")

local lease_forward = P.parse_module([[extern consume(noescape p: ptr(i32)): void end
func ok_call(p: lease ptr(i32)): void
    consume(p)
end
func ok_raw_call(p: ptr(i32)): void
    consume(p)
end
]])
assert(#TC.check_module(lease_forward.module).issues == 0, "leases and raw pointers may pass to noescape params")

local lease_access = P.parse_module([[func read_first(p: lease ptr(i32)): i32
    return p[0]
end
]])
local lease_access_typed = TC.check_module(lease_access.module)
assert(#lease_access_typed.issues == 0, "leases support direct pointer access")
TreeToCode.module(SL.module(lease_access_typed.module))

local lease_preserve = P.parse_module([[struct Store
    x: i32
end
func read_store(readonly s: ptr(Store)): void
    return
end
func ok_preserve(s: ptr(Store), p: lease ptr(i32)): void
    read_store(s)
end
]])
assert(#TC.check_module(lease_preserve.module).issues == 0, "readonly store calls preserve live leases")

local lease_invalidate = P.parse_module([[struct Store
    x: i32
end
func mutate(s: ptr(Store)): void
    return
end
func bad_invalidate(s: ptr(Store), p: lease ptr(i32)): void
    mutate(s)
end
]])
assert(#TC.check_module(lease_invalidate.module).issues > 0, "mutable store calls may not run while a lease is live")

local lease_origin_other_store = P.parse_module([[struct Store
    x: i32
end
func mutate(s: ptr(Store)): void
    return
end
func ok_other_store(s1: ptr(Store), s2: ptr(Store), p: lease(s1) ptr(i32)): void
    mutate(s2)
end
]])
assert(#TC.check_module(lease_origin_other_store.module).issues == 0, "origin-tagged leases allow invalidating unrelated stores")

local lease_origin_same_store = P.parse_module([[struct Store
    x: i32
end
func mutate(s: ptr(Store)): void
    return
end
func bad_same_store(s1: ptr(Store), p: lease(s1) ptr(i32)): void
    mutate(s1)
end
]])
assert(#TC.check_module(lease_origin_same_store.module).issues > 0, "origin-tagged leases reject invalidating their store")

local lease_preserve_modifier = P.parse_module([[struct Store
    x: i32
end
func stable_update(preserve s: ptr(Store)): void
    return
end
func ok_stable_update(s: ptr(Store), p: lease(s) ptr(i32)): void
    stable_update(s)
end
]])
assert(#TC.check_module(lease_preserve_modifier.module).issues == 0, "preserve modifier marks non-invalidating store updates")

local handle_region_ok = P.parse_module([[struct ComponentStore
    x: i32
end
struct Component
    x: i32
end
handle ComponentRef : u32 invalid 0
    domain ComponentStore
    target Component
end
region component_lookup(readonly store: ptr(ComponentStore), h: ComponentRef;
    found(c: lease ptr(Component))
  | missing)
entry start()
    jump missing()
end
end
]])
assert(#handle_region_ok.issues == 0, handle_region_ok.issues[1] and handle_region_ok.issues[1].message)
assert(#TC.check_module(handle_region_ok.module).issues == 0, "handle target/domain should accept coherent lookup region")

local handle_region_bad_target = P.parse_module([[struct ComponentStore
    x: i32
end
struct Component
    x: i32
end
struct Texture
    x: i32
end
handle ComponentRef : u32 invalid 0
    domain ComponentStore
    target Component
end
region component_lookup(readonly store: ptr(ComponentStore), h: ComponentRef;
    found(t: lease ptr(Texture))
  | missing)
entry start()
    jump missing()
end
end
]])
assert(#TC.check_module(handle_region_bad_target.module).issues > 0, "handle target fact should reject leases to the wrong target")

local handle_region_bad_domain = P.parse_module([[struct ComponentStore
    x: i32
end
struct TextureStore
    x: i32
end
struct Component
    x: i32
end
handle ComponentRef : u32 invalid 0
    domain ComponentStore
    target Component
end
region component_lookup(readonly store: ptr(TextureStore), h: ComponentRef;
    found(c: lease ptr(Component))
  | missing)
entry start()
    jump missing()
end
end
]])
assert(#TC.check_module(handle_region_bad_domain.module).issues > 0, "handle domain fact should require access to the owning store domain")

print("ok test_handle_types")
