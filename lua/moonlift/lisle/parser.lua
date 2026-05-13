local Lex = require("moonlift.lisle.lexer")

local M = {}

local function sym(v) return { tag = "sym", value = v } end
local function str(v) return { tag = "str", value = v } end
local function num(v) return { tag = "num", value = v } end
local function bool(v) return { tag = "bool", value = v } end
local function nilv() return { tag = "nil" } end

local function as_atom(tok)
    if tok.kind == "string" then return str(tok.value) end
    if tok.kind ~= "atom" then error("lisle parser: expected atom") end
    local v = tok.value
    if v == "true" then return bool(true) end
    if v == "false" then return bool(false) end
    if v == "nil" then return nilv() end
    local n = tonumber(v)
    if n ~= nil then return num(n) end
    return sym(v)
end

function M.parse(src)
    local toks = Lex.lex(src)
    local i = 1

    local function tk() return toks[i] end
    local function bump() i = i + 1 end

    local function parse_node()
        local t = tk()
        if t.kind == "lparen" then
            bump()
            local xs = { tag = "list" }
            while tk().kind ~= "rparen" do
                if tk().kind == "eof" then error("lisle parser: unterminated list") end
                xs[#xs + 1] = parse_node()
            end
            bump() -- rparen
            return xs
        elseif t.kind == "rparen" then
            error("lisle parser: unexpected ')' ")
        elseif t.kind == "eof" then
            return nil
        else
            bump()
            return as_atom(t)
        end
    end

    local forms = {}
    while tk().kind ~= "eof" do
        forms[#forms + 1] = parse_node()
    end
    return forms
end

return M
