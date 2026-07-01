package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local InternSet = require("lalin.residual_mc_intern_set")(T)
local Residual = T.LalinResidual

local request = InternSet.request({ max_templates = 32 })
assert(asdl.isa(request, Residual.StencilTemplateBankRequest), "intern set request should be ASDL")

local g, p, s = request:template_entry_triplet()
local entry
s, entry = g(p, s)
assert(s ~= nil, "template entry stream should emit a first entry")
assert(asdl.isa(entry, Residual.StencilPatchTemplateEntry), "entry stream should yield typed template entries")
assert(asdl.isa(entry.selection, Residual.StencilPatchTemplateSelection), "entry should carry a typed template selection")
assert(asdl.classof(entry.selection) == Residual.StencilPatchTemplateSelected, "generated template entry should be selected")
assert(entry.selection.instance == entry.template_instance, "entry selection should refer to the representative template instance")
assert(entry.family == entry.selection.family, "entry family should come from the selection")
assert(type(entry.family:patch_template_key()) == "string", "template family should have a stable semantic key")

local seen = {}
local count = 0
while s ~= nil do
    local key = entry.family:patch_template_key()
    assert(not seen[key], "template stream should not duplicate family keys in its prefix: " .. key)
    seen[key] = true
    count = count + 1
    s, entry = g(p, s)
end
assert(count == 32, "max_templates should bound emitted template entries")

local batch_g, batch_p, batch_s = InternSet.request({ batch_size = 7, max_templates = 16 }):template_batch_triplet()
local batch
batch_s, batch = batch_g(batch_p, batch_s)
assert(batch_s ~= nil, "template batch stream should emit a batch")
assert(asdl.isa(batch, Residual.StencilPatchTemplateBatch), "template batch stream should yield typed ASDL batches")
assert(#batch.entries > 0 and #batch.entries <= 7, "template batch should respect requested batch size")

local bank = InternSet.request({ max_templates = 16 }):template_bank()
assert(asdl.isa(bank, Residual.StencilPatchTemplateBank), "template bank should be ASDL")
assert(bank.template_count == 16, "template bank count should match requested template bound")
assert(bank.estimated_template_bytes > 0, "template bank should carry estimated template bytes")

io.write("test_residual_mc_intern_set: ok\n")
