#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local F = T.LuaFFI
local S = T.Stencil
local Validate = require("lua_compile.lua_ffi_validate")

local function assert_ok(ok, errors)
  if not ok then error(table.concat(errors, "\n"), 2) end
end

local function assert_bad(ok, errors, needle)
  assert(not ok, "expected invalid FFI metadata")
  local text = table.concat(errors, "\n")
  assert(text:find(needle, 1, true), "expected error containing " .. needle .. ", got:\n" .. text)
end

local function name(s) return F.CName(s) end
local function id(n) return F.CTypeId(n) end

-- Scalar, pointer, array, function, opaque, and typedef types.
local void_t = F.ScalarType(id(1), F.CVoid, F.Signless, 0, 0)
local int_t = F.ScalarType(id(2), F.CInt, F.Signed, 4, 4)
local double_t = F.ScalarType(id(3), F.CDouble, F.Signless, 8, 8)
local char_t = F.ScalarType(id(4), F.CChar, F.Signless, 1, 1)
local int_ptr_t = F.PointerType(id(5), int_t, false, false)
local int_array_t = F.ArrayType(id(6), int_t, 8, 32, 4)
local flex_char_array_t = F.IncompleteArrayType(id(7), char_t)
local opaque_t = F.OpaqueTagType(id(8), name("opaque_handle"))
local typedef_t = F.TypedefType(id(9), name("int_ptr_alias"), int_ptr_t)
local params = F.CParamList({
  F.CParam(name("x"), int_t, F.CValueParam),
  F.CParam(name("scale"), double_t, F.CValueParam),
}, false)
local fn_t = F.FunctionType(id(10), F.SystemVAMD64, int_t, params)
local void_fn_t = F.FunctionType(id(11), F.PlatformDefaultABI, void_t, F.CParamList({}, false))

for _, ty in ipairs({ void_t, int_t, double_t, char_t, int_ptr_t, int_array_t, flex_char_array_t, opaque_t, typedef_t, fn_t, void_fn_t }) do
  assert(pvm.classof(ty) and F.CType.members[pvm.classof(ty)])
  assert_ok(Validate.ctype(ty))
end

-- Struct layout: normal field, bitfield, flexible array member.
local field_value = F.CField(name("value"), int_t, F.NormalField, 0, 32)
local field_flags = F.CField(name("flags"), int_t, F.BitField, 32, 3)
local field_tail = F.CField(name("tail"), flex_char_array_t, F.FlexibleArrayMember, 64, 0)
local struct_layout = F.CRecordLayout(name("struct_foo"), false, true, 8, 4, { field_value, field_flags, field_tail }, "sha256:layout-foo")
local struct_t = F.StructType(id(12), name("struct_foo"), struct_layout)
assert_ok(Validate.record_layout(struct_layout))
assert_ok(Validate.ctype(struct_t))

-- Enum layout.
local enum_layout = F.CEnumLayout(name("enum_color"), F.CInt, 4, 4, {
  F.CEnumItem(name("red"), 1),
  F.CEnumItem(name("green"), 2),
}, "sha256:layout-color")
local enum_t = F.EnumType(id(13), name("enum_color"), enum_layout)
assert_ok(Validate.enum_layout(enum_layout))
assert_ok(Validate.ctype(enum_t))

-- Dynamic library plus typed function and data symbols.
local libc = F.CLib(F.CLibId(1), name("libc"), F.DynamicLibrary, "libc.so.6", true)
local process = F.CLib(F.CLibId(2), name("process"), F.ProcessLibrary, "", true)
local fn_sym = F.CSymbol(F.CSymbolId(1), name("ffi_test_fn"), libc, F.FunctionSymbol, fn_t, F.SystemVAMD64, true, "addr:ffi_test_fn")
local data_sym = F.CSymbol(F.CSymbolId(2), name("ffi_test_data"), process, F.DataSymbol, int_t, F.PlatformDefaultABI, true, "addr:ffi_test_data")
assert_ok(Validate.symbol(fn_sym))
assert_ok(Validate.symbol(data_sym))

-- C data with inline/external/owned/static storage and finalizer/ownership states.
local no_finalizer = F.NoFinalizer
local c_finalizer = F.CFunctionFinalizer(F.CFinalizerId(1), F.CSymbol(F.CSymbolId(3), name("ffi_test_finalizer"), libc, F.FunctionSymbol, void_fn_t, F.PlatformDefaultABI, true, "addr:ffi_test_finalizer"))
local inline_data = F.CData(int_t, F.InlineStorage("sha256:inline-i32", 4), c_finalizer, F.FinalizerAttachedOwnership, F.CMetatypeId(0))
local external_data = F.CData(int_ptr_t, F.ExternalPointerStorage("ptr:external", 8), no_finalizer, F.BorrowedOwnership, F.CMetatypeId(0))
local owned_data = F.CData(int_array_t, F.OwnedHeapStorage("ptr:owned", 32), no_finalizer, F.OwnedOwnership, F.CMetatypeId(0))
local static_data = F.CData(int_t, F.StaticSymbolStorage(data_sym, 4), no_finalizer, F.BorrowedOwnership, F.CMetatypeId(0))
for _, data in ipairs({ inline_data, external_data, owned_data, static_data }) do
  assert_ok(Validate.cdata(data))
end

-- Callback object.
local callback = F.CCallback(F.CCallbackId(1), fn_t, F.SystemVAMD64, name("lua_callback_ref"), "thunk:callback1", true)
assert_ok(Validate.callback(callback))

-- Registry with all primary typed FFI metadata.
local registry = F.FFIRegistry(
  { void_t, int_t, double_t, char_t, int_ptr_t, int_array_t, flex_char_array_t, opaque_t, typedef_t, fn_t, void_fn_t, struct_t, enum_t },
  { struct_layout },
  { enum_layout },
  { libc, process },
  { fn_sym, data_sym },
  { callback },
  { inline_data, external_data, owned_data, static_data },
  { no_finalizer, c_finalizer }
)
assert_ok(Validate.registry(registry))
assert_ok(C.validate.lua_ffi_registry(registry))

-- Operation outcomes are typed data, not strings or helper calls.
local cdef_ok = F.CDefOk(F.CDeclId(1), registry)
local type_ok = F.TypeQueryOk(typedef_t)
local layout_ok = F.LayoutQueryOk(struct_t, 8, 4, "sha256:layout-foo")
local load_ok = F.LoadLibraryOk(libc)
local symbol_ok = F.ResolveSymbolOk(fn_sym)
local new_ok = F.NewCDataOk(inline_data)
local call_ok = F.FFICallOk(int_t)
local cb_ok = F.CallbackOk(callback)
local fin_ok = F.FinalizerOk(c_finalizer)
local err = F.FFIErrorResult(F.FFIError(F.SymbolResolutionError, name("missing symbol")))
for _, outcome in ipairs({ cdef_ok, type_ok, layout_ok, load_ok, symbol_ok, new_ok, call_ok, cb_ok, fin_ok, err }) do
  assert(F.OperationOutcome.members[pvm.classof(outcome)])
end

-- FFI facts for specialization/stencil selection.
local facts = {
  F.FFITypeEq(F.CTypeId(2), int_t),
  F.FFISymbolResolved(F.CSymbolId(1), "addr:ffi_test_fn"),
  F.FFILayoutEq(F.CTypeId(12), "sha256:layout-foo"),
  F.FFICallbackLive(F.CCallbackId(1)),
}
for _, fact in ipairs(facts) do
  assert(F.Fact.members[pvm.classof(fact)])
end

-- Stencil has typed FFI patch-hole sources rather than stringly ffi_* selectors.
local ffi_symbol_hole = S.PatchHole(S.Name("ffi_symbol_addr"), S.FFISymbolAddr64Patch, 0, 8, S.Abs64, S.FromFFISymbol(fn_sym))
local ffi_field_hole = S.PatchHole(S.Name("ffi_field_offset"), S.FFIFieldOffsetPatch, 8, 4, S.I32, S.FromFFIFieldOffset(F.CTypeId(12), name("value")))
local ffi_size_hole = S.PatchHole(S.Name("ffi_sizeof"), S.FFISizeOfPatch, 12, 4, S.I32, S.FromFFITypeLayout(F.CTypeId(12)))
local ffi_align_hole = S.PatchHole(S.Name("ffi_alignof"), S.FFIAlignOfPatch, 16, 4, S.I32, S.FromFFITypeLayout(F.CTypeId(12)))
local ffi_callback_hole = S.PatchHole(S.Name("ffi_callback_thunk"), S.FFICallbackThunkPatch, 24, 8, S.Abs64, S.FromFFICallback(callback))
for _, hole in ipairs({ ffi_symbol_hole, ffi_field_hole, ffi_size_hole, ffi_align_hole, ffi_callback_hole }) do
  assert(pvm.classof(hole) == S.PatchHole)
  assert(S.PatchKind.members[pvm.classof(hole.kind)])
  assert(S.PatchSource.members[pvm.classof(hole.source)])
end

-- Invalid tests are only malformed metadata checks, not feature-completion claims.
local bad_layout = F.CRecordLayout(name("bad"), false, true, 4, -1, {}, "sha256:bad")
local ok, errors = Validate.record_layout(bad_layout)
assert_bad(ok, errors, "complete align_bytes must be > 0")

local bad_incomplete = F.CRecordLayout(name("incomplete"), false, false, 4, 4, { field_value }, "")
ok, errors = Validate.record_layout(bad_incomplete)
assert_bad(ok, errors, "incomplete layout cannot carry complete size/align/fields")

local bad_sym = F.CSymbol(F.CSymbolId(9), name("not_a_function"), libc, F.FunctionSymbol, int_t, F.SystemVAMD64, true, "addr:not_a_function")
ok, errors = Validate.symbol(bad_sym)
assert_bad(ok, errors, "FunctionType signature")

local bad_cdata = F.CData(opaque_t, F.InlineStorage("sha256:opaque", 8), no_finalizer, F.OwnedOwnership, F.CMetatypeId(0))
ok, errors = Validate.cdata(bad_cdata)
assert_bad(ok, errors, "complete ctype required")

local bad_callback = F.CCallback(F.CCallbackId(9), fn_t, F.SystemVAMD64, name("lua_callback_ref"), "", true)
ok, errors = Validate.callback(bad_callback)
assert_bad(ok, errors, "live callback requires thunk_key")

print("ok - SpongeJIT LuaCompile FFI semantic ASDL foundation")
