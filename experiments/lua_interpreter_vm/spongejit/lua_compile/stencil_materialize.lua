-- stencil_materialize.lua -- dumb copy-and-patch materializer for Stencil ASDL.
--
-- This module consumes Stencil.StencilTemplate metadata plus caller-supplied
-- concrete code bytes, copies the bytes into a materialized image, applies
-- typed patch sites and simple relocations, and returns Stencil.MaterializedImage.
-- It is intentionally VM/language agnostic: no Lua opcode names, protocol tags,
-- interpreter fallback, or semantic descriptor recovery.

local bit = require("bit")
local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local S = T.Stencil
local Validate = require("lua_compile.stencil_validate")

local M = {}

local TWO32 = 4294967296
local TWO31 = 2147483648
local TWO53 = 9007199254740992

local function cls(v) return pvm.classof(v) end
local function is(v, c) return cls(v) == c or v == c or (cls(v) and cls(c) and cls(v) == cls(c)) end
local function name_text(n)
  if type(n) == "table" and n.text ~= nil then return tostring(n.text) end
  return tostring(n or "")
end
local function add(errors, msg) errors[#errors + 1] = msg end

-- Pure LuaJIT SHA-256 for deterministic CodeBlobRef verification.
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function u32(n)
  n = tonumber(n) or 0
  if n < 0 then n = n + TWO32 end
  return n % TWO32
end

local function add32(...)
  local s = 0
  for i = 1, select('#', ...) do s = (s + u32(select(i, ...))) % TWO32 end
  return bit.tobit(s)
end

local function sha256_hex(msg)
  msg = tostring(msg or "")
  local bytes = {}
  for i = 1, #msg do bytes[i] = msg:byte(i) end
  local bit_len = #msg * 8
  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
  -- SpongeJIT test blobs are small; high 32 length bits are zero here.
  bytes[#bytes + 1] = 0
  bytes[#bytes + 1] = 0
  bytes[#bytes + 1] = 0
  bytes[#bytes + 1] = 0
  bytes[#bytes + 1] = bit.band(bit.rshift(bit_len, 24), 0xff)
  bytes[#bytes + 1] = bit.band(bit.rshift(bit_len, 16), 0xff)
  bytes[#bytes + 1] = bit.band(bit.rshift(bit_len, 8), 0xff)
  bytes[#bytes + 1] = bit.band(bit_len, 0xff)

  local h0,h1,h2,h3,h4,h5,h6,h7 = 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
  local w = {}
  for chunk = 1, #bytes, 64 do
    for i = 0, 15 do
      local j = chunk + i * 4
      w[i] = bit.tobit(bytes[j] * 0x1000000 + bytes[j + 1] * 0x10000 + bytes[j + 2] * 0x100 + bytes[j + 3])
    end
    for i = 16, 63 do
      local s0 = bit.bxor(bit.ror(w[i - 15], 7), bit.ror(w[i - 15], 18), bit.rshift(w[i - 15], 3))
      local s1 = bit.bxor(bit.ror(w[i - 2], 17), bit.ror(w[i - 2], 19), bit.rshift(w[i - 2], 10))
      w[i] = add32(w[i - 16], s0, w[i - 7], s1)
    end
    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7
    for i = 0, 63 do
      local S1 = bit.bxor(bit.ror(e, 6), bit.ror(e, 11), bit.ror(e, 25))
      local ch = bit.bxor(bit.band(e, f), bit.band(bit.bnot(e), g))
      local temp1 = add32(h, S1, ch, K[i + 1], w[i])
      local S0 = bit.bxor(bit.ror(a, 2), bit.ror(a, 13), bit.ror(a, 22))
      local maj = bit.bxor(bit.band(a, b), bit.band(a, c), bit.band(b, c))
      local temp2 = add32(S0, maj)
      h,g,f,e,d,c,b,a = g,f,e,add32(d, temp1),c,b,a,add32(temp1, temp2)
    end
    h0,h1,h2,h3 = add32(h0,a),add32(h1,b),add32(h2,c),add32(h3,d)
    h4,h5,h6,h7 = add32(h4,e),add32(h5,f),add32(h6,g),add32(h7,h)
  end
  local function hx(x) return string.format("%08x", u32(x)) end
  return table.concat{hx(h0),hx(h1),hx(h2),hx(h3),hx(h4),hx(h5),hx(h6),hx(h7)}
end
M.sha256_hex = sha256_hex

local function bytes_to_array(bytes)
  local out = {}
  for i = 1, #bytes do out[i] = bytes:byte(i) end
  return out
end

local function array_to_bytes(out)
  local chunks = {}
  for i = 1, #out, 4096 do
    local last = math.min(i + 4095, #out)
    chunks[#chunks + 1] = string.char(unpack(out, i, last))
  end
  return table.concat(chunks)
end

local function lookup_blob(code, blobs)
  if type(blobs) == "string" then return blobs end
  if type(blobs) ~= "table" then return nil end
  if type(blobs.bytes) == "string" then return blobs.bytes, blobs end
  local direct = blobs[code]
  if type(direct) == "string" then return direct end
  if type(direct) == "table" and type(direct.bytes) == "string" then return direct.bytes, direct end
  local keys = { name_text(code.symbol), tostring(code.content_hash or "") }
  for _, key in ipairs(keys) do
    local v = blobs[key]
    if type(v) == "string" then return v end
    if type(v) == "table" and type(v.bytes) == "string" then return v.bytes, v end
  end
  return nil
end

local function checked_code_bytes(code, blobs, errors)
  local bytes, meta = lookup_blob(code, blobs)
  if not bytes then add(errors, "missing code bytes for CodeBlobRef: " .. name_text(code and code.symbol)); return nil end
  if meta and meta.byte_size and tonumber(meta.byte_size) ~= #bytes then add(errors, "caller byte_size mismatch for CodeBlobRef: " .. name_text(code.symbol)) end
  if #bytes ~= tonumber(code.byte_size) then add(errors, "CodeBlobRef byte_size mismatch: expected " .. tostring(code.byte_size) .. ", got " .. tostring(#bytes)) end
  local want_hash = tostring(code.content_hash or "")
  local got_hash = "sha256:" .. sha256_hex(bytes)
  if meta and meta.content_hash and tostring(meta.content_hash) ~= got_hash then add(errors, "caller content_hash mismatch for CodeBlobRef: " .. name_text(code.symbol)) end
  if want_hash ~= got_hash then add(errors, "CodeBlobRef content_hash mismatch: expected " .. want_hash .. ", got " .. got_hash) end
  return bytes
end

local ENCODING = {}
local function enc_key(enc)
  if is(enc, S.TargetSpecific) then return "TargetSpecific" end
  local c = cls(enc)
  for _, name in ipairs({ "U8", "U16", "U32", "U64", "I32", "I64", "PcRel32", "PcRel64", "Abs64" }) do
    if c == S[name] then return name end
  end
  return tostring(enc and enc.kind or c)
end

ENCODING.U8 = { width = 1, signed = false }
ENCODING.U16 = { width = 2, signed = false }
ENCODING.U32 = { width = 4, signed = false }
ENCODING.U64 = { width = 8, signed = false }
ENCODING.I32 = { width = 4, signed = true }
ENCODING.I64 = { width = 8, signed = true }
ENCODING.PcRel32 = { width = 4, signed = true }
ENCODING.PcRel64 = { width = 8, signed = true }
ENCODING.Abs64 = { width = 8, signed = false }

local function checked_encoding(hole, errors)
  local key = enc_key(hole.encoding)
  local spec = ENCODING[key]
  if not spec then add(errors, "unsupported patch encoding: " .. key); return nil end
  if tonumber(hole.width_bytes) ~= spec.width then
    add(errors, "patch width/encoding mismatch for " .. name_text(hole.id) .. ": width " .. tostring(hole.width_bytes) .. " vs " .. key)
    return nil
  end
  return spec, key
end

local function parse_hex_words(s)
  s = tostring(s):lower():gsub("^0x", "")
  if not s:match("^[0-9a-f]+$") or #s > 16 then return nil, nil, "invalid u64 hex string: " .. tostring(s) end
  local lo_s = s:sub(math.max(1, #s - 7))
  local hi_s = #s > 8 and s:sub(1, #s - 8) or "0"
  return tonumber(hi_s, 16) or 0, tonumber(lo_s, 16) or 0
end

local function words_from_number(n, signed)
  if n < 0 then
    if not signed then return nil, nil, "negative value for unsigned patch: " .. tostring(n) end
    local abs = -n
    if abs > TWO53 then return nil, nil, "negative i64 magnitude too large to encode precisely: " .. tostring(n) end
    local lo = abs % TWO32
    local hi = math.floor(abs / TWO32)
    if lo == 0 then
      lo = 0
      hi = (TWO32 - hi) % TWO32
    else
      lo = TWO32 - lo
      hi = (TWO32 - hi - 1) % TWO32
    end
    return hi, lo
  end
  if n > TWO53 then return nil, nil, "u64 number too large to encode precisely: " .. tostring(n) end
  local hi = math.floor(n / TWO32)
  local lo = n - hi * TWO32
  return hi, lo
end

local function u64_words(value, signed)
  if type(value) == "string" then return parse_hex_words(value) end
  if type(value) ~= "number" then return nil, nil, "expected numeric patch value, got " .. type(value) end
  return words_from_number(value, signed)
end

local function low_number(hi, lo)
  if hi ~= 0 then return nil end
  return lo
end

local function pack_le(value, width, signed)
  if width == 8 then
    local hi, lo, err = u64_words(value, signed)
    if err then return nil, err end
    return string.char(
      bit.band(lo, 0xff), bit.band(bit.rshift(lo, 8), 0xff), bit.band(bit.rshift(lo, 16), 0xff), bit.band(bit.rshift(lo, 24), 0xff),
      bit.band(hi, 0xff), bit.band(bit.rshift(hi, 8), 0xff), bit.band(bit.rshift(hi, 16), 0xff), bit.band(bit.rshift(hi, 24), 0xff)
    )
  end
  local n = value
  if type(n) == "string" then
    local hi, lo, err = parse_hex_words(n)
    if err then return nil, err end
    n = low_number(hi, lo)
    if not n then return nil, "hex value too large for " .. tostring(width) .. "-byte patch" end
  end
  if type(n) ~= "number" then return nil, "expected numeric patch value" end
  local bits = width * 8
  if signed then
    local min, max = -2^(bits - 1), 2^(bits - 1) - 1
    if n < min or n > max then return nil, "signed patch overflow: " .. tostring(n) .. " for " .. tostring(bits) .. " bits" end
    if n < 0 then n = 2^bits + n end
  else
    local max = 2^bits - 1
    if n < 0 or n > max then return nil, "unsigned patch overflow: " .. tostring(n) .. " for " .. tostring(bits) .. " bits" end
  end
  local bytes = {}
  for i = 1, width do
    bytes[i] = n % 256
    n = math.floor(n / 256)
  end
  return string.char(unpack(bytes))
end

local function write_bytes(out, offset, data, errors, label)
  offset = tonumber(offset)
  if not offset or offset < 0 then add(errors, label .. " offset must be >= 0"); return false end
  if offset + #data > #out then add(errors, label .. " out of range at offset " .. tostring(offset)); return false end
  for i = 1, #data do out[offset + i] = data:byte(i) end
  return true
end

local function symbol_maps(template, opts)
  opts = opts or {}
  local offsets, addresses = {}, {}
  for _, sym in ipairs(template.local_symbols or {}) do
    if not is(sym.visibility, S.ExternalImported) then offsets[name_text(sym.name)] = tonumber(sym.offset) or 0 end
  end
  for k, v in pairs(opts.symbol_offsets or {}) do offsets[tostring(k)] = tonumber(v) end
  for k, v in pairs(opts.symbol_addresses or {}) do addresses[tostring(k)] = v end
  return offsets, addresses
end

local function resolve_symbol_value(sym, offsets, addresses, opts, for_reloc)
  local name = name_text(sym and sym.name)
  local base = tonumber((opts or {}).base_address or 0) or 0
  if addresses[name] ~= nil then return addresses[name] end
  if offsets[name] ~= nil then return base + offsets[name] end
  return nil, "unresolved symbol: " .. name
end

local function immediate_numeric(imm, offsets, addresses, opts)
  if is(imm, S.ImmI64) then return tonumber(imm.value) or 0 end
  if is(imm, S.ImmBool) then return imm.value and 1 or 0 end
  if is(imm, S.ImmSymbol) then return resolve_symbol_value(imm.symbol, offsets, addresses, opts) end
  return nil, "unsupported immediate operand for materialization: " .. tostring(imm and imm.kind)
end

local function normalize_external_value(v, hole, offsets, addresses, opts)
  if type(v) == "number" or type(v) == "string" then return v end
  if type(v) ~= "table" then return nil, "missing patch value for " .. name_text(hole.id) end
  if T.Stencil.PatchValue.members[cls(v)] then return v end
  if T.Stencil.ImmediateOperand.members[cls(v)] then return S.PatchImmediate(v) end
  if is(v, S.Symbol) then return S.PatchSymbol(v) end
  if v.value ~= nil then return v.value end
  return nil, "unsupported external patch value for " .. name_text(hole.id)
end

local patch_value_numeric

local function patch_source_value(source, hole, offsets, addresses, opts)
  if is(source, S.FromImmediate) then return immediate_numeric(source.imm, offsets, addresses, opts) end
  if is(source, S.FromSymbol) then return resolve_symbol_value(source.symbol, offsets, addresses, opts) end
  if is(source, S.FromMaterializationValue) then
    local key = name_text(source.name)
    local v = (opts.patch_values or {})[key]
    if v == nil then return nil, "missing materialization value: " .. key end
    local normalized, err = normalize_external_value(v, hole, offsets, addresses, opts)
    if err then return nil, err end
    if T.Stencil.PatchValue.members[cls(normalized)] then return patch_value_numeric(normalized, hole, offsets, addresses, opts) end
    return normalized
  end
  return nil, "unsupported PatchSource for materialization: " .. tostring(source and source.kind)
end

function patch_value_numeric(pv, hole, offsets, addresses, opts)
  if type(pv) == "number" or type(pv) == "string" then return pv end
  if is(pv, S.PatchImmediate) then return immediate_numeric(pv.imm, offsets, addresses, opts) end
  if is(pv, S.PatchSymbol) then return resolve_symbol_value(pv.symbol, offsets, addresses, opts) end
  if is(pv, S.PatchStack) then return tonumber(pv.stack.byte_offset) or 0 end
  if is(pv, S.PatchComputed) then
    local key = name_text(pv.name)
    local v = (opts.patch_values or {})[key] or (opts.patch_values or {})[name_text(hole.id)]
    if v == nil then return nil, "missing computed patch value: " .. key end
    local normalized, err = normalize_external_value(v, hole, offsets, addresses, opts)
    if err then return nil, err end
    return patch_value_numeric(normalized, hole, offsets, addresses, opts)
  end
  if pv == nil then return patch_source_value(hole.source, hole, offsets, addresses, opts) end
  return nil, "unsupported PatchValue for materialization: " .. tostring(pv and pv.kind)
end

local function collect_patch_sites(template, errors)
  local sites = {}
  for i, site in ipairs((template.plan and template.plan.patch_sites) or {}) do
    local id = name_text(site.hole and site.hole.id)
    if sites[id] then add(errors, "duplicate patch site for hole: " .. id) end
    sites[id] = site.value
  end
  return sites
end

local function value_display(v)
  if type(v) == "string" then return v end
  return tostring(v)
end

local function apply_patches(out, template, offsets, addresses, opts, errors, records)
  local sites = collect_patch_sites(template, errors)
  for _, hole in ipairs(template.holes or {}) do
    local spec, key = checked_encoding(hole, errors)
    if spec then
      local id = name_text(hole.id)
      local pv = sites[id]
      if pv == nil and (opts.patch_values or {})[id] ~= nil then pv = normalize_external_value((opts.patch_values or {})[id], hole, offsets, addresses, opts) end
      local value, verr = patch_value_numeric(pv, hole, offsets, addresses, opts)
      if verr then add(errors, verr) else
        local packed, perr = pack_le(value, spec.width, spec.signed)
        if perr then add(errors, id .. ": " .. perr)
        elseif write_bytes(out, hole.offset, packed, errors, "patch " .. id) then
          records[#records + 1] = S.AppliedPatch(hole.id, hole.offset, hole.width_bytes, hole.encoding, value_display(value))
        end
      end
    end
  end
end

local function add_numeric(value, addend)
  if type(value) == "number" then return value + (tonumber(addend) or 0) end
  if type(value) == "string" and (tonumber(addend) or 0) == 0 then return value end
  return nil, "cannot add reloc addend to nonnumeric symbol address: " .. tostring(value)
end

local function apply_relocs(out, template, offsets, addresses, opts, errors, records)
  local base = tonumber(opts.base_address or 0) or 0
  for _, reloc in ipairs(template.relocs or {}) do
    local id = name_text(reloc.id)
    local target, terr = resolve_symbol_value(reloc.target, offsets, addresses, opts, true)
    if terr then add(errors, terr) else
      if is(reloc.kind, S.AbsAddr) then
        local value, aerr = add_numeric(target, reloc.addend)
        if aerr then add(errors, id .. ": " .. aerr) else
          local packed, perr = pack_le(value, 8, false)
          if perr then add(errors, id .. ": " .. perr)
          elseif write_bytes(out, reloc.offset, packed, errors, "reloc " .. id) then
            records[#records + 1] = S.AppliedReloc(reloc.id, reloc.offset, reloc.kind, value_display(value))
          end
        end
      elseif is(reloc.kind, S.PcRel) then
        if type(target) ~= "number" then add(errors, id .. ": PcRel target must resolve to numeric address") else
          local value = target + (tonumber(reloc.addend) or 0) - (base + tonumber(reloc.offset) + 4)
          local packed, perr = pack_le(value, 4, true)
          if perr then add(errors, id .. ": " .. perr)
          elseif write_bytes(out, reloc.offset, packed, errors, "reloc " .. id) then
            records[#records + 1] = S.AppliedReloc(reloc.id, reloc.offset, reloc.kind, tostring(value))
          end
        end
      else
        add(errors, "unsupported relocation kind: " .. tostring(reloc.kind and reloc.kind.kind))
      end
    end
  end
end

function M.materialize(template, code_blobs, opts)
  opts = opts or {}
  local errors = {}
  local ok, verr = Validate.validate_template(template, opts.validate_opts or {})
  if not ok then for _, e in ipairs(verr) do add(errors, e) end; return nil, errors end

  local bytes = checked_code_bytes(template.code, code_blobs, errors)
  if #errors > 0 then return nil, errors end

  local out = bytes_to_array(bytes)
  local offsets, addresses = symbol_maps(template, opts)
  local records = {}
  apply_patches(out, template, offsets, addresses, opts, errors, records)
  apply_relocs(out, template, offsets, addresses, opts, errors, records)
  if #errors > 0 then return nil, errors end

  local entry_offset = offsets[name_text(template.plan.entry.symbol.name)]
  if entry_offset == nil then add(errors, "entry symbol does not resolve: " .. name_text(template.plan.entry.symbol.name)); return nil, errors end
  if entry_offset < 0 or entry_offset >= #out then add(errors, "entry offset out of range: " .. tostring(entry_offset)); return nil, errors end

  local image = S.MaterializedImage(template.name, template.code, array_to_bytes(out), template.plan.entry.symbol, entry_offset, records)
  local image_ok, image_errors = Validate.validate_materialized_image(image)
  if not image_ok then return nil, image_errors end
  return image, {}
end

function M.materialize_or_error(template, code_blobs, opts)
  local image, errors = M.materialize(template, code_blobs, opts)
  if not image then error(table.concat(errors, "\n"), 2) end
  return image
end

return M
