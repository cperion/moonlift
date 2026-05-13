local M = {}

local function is_space(c)
    return c == 32 or c == 9 or c == 10 or c == 13
end

local function is_delim(c)
    return c == 40 or c == 41 or c == 34 or c == 59 or is_space(c)
end

local function decode_string(src, i)
    local n = #src
    i = i + 1 -- skip opening quote
    local out = {}
    while i <= n do
        local c = string.byte(src, i)
        if c == 34 then
            return table.concat(out), i + 1
        elseif c == 92 then
            local nc = string.byte(src, i + 1)
            if nc == 110 then out[#out + 1] = "\n"
            elseif nc == 114 then out[#out + 1] = "\r"
            elseif nc == 116 then out[#out + 1] = "\t"
            elseif nc == 34 then out[#out + 1] = '"'
            elseif nc == 92 then out[#out + 1] = "\\"
            else
                out[#out + 1] = string.char(nc or 0)
            end
            i = i + 2
        else
            out[#out + 1] = string.char(c)
            i = i + 1
        end
    end
    error("lisle lexer: unterminated string")
end

function M.lex(src)
    local toks = {}
    local i, n = 1, #src

    while i <= n do
        local c = string.byte(src, i)

        if is_space(c) then
            i = i + 1

        elseif c == 59 then -- ';' comment to end-of-line
            while i <= n and string.byte(src, i) ~= 10 do i = i + 1 end

        elseif c == 40 then -- '('
            toks[#toks + 1] = { kind = "lparen" }
            i = i + 1

        elseif c == 41 then -- ')'
            toks[#toks + 1] = { kind = "rparen" }
            i = i + 1

        elseif c == 34 then -- string
            local s
            s, i = decode_string(src, i)
            toks[#toks + 1] = { kind = "string", value = s }

        else
            local s = i
            while i <= n do
                local cc = string.byte(src, i)
                if is_delim(cc) then break end
                i = i + 1
            end
            local atom = string.sub(src, s, i - 1)
            toks[#toks + 1] = { kind = "atom", value = atom }
        end
    end

    toks[#toks + 1] = { kind = "eof" }
    return toks
end

return M
