-- asdl.lua — compiler ASDL runtime
--
-- ── API ─────────────────────────────────────────────────────
--
--   asdl.context()              GC-backed ASDL type system
--   asdl.with(node, overrides)  structural update preserving sharing
--   asdl.T                      triplet algebra module
--
--   asdl.one(g, p, c)           terminal: consume exactly one element
--   asdl.drain(g, p, c)         canonical terminal: materialize → array
--   asdl.drain_into(g, p, c, out)  terminal optimization for append-only sinks

local Triplet = require("lalin.triplet")

local type = type
local getmetatable = getmetatable

local asdl = {}
asdl.NIL = {}
asdl.T = Triplet
local SCHEMA_CONTEXT = nil

local function get_schema_context()
	if SCHEMA_CONTEXT ~= nil then
		return SCHEMA_CONTEXT
	end
	SCHEMA_CONTEXT = require("lalin.schema_context")
	return SCHEMA_CONTEXT
end

function asdl.context(opts)
	return get_schema_context().NewContext(opts)
end

function asdl.classof(node)
	if type(node) ~= "table" then
		return false
	end
	local mt = getmetatable(node)
	return (mt and mt.__class) or false
end

local function class_from(value)
	return get_schema_context().Class(value)
end

function asdl.class_name(value)
	return get_schema_context().ClassName(value)
end

function asdl.class_basename(value)
	return get_schema_context().ClassBasename(value)
end

function asdl.context_of(value)
	return get_schema_context().ContextOf(value)
end

function asdl.fields(value)
	return get_schema_context().Fields(value)
end

function asdl.members(value)
	return get_schema_context().Members(value)
end

function asdl.is_sum_parent(value)
	return get_schema_context().IsSumParent(value)
end

function asdl.isa(node, class_or_singleton)
	local node_class = asdl.classof(node)
	if not node_class then return false end
	if node_class == class_or_singleton then return true end
	local target_class = class_from(class_or_singleton)
	if not target_class then return false end
	local members = asdl.members(target_class)
	return node_class == target_class or (members and members[node_class]) or false
end

function asdl.with(node, overrides)
	return get_schema_context().With(node, overrides, asdl.NIL)
end

function asdl.singleton(T, class)
	if type(T) ~= "table" or type(T.singleton) ~= "function" then
		error("asdl.singleton: expected ASDL context", 2)
	end
	return T:singleton(class)
end

local function seq_gen(t, i)
	i = i + 1
	if i > #t then
		return nil
	end
	return i, t[i]
end

local function seq_n_gen(s, i)
	i = i + 1
	if i > s.n then
		return nil
	end
	return i, s.array[i]
end

local function copy_seq_array(array, start_i, end_i)
	if start_i > end_i then
		return {}
	end
	local out, n = {}, 0
	for i = start_i, end_i do
		n = n + 1
		out[n] = array[i]
	end
	return out
end

local function append_seq_array(out, array, start_i, end_i)
	if start_i > end_i then
		return out
	end
	local n = #out
	for i = start_i, end_i do
		n = n + 1
		out[n] = array[i]
	end
	return out
end

local function drain_generic(g, p, c)
	local result, n = {}, 0
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		n = n + 1
		result[n] = val
	end
	return result
end

local function drain_generic_into(g, p, c, out)
	local n = #out
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		n = n + 1
		out[n] = val
	end
	return out
end

local function each_generic(g, p, c, fn)
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		fn(val)
	end
end

local function fold_generic(g, p, c, acc, fn)
	while true do
		local val
		c, val = g(p, c)
		if c == nil then
			break
		end
		acc = fn(acc, val)
	end
	return acc
end

-- ══════════════════════════════════════════════════════════════
--  DRAIN — force full materialization
--
--  Pulls all elements from a triplet into a flat array.
-- ══════════════════════════════════════════════════════════════

function asdl.drain(g, p, c)
	if g == nil then
		return {}
	end
	if g == seq_gen then
		return copy_seq_array(p, c + 1, #p)
	end
	if g == seq_n_gen then
		return copy_seq_array(p.array, c + 1, p.n)
	end
	return drain_generic(g, p, c)
end

-- Drain appending to an existing output array.
-- This is a sink optimization over the canonical triplet path,
-- not a separate flat execution architecture.

function asdl.drain_into(g, p, c, out)
	if g == nil then
		return out
	end
	if g == seq_gen then
		return append_seq_array(out, p, c + 1, #p)
	end
	if g == seq_n_gen then
		return append_seq_array(out, p.array, c + 1, p.n)
	end
	return drain_generic_into(g, p, c, out)
end

-- ══════════════════════════════════════════════════════════════
--  EACH — drain with per-element callback
--
--  For side-effectful consumption (rendering, audio output)
--  without materializing an array.
--
--    asdl.each(render(root), function(cmd)
--        execute_draw(cmd)
--    end)
--
-- ══════════════════════════════════════════════════════════════

function asdl.each(g, p, c, fn)
	if g == nil then
		return
	end
	if g == seq_gen then
		for i = c + 1, #p do
			fn(p[i])
		end
		return
	end
	if g == seq_n_gen then
		for i = c + 1, p.n do
			fn(p.array[i])
		end
		return
	end
	each_generic(g, p, c, fn)
end

-- ══════════════════════════════════════════════════════════════
--  FOLD — drain with accumulator
--
--  For reductions that don't need an intermediate array.
--
--    local total = asdl.fold(children(root), 0, function(acc, val)
--        return acc + val.size
--    end)
--
-- ══════════════════════════════════════════════════════════════

function asdl.fold(g, p, c, init, fn)
	if g == nil then
		return init
	end
	local acc = init
	if g == seq_gen then
		for i = c + 1, #p do
			acc = fn(acc, p[i])
		end
		return acc
	end
	if g == seq_n_gen then
		for i = c + 1, p.n do
			acc = fn(acc, p.array[i])
		end
		return acc
	end
	return fold_generic(g, p, c, acc, fn)
end

-- ══════════════════════════════════════════════════════════════
--  ONE — consume exactly one element from a triplet
--
--  Useful for scalar boundaries expressed as phases.
--  Errors if the stream is empty or has more than one element.
-- ══════════════════════════════════════════════════════════════

function asdl.one(g, p, c)
	if g == nil then
		error("asdl.one: expected exactly 1 element, got 0", 2)
	end
	if g == seq_gen then
		local i = c + 1
		local n = #p
		if i > n then
			error("asdl.one: expected exactly 1 element, got 0", 2)
		end
		if i < n then
			error("asdl.one: expected exactly 1 element, got more", 2)
		end
		return p[i]
	end
	if g == seq_n_gen then
		local i = c + 1
		local n = p.n
		if i > n then
			error("asdl.one: expected exactly 1 element, got 0", 2)
		end
		if i < n then
			error("asdl.one: expected exactly 1 element, got more", 2)
		end
		return p.array[i]
	end
	local c1, v1 = g(p, c)
	if c1 == nil then
		error("asdl.one: expected exactly 1 element, got 0", 2)
	end
	local c2 = g(p, c1)
	if c2 ~= nil then
		error("asdl.one: expected exactly 1 element, got more", 2)
	end
	return v1
end

function asdl.seq(array, n)
	n = n or #array
	if n >= #array then
		return seq_gen, array, 0
	end
	return seq_n_gen, { array = array, n = n }, 0
end

local function seq_rev_gen(a, i)
	i = i - 1
	if i < 1 then
		return nil
	end
	return i, a[i]
end

function asdl.seq_rev(array, n)
	n = n or #array
	if n > #array then
		n = #array
	end
	return seq_rev_gen, array, n + 1
end

-- ══════════════════════════════════════════════════════════════
--  ONCE — single-element triplet
--
--  The leaf case. When a handler produces one output element.
--
--    [Widget.Text] = function(node)
--        return asdl.once(DrawText(node.value))
--    end
--
-- ══════════════════════════════════════════════════════════════

local function once_gen(val, emitted)
	if emitted ~= 0 then
		return nil
	end
	return 1, val
end

function asdl.once(value)
	return once_gen, value, 0
end

-- ══════════════════════════════════════════════════════════════
--  EMPTY — zero-element triplet
-- ══════════════════════════════════════════════════════════════

local function empty_gen()
	return nil
end

function asdl.empty()
	return empty_gen, nil, nil
end

-- ══════════════════════════════════════════════════════════════
--  CONCAT — specialized small-arity concatenation
--
--  concat2/concat3 avoid the meta-iterator and packed-table
--  overhead of concat_all for the most common cases.
-- ══════════════════════════════════════════════════════════════

local function concat2_gen(s, phase)
	if phase == 1 then
		local nc, v = s[1](s[2], s[3])
		if nc ~= nil then
			s[3] = nc
			return 1, v
		end
		phase = 2
	end
	local nc, v = s[4](s[5], s[6])
	if nc == nil then
		return nil
	end
	s[6] = nc
	return 2, v
end

local function concat3_gen(s, phase)
	if phase == 1 then
		local nc, v = s[1](s[2], s[3])
		if nc ~= nil then
			s[3] = nc
			return 1, v
		end
		phase = 2
	end
	if phase == 2 then
		local nc, v = s[4](s[5], s[6])
		if nc ~= nil then
			s[6] = nc
			return 2, v
		end
		phase = 3
	end
	local nc, v = s[7](s[8], s[9])
	if nc == nil then
		return nil
	end
	s[9] = nc
	return 3, v
end

function asdl.concat2(g1, p1, c1, g2, p2, c2)
	return concat2_gen, { g1, p1, c1, g2, p2, c2 }, 1
end

function asdl.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
	return concat3_gen, { g1, p1, c1, g2, p2, c2, g3, p3, c3 }, 1
end

-- ══════════════════════════════════════════════════════════════
--  CONCAT_ALL — N-way triplet concatenation
--
--  Takes an array of packed triplets: { {g,p,c}, {g,p,c}, ... }
--  Returns a single concatenated triplet.
--
--  For large arity this stays inside asdl with one small state machine
--  instead of building a meta-iterator for Triplet.flatten().
-- ══════════════════════════════════════════════════════════════

local CONCAT_TRIPS = 1
local CONCAT_N = 2
local CONCAT_I = 3
local CONCAT_G = 4
local CONCAT_P = 5
local CONCAT_C = 6

local function concatn_gen(s, active)
	while true do
		local g = s[CONCAT_G]
		if g ~= nil then
			local c, v = g(s[CONCAT_P], s[CONCAT_C])
			if c ~= nil then
				s[CONCAT_C] = c
				return active, v
			end
			s[CONCAT_G] = nil
		end
		local i = s[CONCAT_I] + 1
		if i > s[CONCAT_N] then
			return nil
		end
		s[CONCAT_I] = i
		local trip = s[CONCAT_TRIPS][i]
		s[CONCAT_G] = trip[1]
		s[CONCAT_P] = trip[2]
		s[CONCAT_C] = trip[3]
	end
end

function asdl.concat_all(trips)
	local n = #trips
	if n == 0 then
		return asdl.empty()
	end
	if n == 1 then
		return trips[1][1], trips[1][2], trips[1][3]
	end
	if n == 2 then
		local t1, t2 = trips[1], trips[2]
		return asdl.concat2(t1[1], t1[2], t1[3], t2[1], t2[2], t2[3])
	end
	if n == 3 then
		local t1, t2, t3 = trips[1], trips[2], trips[3]
		return asdl.concat3(t1[1], t1[2], t1[3], t2[1], t2[2], t2[3], t3[1], t3[2], t3[3])
	end
	return concatn_gen, { trips, n, 0, nil, nil, nil }, true
end

-- ══════════════════════════════════════════════════════════════
--  CHILDREN — map a triplet-producing function over an array of child nodes
--
--  The most common handler pattern: lower each child,
--  concatenate results.
--
--    [Widget.Row] = function(node)
--        return asdl.children(lower, node.items)
--    end
--
--  This is pull-driven: if any child hits, its seq is instant.
--  If a child misses, its recording triplet fuses with the
--  parent's recording.
--
--  For large arrays, children stay lazy: asdl does not prebuild an
--  intermediate triplet array for every child before draining.
-- ══════════════════════════════════════════════════════════════

local CHILDREN_PHASE = 1
local CHILDREN_ARRAY = 2
local CHILDREN_N = 3
local CHILDREN_I = 4
local CHILDREN_G = 5
local CHILDREN_P = 6
local CHILDREN_C = 7

local function children_gen(s, active)
	while true do
			local g = s[CHILDREN_G]
			if g ~= nil then
				local c, v = g(s[CHILDREN_P], s[CHILDREN_C])
				if c ~= nil then
					s[CHILDREN_C] = c
				return active, v
			end
			s[CHILDREN_G] = nil
		end
		local i = s[CHILDREN_I] + 1
		if i > s[CHILDREN_N] then
			return nil
		end
		s[CHILDREN_I] = i
		local next_g, next_p, next_c = s[CHILDREN_PHASE](s[CHILDREN_ARRAY][i])
		if next_g ~= nil then
			s[CHILDREN_G] = next_g
			s[CHILDREN_P] = next_p
			s[CHILDREN_C] = next_c
		end
	end
end

function asdl.children(phase_fn, array, n)
	n = n or #array
	if n > #array then
		n = #array
	end
	if n == 0 then
		return asdl.empty()
	end
	if n == 1 then
		return phase_fn(array[1])
	end
	if n == 2 then
		local g1, p1, c1 = phase_fn(array[1])
		local g2, p2, c2 = phase_fn(array[2])
		return asdl.concat2(g1, p1, c1, g2, p2, c2)
	end
	if n == 3 then
		local g1, p1, c1 = phase_fn(array[1])
		local g2, p2, c2 = phase_fn(array[2])
		local g3, p3, c3 = phase_fn(array[3])
		return asdl.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
	end
	return children_gen, { phase_fn, array, n, 0, nil, nil, nil }, true
end

return asdl
