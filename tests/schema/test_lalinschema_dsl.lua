package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local S = require("lalin.schema.dsl")

local T = pvm.context()

local Demo = S.schema("LalinSchemaDslTest", {
    S.product("Name", {
        S.field("text", "string"),
    }, { S.unique }),

    S.alias("NameAlias", "LalinSchemaDslTest.Name"),

    S.product("Item", {
        S.field("name", "LalinSchemaDslTest.Name"),
        S.field("children", S.many(S.ref("LalinSchemaDslTest.Name"))),
        S.field("maybe_name", S.optional("LalinSchemaDslTest.Name")),
        S.field("stable_id", S.id("LalinSchemaDslTest.Name")),
        S.field("by_key", S.map("string", "LalinSchemaDslTest.Name")),
    }, { S.unique }),

    S.sum("Node", {
        S.variant("Leaf", {
            S.field("value", "string"),
        }, { S.variant_unique }),

        S.variant("Pair", {
            S.field("left", S.ref("LalinSchemaDslTest.Item")),
            S.field("right", S.ref("LalinSchemaDslTest.Item")),
        }, { S.variant_unique }),

        S.variant("Empty", {}),
    }),
})

S.define(T, { Demo })

local D = T.LalinSchemaDslTest

local x = D.Name("x")
local y = D.Name("y")
assert(x == D.Name("x"), "unique product should intern equal names")

local alias = D.NameAlias(x)
assert(alias.value == x, "alias should project to a unique value product")
assert(alias == D.NameAlias(x), "alias projection should be interned")

local item = D.Item(x, { y }, nil, x, { x, y })
assert(item.name == x, "plain field should preserve value")
assert(item.children[1] == y, "many/ref wrapper should project as a list of values")
assert(item.maybe_name == nil, "optional wrapper should accept nil")
assert(item.stable_id == x, "id wrapper should project as its payload value")
assert(item.by_key[1] == x and item.by_key[2] == y, "map wrapper should project as value records for runtime classes")
assert(item == D.Item(x, { y }, nil, x, { x, y }), "unique product with list fields should intern canonical lists")

local leaf = D.Leaf("ok")
assert(D.Node:isclassof(leaf), "sum parent should recognize variant instance")
assert(leaf.kind == "Leaf" and leaf.value == "ok", "variant fields should project")

local pair = D.Pair(item, item)
assert(D.Node:isclassof(pair), "sum parent should recognize non-leaf variant instance")
assert(pair.left == item and pair.right == item, "ref wrapper should project as payload value")

assert(D.Empty.kind == "Empty", "empty variant should project to singleton")
assert(D.Node:isclassof(D.Empty), "sum parent should recognize empty singleton variant")

local asdl_schema = S.to_asdl_schema(pvm.context(), { Demo })
assert(#asdl_schema.modules == 1, "LalinSchema should project to one LalinAsdl module")
assert(asdl_schema.modules[1].name == "LalinSchemaDslTest", "projected module name should match source")

io.write("lalin lalinschema dsl ok\n")
