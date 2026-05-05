-- lexgen.lua — Pure-Lua trie builder for MoonLift lexer generators.
--
-- Provides trie construction, name assignment, and traversal helpers.
-- The region...end factory functions stay in the .mlua file where
-- they're used, following the pattern from LANGUAGE_REFERENCE §21.3.
--
-- Usage in a .mlua file:
--   local lexgen = require("lib.lexgen")
--   local trie = lexgen.build_trie(tokens)
--   local names = lexgen.assign_names("Prefix", trie)
--   -- Then define your inline gen_node(trie, 0) factory

local M = {}

function M.build_trie(tokens)
    local trie = {children = {}, token = nil}
    for _, tok in ipairs(tokens) do
        local node = trie
        for i = 1, #tok.keyword do
            local b = string.byte(tok.keyword, i)
            node.children[b] = node.children[b] or {children = {}, token = nil}
            node = node.children[b]
        end
        node.token = tok
    end
    return trie
end

function M.assign_names(prefix, trie)
    local names, ctr = {}, 0
    local function walk(node, depth)
        if names[node] then return end
        ctr = ctr + 1
        names[node] = prefix .. "_d" .. depth .. "_n" .. ctr
        for _, child in pairs(node.children) do
            walk(child, depth + 1)
        end
    end
    walk(trie, 0)
    return names
end

-- Returns children as sorted array {{byte, child_node}, ...}
function M.sorted_children(node)
    local out = {}
    for byte, child in pairs(node.children) do
        out[#out + 1] = {byte = byte, node = child}
    end
    table.sort(out, function(a, b) return a.byte < b.byte end)
    return out
end

return M
