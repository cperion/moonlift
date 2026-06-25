#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local C = require("lua_compile")
local T = C.schema.get()
local S = T.Stencil
local Validate = require("lua_compile.stencil_validate")
local Key = require("lua_compile.stencil_key")
local Plan = require("lua_compile.stencil_materialization_plan")
local ObjectExtract = require("lua_compile.stencil_object_extract")
local Materialize = require("lua_compile.stencil_materialize")
local Bank = require("lua_compile.stencil_bank")
local Manifest = require("lua_compile.stencil_manifest")
local Bundle = require("lua_compile.stencil_bundle")

local function empty_contract()
  return T.CompileContract.Contract(T.CompileContract.Transfer({}, {}), {}, {}, {})
end

local contract = empty_contract()
local target = Plan.default_target_abi({ triple = "x86_64-unknown-linux-gnu", calling_convention = "lalin", pointer_width = "64", endian = "little" })
local features = Plan.default_feature_set({ arch = "x64", os = "linux", cpu_features = "baseline", codegen_version = "test-v1" })
local placement = Plan.empty_placement()
local variant = S.VariantKey(S.KernelStencil, T.LalinCFG.InlineSpan, contract, placement, target, features)
local entry = S.Symbol(S.Name("kernel_entry"), S.EntrySymbol, S.Local, 0)
local code = S.CodeBlobRef(S.Name("kernel_blob"), 16, "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
local hole = S.PatchHole(
  S.Name("imm_patch"),
  S.ImmediatePatch,
  4,
  8,
  S.I64,
  S.FromImmediate(S.ImmI64(0))
)
local plan = S.MaterializationPlan(
  { S.PatchSite(hole, S.PatchImmediate(S.ImmI64(42))) },
  {},
  S.EntryPoint(entry, target)
)
local template = S.StencilTemplate(S.Name("kernel_template"), S.KernelStencil, variant, code, { hole }, {}, { entry }, plan)
local module = S.StencilModule(
  S.BankIndex({ variant }, { S.TemplateIndexEntry(variant, S.Name("kernel_template")) }),
  { template },
  { entry },
  S.Linkage({ entry }, {}, {})
)

local ok, errors = Validate.validate_variant_key(variant)
assert(ok, table.concat(errors, "\n"))
ok, errors = Validate.validate_template(template)
assert(ok, table.concat(errors, "\n"))
ok, errors = Validate.validate_module(module)
assert(ok, table.concat(errors, "\n"))
assert(Key.variant_key(variant) == Key.variant_key(variant), "variant key must be deterministic")
assert(Key.variant_key(variant):find("Stencil.VariantKey", 1, true), "variant key must identify Stencil.VariantKey")

local extracted = ObjectExtract.template_from_metadata({
  name = "extracted_template",
  code = { symbol = "extracted_entry", byte_size = 24, content_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
  entry = "extracted_entry",
  symbols = { { name = "extracted_entry", kind = "EntrySymbol", visibility = "Local", offset = 0 } },
  holes = { { id = "const_patch", kind = "ImmediatePatch", offset = 8, width_bytes = 8, encoding = "I64", source = { kind = "FromImmediate", value = 0 } } },
  patch_values = { const_patch = S.PatchImmediate(S.ImmI64(7)) },
}, variant)
ok, errors = Validate.validate_template(extracted)
assert(ok, table.concat(errors, "\n"))

local function expect_invalid(label, node, validate_fn, want)
  local good, errs = validate_fn(node)
  assert(not good, label .. " unexpectedly validated")
  local text = table.concat(errs, "\n")
  assert(text:match(want), label .. " wrong error set: " .. text)
end

local bad_op_template = S.StencilTemplate(S.Name("OP_GETTABLE"), S.KernelStencil, variant, code, { hole }, {}, { entry }, plan)
expect_invalid("opcode-shaped template", bad_op_template, Validate.validate_template, "opcode")

local old_bank_name = "spon" .. "bank" .. "_selector"
local bad_symbol = S.Symbol(S.Name(old_bank_name), S.LocalLabel, S.Local, 0)
local bad_old_template = S.StencilTemplate(S.Name("kernel_template"), S.KernelStencil, variant, code, { hole }, {}, { bad_symbol }, S.MaterializationPlan({}, {}, S.EntryPoint(bad_symbol, target)))
expect_invalid("old backend symbol", bad_old_template, Validate.validate_template, "old backend")

local bad_out_hole = S.PatchHole(S.Name("out_tag"), S.ImmediatePatch, 0, 4, S.I32, S.FromMaterializationValue(S.Name("out_tag")))
local bad_out_template = S.StencilTemplate(S.Name("kernel_template"), S.KernelStencil, variant, code, { bad_out_hole }, {}, { entry }, S.MaterializationPlan({ S.PatchSite(bad_out_hole, S.PatchComputed(S.Name("out_tag"))) }, {}, S.EntryPoint(entry, target)))
expect_invalid("out tag hole", bad_out_template, Validate.validate_template, "out")

local zero_hole = S.PatchHole(S.Name("zero_width"), S.ImmediatePatch, 0, 0, S.I32, S.FromImmediate(S.ImmI64(0)))
local zero_template = S.StencilTemplate(S.Name("kernel_template"), S.KernelStencil, variant, code, { zero_hole }, {}, { entry }, S.MaterializationPlan({}, {}, S.EntryPoint(entry, target)))
expect_invalid("zero-width patch", zero_template, Validate.validate_template, "width")

local missing = S.Symbol(S.Name("missing_target"), S.ExternalTarget, S.ExternalImported, 0)
local bad_reloc = S.Reloc(S.Name("reloc_missing"), S.PcRel, 2, missing, 0)
local reloc_template = S.StencilTemplate(S.Name("kernel_template"), S.KernelStencil, variant, code, {}, { bad_reloc }, { entry }, S.MaterializationPlan({}, {}, S.EntryPoint(entry, target)))
expect_invalid("unresolved relocation", reloc_template, Validate.validate_template, "resolve")

local runtime_variant = S.VariantKey(S.RuntimeBoundaryStencil, T.LalinCFG.InlineSpan, contract, placement, target, features)
local runtime_template = S.StencilTemplate(S.Name("runtime_boundary"), S.RuntimeBoundaryStencil, runtime_variant, code, {}, {}, { entry }, S.MaterializationPlan({}, {}, S.EntryPoint(entry, target)))
expect_invalid("runtime boundary", runtime_template, Validate.validate_template, "RuntimeBoundaryStencil")

local allowed, allowed_errors = Validate.validate_template(runtime_template, { allow_runtime_boundary = true })
assert(allowed, table.concat(allowed_errors, "\n"))

local function zero_bytes(n) return string.rep(string.char(0), n) end
local function bhex(bytes)
  local out = {}
  for i = 1, #bytes do out[#out + 1] = string.format("%02x", bytes:byte(i)) end
  return table.concat(out)
end
local function code_ref(symbol, bytes)
  return S.CodeBlobRef(S.Name(symbol), #bytes, "sha256:" .. Materialize.sha256_hex(bytes))
end

local bank_bytes_a = string.char(1, 2, 3, 4, 5, 6, 7, 8)
local bank_bytes_b = string.char(9, 10, 11, 12, 13, 14, 15, 16)
local features_b = Plan.default_feature_set({ arch = "x64", os = "linux", cpu_features = "baseline", codegen_version = "test-v2" })
local variant_b = S.VariantKey(S.KernelStencil, T.LalinCFG.InlineSpan, contract, placement, target, features_b)
local features_c = Plan.default_feature_set({ arch = "x64", os = "linux", cpu_features = "baseline", codegen_version = "test-v3" })
local variant_c = S.VariantKey(S.KernelStencil, T.LalinCFG.InlineSpan, contract, placement, target, features_c)
local bank_entry_a = S.Symbol(S.Name("bank_entry_a"), S.EntrySymbol, S.Local, 0)
local bank_entry_b = S.Symbol(S.Name("bank_entry_b"), S.EntrySymbol, S.Local, 0)
local bank_template_a = S.StencilTemplate(
  S.Name("bank_template_a"),
  S.KernelStencil,
  variant,
  code_ref("bank_blob_a", bank_bytes_a),
  {}, {}, { bank_entry_a },
  S.MaterializationPlan({}, {}, S.EntryPoint(bank_entry_a, target))
)
local bank_template_b = S.StencilTemplate(
  S.Name("bank_template_b"),
  S.KernelStencil,
  variant_b,
  code_ref("bank_blob_b", bank_bytes_b),
  {}, {}, { bank_entry_b },
  S.MaterializationPlan({}, {}, S.EntryPoint(bank_entry_b, target))
)
local bank_module = S.StencilModule(
  S.BankIndex({ variant, variant_b }, {
    S.TemplateIndexEntry(variant, S.Name("bank_template_a")),
    S.TemplateIndexEntry(variant_b, S.Name("bank_template_b")),
  }),
  { bank_template_a, bank_template_b },
  { bank_entry_a, bank_entry_b },
  S.Linkage({ bank_entry_a, bank_entry_b }, {}, {})
)
local bank_index, bank_errors = Bank.build_index(bank_module)
assert(bank_index, table.concat(bank_errors or {}, "\n"))
assert(#bank_index.ordered_variant_keys == 2, "bank index should preserve deterministic ordered variant key list")
local selected_a = assert(Bank.select_template(bank_index, variant))
local selected_b = assert(Bank.select_template(bank_index, variant_b))
assert(selected_a == bank_template_a, "variant A must select template A")
assert(selected_b == bank_template_b, "variant B must select template B")
assert(Bank.select_template(bank_index, Key.variant_key(variant_b)) == bank_template_b, "string key lookup must select the same template")
assert(Bank.select_template(bank_module, variant_b) == bank_template_b, "module lookup must build a deterministic index")
assert(Bank.select_template(bank_index, variant_b) == Bank.select_template(bank_index, variant_b), "selection must be deterministic")
local bank_image, bank_mat_errors = Bank.materialize(bank_index, variant_b, { bank_blob_b = bank_bytes_b })
assert(bank_image, table.concat(bank_mat_errors or {}, "\n"))
assert(bank_image.template_name.text == "bank_template_b", "materialized image must come from selected template")
assert(bank_image.bytes == bank_bytes_b, "selected bank variant must materialize exact bytes for template B")
local bank_image2 = assert(Bank.materialize(bank_module, Key.variant_key(variant_b), { bank_blob_b = bank_bytes_b }))
assert(bank_image2.bytes == bank_image.bytes and bank_image2.template_name == bank_image.template_name, "bank materialization must be deterministic")

local function expect_bank_invalid(label, mod, want)
  local idx, errs = Bank.build_index(mod)
  assert(not idx, label .. " unexpectedly built a bank index")
  local text = table.concat(errs or {}, "\n")
  assert(text:match(want), label .. " wrong errors: " .. text)
end

expect_bank_invalid("duplicate variant keys", S.StencilModule(
  S.BankIndex({ variant, variant }, { S.TemplateIndexEntry(variant, S.Name("bank_template_a")) }),
  { bank_template_a }, { bank_entry_a }, S.Linkage({ bank_entry_a }, {}, {})
), "duplicate variant")

local dup_name_template = S.StencilTemplate(
  S.Name("bank_template_a"), S.KernelStencil, variant_b, code_ref("dup_name_blob", bank_bytes_b), {}, {}, { bank_entry_b },
  S.MaterializationPlan({}, {}, S.EntryPoint(bank_entry_b, target))
)
expect_bank_invalid("duplicate template names", S.StencilModule(
  S.BankIndex({ variant, variant_b }, {
    S.TemplateIndexEntry(variant, S.Name("bank_template_a")),
    S.TemplateIndexEntry(variant_b, S.Name("bank_template_a")),
  }),
  { bank_template_a, dup_name_template }, { bank_entry_a, bank_entry_b }, S.Linkage({ bank_entry_a, bank_entry_b }, {}, {})
), "duplicate template name")

expect_bank_invalid("unresolved template entry", S.StencilModule(
  S.BankIndex({ variant }, { S.TemplateIndexEntry(variant, S.Name("missing_template")) }),
  { bank_template_a }, { bank_entry_a }, S.Linkage({ bank_entry_a }, {}, {})
), "does not resolve")

expect_bank_invalid("mismatched template variant", S.StencilModule(
  S.BankIndex({ variant_b }, { S.TemplateIndexEntry(variant_b, S.Name("bank_template_a")) }),
  { bank_template_a }, { bank_entry_a }, S.Linkage({ bank_entry_a }, {}, {})
), "variant mismatch")

local missing_template, missing_errors = Bank.lookup(bank_index, variant_c)
assert(not missing_template, "missing variant lookup unexpectedly succeeded")
assert(table.concat(missing_errors or {}, "\n"):match("no template"), "missing variant error should be explicit")

local forbidden_template = S.StencilTemplate(
  S.Name("OP_BANK"), S.KernelStencil, variant_c, code_ref("forbidden_bank_blob", bank_bytes_a), {}, {}, { bank_entry_a },
  S.MaterializationPlan({}, {}, S.EntryPoint(bank_entry_a, target))
)
expect_bank_invalid("forbidden bank name", S.StencilModule(
  S.BankIndex({ variant_c }, { S.TemplateIndexEntry(variant_c, S.Name("OP_BANK")) }),
  { forbidden_template }, { bank_entry_a }, S.Linkage({ bank_entry_a }, {}, {})
), "opcode")

local function mat_template(args)
  args = args or {}
  local bytes = args.bytes or zero_bytes(40)
  local entry_sym = S.Symbol(S.Name("mat_entry"), S.EntrySymbol, S.Local, 0)
  local target_sym = args.target_sym or S.Symbol(S.Name("mat_target"), S.LocalLabel, S.Local, 3)
  local cref = args.code or code_ref(args.code_symbol or "mat_blob", bytes)
  return S.StencilTemplate(
    S.Name(args.name or "mat_template"),
    S.KernelStencil,
    variant,
    cref,
    args.holes or {},
    args.relocs or {},
    args.symbols or { entry_sym, target_sym },
    args.plan or S.MaterializationPlan(args.patch_sites or {}, {}, S.EntryPoint(entry_sym, target))
  ), bytes
end

local mat_bytes = zero_bytes(40)
local h_u8 = S.PatchHole(S.Name("u8_patch"), S.ImmediatePatch, 0, 1, S.U8, S.FromImmediate(S.ImmI64(0)))
local h_u16 = S.PatchHole(S.Name("u16_patch"), S.ImmediatePatch, 1, 2, S.U16, S.FromImmediate(S.ImmI64(0)))
local h_u32 = S.PatchHole(S.Name("u32_patch"), S.ImmediatePatch, 3, 4, S.U32, S.FromImmediate(S.ImmI64(0)))
local h_i32 = S.PatchHole(S.Name("i32_patch"), S.ImmediatePatch, 7, 4, S.I32, S.FromImmediate(S.ImmI64(0)))
local h_u64 = S.PatchHole(S.Name("u64_patch"), S.ImmediatePatch, 11, 8, S.U64, S.FromMaterializationValue(S.Name("u64_value")))
local h_i64 = S.PatchHole(S.Name("i64_patch"), S.ImmediatePatch, 19, 8, S.I64, S.FromImmediate(S.ImmI64(0)))
local entry_sym = S.Symbol(S.Name("mat_entry"), S.EntrySymbol, S.Local, 0)
local target_sym = S.Symbol(S.Name("mat_target"), S.LocalLabel, S.Local, 3)
local abs_reloc = S.Reloc(S.Name("abs_reloc"), S.AbsAddr, 27, target_sym, 0)
local pc_reloc = S.Reloc(S.Name("pc_reloc"), S.PcRel, 35, target_sym, 0)
local mat_plan = S.MaterializationPlan({
  S.PatchSite(h_u8, S.PatchImmediate(S.ImmI64(0xab))),
  S.PatchSite(h_u16, S.PatchImmediate(S.ImmI64(0x1234))),
  S.PatchSite(h_u32, S.PatchImmediate(S.ImmI64(0x11223344))),
  S.PatchSite(h_i32, S.PatchImmediate(S.ImmI64(-2))),
  S.PatchSite(h_u64, S.PatchComputed(S.Name("u64_value"))),
  S.PatchSite(h_i64, S.PatchImmediate(S.ImmI64(-1))),
}, {}, S.EntryPoint(entry_sym, target))
local mat = S.StencilTemplate(S.Name("materialized_template"), S.KernelStencil, variant, code_ref("mat_blob", mat_bytes), { h_u8, h_u16, h_u32, h_i32, h_u64, h_i64 }, { abs_reloc, pc_reloc }, { entry_sym, target_sym }, mat_plan)
local image, mat_errors = Materialize.materialize(mat, { mat_blob = mat_bytes }, { base_address = 0x1000, patch_values = { u64_value = "0x0102030405060708" } })
assert(image, table.concat(mat_errors or {}, "\n"))
assert(pvm.classof(image) == S.MaterializedImage)
local image_ok, image_errs = Validate.validate_materialized_image(image)
assert(image_ok, table.concat(image_errs, "\n"))
assert(image.entry_offset == 0)
local expected_hex = table.concat({
  "ab",          -- U8
  "3412",        -- U16
  "44332211",    -- U32
  "feffffff",    -- I32 -2
  "0807060504030201", -- U64
  "ffffffffffffffff", -- I64 -1
  "0310000000000000", -- AbsAddr(base + target offset)
  "dcffffff",    -- PcRel32 target 3 from site 35 + 4
  "00",          -- trailing copied byte remains unchanged
})
assert(bhex(image.bytes) == expected_hex, "materialized bytes mismatch: " .. bhex(image.bytes))
assert(#image.records == 8, "six patches plus two relocs should be recorded")

local symbol_hole = S.PatchHole(S.Name("symbol_patch"), S.SymbolAddressPatch, 0, 8, S.Abs64, S.FromSymbol(target_sym))
local symbol_template = S.StencilTemplate(S.Name("symbol_template"), S.KernelStencil, variant, code_ref("symbol_blob", zero_bytes(8)), { symbol_hole }, {}, { entry_sym, target_sym }, S.MaterializationPlan({ S.PatchSite(symbol_hole, S.PatchSymbol(target_sym)) }, {}, S.EntryPoint(entry_sym, target)))
local symbol_image = assert(Materialize.materialize(symbol_template, { symbol_blob = zero_bytes(8) }, { base_address = 0x2000 }))
assert(bhex(symbol_image.bytes) == "0320000000000000", "symbol Abs64 patch should use base + symbol offset")
local direct_blob_map = { [symbol_template.code] = zero_bytes(8) }
local direct_image = assert(Materialize.materialize(symbol_template, direct_blob_map, { base_address = 0x2000 }))
assert(direct_image.bytes == symbol_image.bytes, "CodeBlobRef-keyed byte input must materialize deterministically")
local hash_blob_map = { [symbol_template.code.content_hash] = zero_bytes(8) }
local hash_image = assert(Materialize.materialize(symbol_template, hash_blob_map, { base_address = 0x2000 }))
assert(hash_image.bytes == symbol_image.bytes, "content-hash-keyed byte input must materialize deterministically")

local function expect_materialize_invalid(label, tmpl, blobs, opts, want)
  local img, errs = Materialize.materialize(tmpl, blobs, opts or {})
  assert(not img, label .. " unexpectedly materialized")
  local text = table.concat(errs or {}, "\n")
  assert(text:match(want), label .. " wrong errors: " .. text)
end

expect_materialize_invalid("missing bytes", mat, {}, { patch_values = { u64_value = "0x1" } }, "missing code bytes")
expect_materialize_invalid("hash mismatch", mat, { mat_blob = zero_bytes(40):sub(1, 39) .. string.char(1) }, { patch_values = { u64_value = "0x1" } }, "content_hash mismatch")
expect_materialize_invalid("size mismatch", mat, { mat_blob = zero_bytes(39) }, { patch_values = { u64_value = "0x1" } }, "byte_size mismatch")
local out_hole = S.PatchHole(S.Name("range_patch"), S.ImmediatePatch, 39, 4, S.I32, S.FromImmediate(S.ImmI64(1)))
local out_template = S.StencilTemplate(S.Name("range_template"), S.KernelStencil, variant, code_ref("range_blob", zero_bytes(40)), { out_hole }, {}, { entry_sym }, S.MaterializationPlan({ S.PatchSite(out_hole, S.PatchImmediate(S.ImmI64(1))) }, {}, S.EntryPoint(entry_sym, target)))
expect_materialize_invalid("out-of-range patch", out_template, { range_blob = zero_bytes(40) }, {}, "out of range")
local target_hole = S.PatchHole(S.Name("target_patch"), S.ImmediatePatch, 0, 4, S.TargetSpecific("target32"), S.FromImmediate(S.ImmI64(1)))
local target_template = S.StencilTemplate(S.Name("target_template"), S.KernelStencil, variant, code_ref("target_blob", zero_bytes(8)), { target_hole }, {}, { entry_sym }, S.MaterializationPlan({ S.PatchSite(target_hole, S.PatchImmediate(S.ImmI64(1))) }, {}, S.EntryPoint(entry_sym, target)))
expect_materialize_invalid("unsupported encoding", target_template, { target_blob = zero_bytes(8) }, {}, "unsupported patch encoding")
local overflow_hole = S.PatchHole(S.Name("overflow_patch"), S.ImmediatePatch, 0, 1, S.U8, S.FromImmediate(S.ImmI64(300)))
local overflow_template = S.StencilTemplate(S.Name("overflow_template"), S.KernelStencil, variant, code_ref("overflow_blob", zero_bytes(8)), { overflow_hole }, {}, { entry_sym }, S.MaterializationPlan({ S.PatchSite(overflow_hole, S.PatchImmediate(S.ImmI64(300))) }, {}, S.EntryPoint(entry_sym, target)))
expect_materialize_invalid("overflow", overflow_template, { overflow_blob = zero_bytes(8) }, {}, "overflow")
local ext_sym = S.Symbol(S.Name("external_target"), S.ExternalTarget, S.ExternalImported, 0)
local ext_reloc = S.Reloc(S.Name("external_abs"), S.AbsAddr, 0, ext_sym, 0)
local ext_template = S.StencilTemplate(S.Name("external_template"), S.KernelStencil, variant, code_ref("external_blob", zero_bytes(8)), {}, { ext_reloc }, { entry_sym, ext_sym }, S.MaterializationPlan({}, {}, S.EntryPoint(entry_sym, target)))
expect_materialize_invalid("unresolved external symbol", ext_template, { external_blob = zero_bytes(8) }, {}, "unresolved symbol")
local bad_name_template = S.StencilTemplate(S.Name("OP_PATCH"), S.KernelStencil, variant, code_ref("bad_name_blob", zero_bytes(8)), {}, {}, { entry_sym }, S.MaterializationPlan({}, {}, S.EntryPoint(entry_sym, target)))
expect_materialize_invalid("semantic string leakage", bad_name_template, { bad_name_blob = zero_bytes(8) }, {}, "opcode")

local bundle_blobs = { bank_blob_a = bank_bytes_a, bank_blob_b = bank_bytes_b }
local bundle, bundle_meta = Bundle.materialize_all(bank_module, bundle_blobs)
assert(bundle, table.concat(bundle_meta or {}, "\n"))
assert(pvm.classof(bundle) == S.MaterializedBundle, "bundle must be ASDL Stencil.MaterializedBundle")
local bundle_ok, bundle_errs = Validate.validate_materialized_bundle(bundle)
assert(bundle_ok, table.concat(bundle_errs, "\n"))
assert(#bundle.images == 2 and #bundle.entries == 2, "materialize_all must materialize both bank templates")
assert(bundle.images[1].template_name.text == "bank_template_a", "bundle materialization order must be deterministic by variant key/template")
assert(bundle.images[2].template_name.text == "bank_template_b", "bundle materialization order must be deterministic by variant key/template")
assert(bundle.images[1].bytes == bank_bytes_a and bundle.images[2].bytes == bank_bytes_b, "bundle must contain exact copied images")
assert(bundle.entries[1].template_name == bundle.images[1].template_name, "publish metadata must identify image template")
assert(bundle.entries[1].entry.name.text == "bank_entry_a", "publish metadata must carry entry symbol")
assert(bundle.entries[1].entry_offset == 0, "publish metadata must carry entry offset")
assert(bundle.entries[1].entry_address_placeholder:match("^unpublished:"), "publish metadata must use explicit unpublished address placeholder")
assert(bundle.entries[1].image_size == #bank_bytes_a, "publish metadata must carry image size")
assert(bundle.entries[1].image_hash == "sha256:" .. Materialize.sha256_hex(bank_bytes_a), "publish metadata must carry image hash")
assert(bundle.entries[1].target_abi == variant.target_abi and bundle.entries[1].features == variant.features, "publish metadata must carry ABI/features")
local current_manifest = assert(Manifest.build(bank_module, bundle_blobs))
assert(bundle.manifest_digest == current_manifest.digest, "bundle must carry stable manifest digest")
assert(bundle.generation_id:find("bundle%-sha256:") == 1, "bundle must carry deterministic generation id")

local bundle_again = assert(Bundle.materialize_all(bank_module, bundle_blobs))
assert(bundle_again.generation_id == bundle.generation_id, "bundle generation id must be deterministic")
assert(bundle_again.manifest_digest == bundle.manifest_digest, "bundle manifest digest must be deterministic")
assert(bundle_again.images[1].template_name == bundle.images[1].template_name and bundle_again.images[2].template_name == bundle.images[2].template_name, "bundle image order must be deterministic")
assert(bundle_again.entries[1].image_hash == bundle.entries[1].image_hash and bundle_again.entries[2].image_hash == bundle.entries[2].image_hash, "publish metadata must be deterministic")

local selected_bundle = assert(Bundle.materialize_selected_variants(bank_module, bundle_blobs, { variant_b }))
assert(#selected_bundle.images == 1, "selected bundle must materialize only requested variants")
assert(selected_bundle.images[1].template_name.text == "bank_template_b", "selected variant must materialize matching template")
local selected_by_string = assert(Bundle.materialize_selected_variants(bank_module, bundle_blobs, { Key.variant_key(variant_b) }))
assert(selected_by_string.images[1].template_name == selected_bundle.images[1].template_name, "selected string key must match variant object")
local selected_reversed = assert(Bundle.materialize_selected_variants(bank_module, bundle_blobs, { variant_b, variant }))
assert(selected_reversed.images[1].template_name.text == "bank_template_a" and selected_reversed.images[2].template_name.text == "bank_template_b", "selected variants must be sorted deterministically by variant key")

local function expect_bundle_invalid(label, mod, blobs, opts, want, selected)
  local b, errs
  if selected then b, errs = Bundle.materialize_selected_variants(mod, blobs, selected, opts or {})
  else b, errs = Bundle.materialize_all(mod, blobs, opts or {}) end
  assert(not b, label .. " unexpectedly built a materialized bundle")
  local text = table.concat(errs or {}, "\n")
  assert(text:match(want), label .. " wrong errors: " .. text)
end

expect_bundle_invalid("bundle duplicate bank entry", S.StencilModule(
  S.BankIndex({ variant, variant_b }, {
    S.TemplateIndexEntry(variant, S.Name("bank_template_a")),
    S.TemplateIndexEntry(variant, S.Name("bank_template_a")),
    S.TemplateIndexEntry(variant_b, S.Name("bank_template_b")),
  }),
  { bank_template_a, bank_template_b }, { bank_entry_a, bank_entry_b }, S.Linkage({ bank_entry_a, bank_entry_b }, {}, {})
), bundle_blobs, {}, "duplicate")
expect_bundle_invalid("bundle missing bytes", bank_module, { bank_blob_a = bank_bytes_a }, {}, "missing code")
local stale_manifest = assert(Manifest.build(bank_module, bundle_blobs))
stale_manifest.digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
expect_bundle_invalid("bundle manifest mismatch", bank_module, bundle_blobs, { manifest = stale_manifest }, "manifest")
expect_bundle_invalid("bundle digest mismatch", bank_module, bundle_blobs, { manifest_digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111" }, "manifest digest mismatch")
expect_bundle_invalid("bundle forbidden runtime boundary", S.StencilModule(
  S.BankIndex({ runtime_variant }, { S.TemplateIndexEntry(runtime_variant, S.Name("runtime_boundary")) }),
  { runtime_template }, { entry }, S.Linkage({ entry }, {}, {})
), { kernel_blob = string.rep("\0", 16) }, {}, "RuntimeBoundaryStencil")
expect_bundle_invalid("bundle forbidden opcode string", S.StencilModule(
  S.BankIndex({ variant_c }, { S.TemplateIndexEntry(variant_c, S.Name("OP_BANK")) }),
  { forbidden_template }, { bank_entry_a }, S.Linkage({ bank_entry_a }, {}, {})
), { forbidden_bank_blob = bank_bytes_a }, {}, "opcode")
expect_bundle_invalid("bundle duplicate selected variant", bank_module, bundle_blobs, {}, "duplicate selected", { variant_b, Key.variant_key(variant_b) })

assert(pvm.classof(template) == S.StencilTemplate)
print("ok - SpongeJIT LuaCompile stencil artifacts")
