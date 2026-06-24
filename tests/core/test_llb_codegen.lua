package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local llb = require("llb")
local g = llb.grammar

local Mini = llb.define "CodegenMini" {
    g.role. items { kind = "array", item = "name" },
    g.role. fields { kind = "product" },
    g.role. variants { kind = "sum", payload_role = "fields" },
    g.head. decl {
        g.slot. name [g.name],
        g.slot. items [g.items],
        emit = function(n)
            return {
                tag = "decl",
                name = n.name.text,
                items = n.items,
            }
        end,
    },
    g.head. record {
        g.slot. name [g.name],
        g.slot. fields [g.fields],
        emit = function(n)
            return {
                tag = "record",
                name = n.name.text,
                fields = n.fields,
            }
        end,
    },
    g.head. union {
        g.slot. name [g.name],
        g.slot. variants [g.variants],
        emit = function(n)
            return {
                tag = "union",
                name = n.name.text,
                variants = n.variants,
            }
        end,
    },
}

assert(Mini.compiled ~= nil, "llb.define should compile a language runtime")
assert(Mini.compiled.roles.items ~= nil, "compiled runtime should include role normalizers")
assert(Mini.compiled.spreads.items ~= nil, "compiled runtime should include role spread expanders")

local session = llb.use(Mini, { scope = "env" })
local env = session.env
assert(rawget(env.decl, "backend") == "compiled", "language environment should install compiled head machines")
local out = env.decl. demo { "a", "b" }
assert(out.tag == "decl", "compiled role path should preserve head emission")
assert(out.name == "demo", "compiled role path should normalize name slots")
assert(#out.items == 2 and out.items[1].text == "a" and out.items[2].text == "b", "compiled array role should normalize item roles")

local fragment = llb.fragment("items", { llb.name("c"), llb.name("d") })
local spread_out = env.decl. spread_demo { llb._(fragment), llb._({ "e" }) }
assert(#spread_out.items == 3, "compiled spread expander should append fragment and table spreads")
assert(spread_out.items[1].text == "c" and spread_out.items[2].text == "d" and spread_out.items[3].text == "e", "compiled spread expander should preserve item order")

local T = llb.type("T")
local field_fragment = llb.fragment("fields", {
    { tag = "field", name = "x", type = T },
    { tag = "field", name = "y", type = T },
})
local product_out = env.record. Rec { llb._(field_fragment), llb._({ llb.symbol("z")[T] }) }
assert(#product_out.fields == 3, "compiled product role should expand product spreads")
assert(product_out.fields[1].name == "x" and product_out.fields[3].name == "z", "compiled product role should preserve spread field order")

local variant_fragment = llb.fragment("variants", {
    { tag = "variant", name = "Some", payload = nil },
})
local sum_out = env.union. Maybe { llb._(variant_fragment), llb.symbol("None") }
assert(#sum_out.variants == 2, "compiled sum role should expand variant spreads")
assert(sum_out.variants[1].name == "Some" and sum_out.variants[2].name == "None", "compiled sum role should preserve variant order")

local compiled_items = Mini.compiled.roles.items
assert(type(compiled_items.region) == "function", "compiled role should expose region form")
assert(type(compiled_items.collect) == "function", "compiled role should expose collect materializer")
local reflected = llb.normalize_role({ lang = Mini, reflective = true }, "items", { "x" })
local compiled = compiled_items({ lang = Mini }, { "x" })
assert(reflected[1].text == compiled[1].text, "compiled role output should match reflective output")

local regioned = {}
llb.gps.each(function(item) regioned[#regioned + 1] = item end, compiled_items.region({ lang = Mini }, { "s1", "s2" }))
assert(#regioned == 2 and regioned[1].text == "s1" and regioned[2].text == "s2", "compiled role region should emit normalized items")

local spread_regioned = {}
llb.gps.each(function(item) spread_regioned[#spread_regioned + 1] = item end, Mini.compiled.spreads.items.region({ lang = Mini }, llb._(fragment)))
assert(#spread_regioned == 2 and spread_regioned[1].text == "c" and spread_regioned[2].text == "d", "compiled spread region should emit fragment items")

local event_out = llb.collect_head_events(env.decl, {
    llb.event(llb.channel.index_name, llb.name("evented"), { action = "name", argc = 1 }),
    llb.event(llb.channel.call_table, { "q" }, { action = "call", argc = 1 }),
})
assert(event_out.tag == "decl" and event_out.name == "evented" and event_out.items[1].text == "q", "head event region should construct through the same role materializers")

local rendered_chunks = {}
llb.gps.each(function(chunk) rendered_chunks[#rendered_chunks + 1] = chunk end, llb.render_region(llb.doc.concat { "a", llb.doc.line(), "b" }, { width = 1 }))
assert(table.concat(rendered_chunks) == "a\nb", "render_region should emit render chunks")

local formatted_chunks = {}
llb.gps.each(function(chunk) formatted_chunks[#formatted_chunks + 1] = chunk end, llb.format_region(llb.name("fmt")))
assert(table.concat(formatted_chunks) == "fmt", "format_region should be the primary formatting region")

local ok = pcall(function()
    llb.normalize_role({ lang = Mini, reflective = true }, "items", 1)
end)
assert(ok == false, "reflective role fallback should still report bad input")

io.write("llb codegen ok\n")
