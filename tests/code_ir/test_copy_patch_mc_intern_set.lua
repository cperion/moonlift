package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Matrix = require("lalin.stencil_support_matrix")(T)
local InternSet = require("lalin.copy_patch_mc_intern_set")(T)
local Bank = require("lalin.copy_patch_mc")(T)

local function set(xs)
    local out = {}
    for _, x in ipairs(xs or {}) do out[x] = true end
    return out
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local cells = InternSet.cells()
assert(#cells > 0, "MC intern matrix must not be empty")

local covered_vocabs = {}
for _, cell in ipairs(cells) do
    assert(type(cell.name) == "string" and cell.name ~= "", "MC intern cell needs a stable name")
    local vocab = Matrix.vocabs[cell.vocab]
    assert(vocab ~= nil, "MC intern cell uses unknown vocab " .. tostring(cell.vocab))
    assert(vocab.status == Matrix.status.supported, "MC intern cell uses unsupported vocab " .. tostring(cell.vocab))
    local topology = Matrix.topologies[cell.topology]
    assert(topology ~= nil, "MC intern cell uses unknown topology " .. tostring(cell.topology))
    assert(topology.status == Matrix.status.supported, "MC intern cell uses unsupported topology " .. tostring(cell.topology))
    covered_vocabs[cell.vocab] = true
end

for vocab, entry in pairs(Matrix.vocabs) do
    if entry.status == Matrix.status.supported then
        assert(covered_vocabs[vocab], "supported vocab missing from MC intern matrix: " .. vocab)
    end
end

local artifacts = InternSet.artifacts()
assert(#artifacts == #cells, "MC intern matrix should build exactly one artifact per cell")

local expected_symbols = InternSet.expected_symbols()
assert(#expected_symbols == #cells, "MC intern matrix cells should produce unique symbols")

local bank, err, source = Bank.build_mc_bank(artifacts, {
    stem = "test_copy_patch_mc_intern_set",
    dir = "target/test_artifacts/test_copy_patch_mc_intern_set",
    preamble = InternSet.preamble(),
})
assert(bank ~= nil, tostring(err) .. "\n" .. tostring(source))

local expected = set(expected_symbols)
local actual = {}
for _, entry in ipairs(bank.entries or {}) do actual[entry.symbol] = true end

for _, symbol in ipairs(expected_symbols) do
    assert(actual[symbol], "MC bank missing intern matrix symbol " .. symbol)
end
for _, symbol in ipairs(sorted_keys(actual)) do
    assert(expected[symbol], "MC bank produced symbol outside intern matrix " .. symbol)
end

io.write("lalin copy_patch_mc intern set ok\n")
