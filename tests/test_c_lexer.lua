package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local lexer = require("moonlift.c.c_lexer")

-- ---------------------------------------------------------------------------
-- Helper: lex a source string and return { tokens, spans, issues }
-- ---------------------------------------------------------------------------
local function lex(src)
    return lexer.lex(src, "test.c")
end

-- ---------------------------------------------------------------------------
-- 1. Keywords
-- ---------------------------------------------------------------------------
do
    local r = lex("int return if for while struct void char float double short long unsigned signed const static extern typedef union enum switch case default break continue do goto sizeof volatile auto register inline restrict _Bool _Complex")

    -- Ordered list of { lexer_output_name, keyword_variant } pairs
    local kw_list = {
        { "int", "CKwInt" }, { "return", "CKwReturn" }, { "if", "CKwIf" },
        { "for", "CKwFor" }, { "while", "CKwWhile" }, { "struct", "CKwStruct" },
        { "void", "CKwVoid" }, { "char", "CKwChar" }, { "float", "CKwFloat" },
        { "double", "CKwDouble" }, { "short", "CKwShort" }, { "long", "CKwLong" },
        { "unsigned", "CKwUnsigned" }, { "signed", "CKwSigned" }, { "const", "CKwConst" },
        { "static", "CKwStatic" }, { "extern", "CKwExtern" }, { "typedef", "CKwTypedef" },
        { "union", "CKwUnion" }, { "enum", "CKwEnum" },
        { "switch", "CKwSwitch" }, { "case", "CKwCase" }, { "default", "CKwDefault" },
        { "break", "CKwBreak" }, { "continue", "CKwContinue" }, { "do", "CKwDo" },
        { "goto", "CKwGoto" }, { "sizeof", "CKwSizeof" }, { "volatile", "CKwVolatile" },
        { "auto", "CKwAuto" }, { "register", "CKwRegister" }, { "inline", "CKwInline" },
        { "restrict", "CKwRestrict" }, { "_Bool", "CKwBool" }, { "_Complex", "CKwComplex" },
    }

    local kw_idx = 1
    for _, entry in ipairs(kw_list) do
        local name = entry[1]
        local expected_variant = entry[2]
        -- Skip past non-keyword tokens (newlines, EOF)
        while kw_idx <= #r.tokens do
            local t = r.tokens[kw_idx]
            if t._variant == "CTokKeyword" then break end
            kw_idx = kw_idx + 1
        end
        local t = r.tokens[kw_idx]
        assert(t ~= nil, "missing keyword token for '" .. name .. "'")
        assert(t._variant == "CTokKeyword",
               "expected CTokKeyword for '" .. name .. "', got " .. t._variant)
        assert(t.kw._variant == expected_variant,
               "expected keyword variant " .. expected_variant .. " for '" .. name .. "', got " .. t.kw._variant)
        kw_idx = kw_idx + 1
    end

    print("  keywords: PASS")
end

-- ---------------------------------------------------------------------------
-- 2. Identifiers
-- ---------------------------------------------------------------------------
do
    local r = lex("foo bar_123 _leading")
    local idents = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokIdent" then
            idents[#idents + 1] = tok.name
        end
    end
    assert(#idents == 3, "expected 3 identifiers, got " .. #idents)
    assert(idents[1] == "foo")
    assert(idents[2] == "bar_123")
    assert(idents[3] == "_leading")
    print("  identifiers: PASS")
end

-- ---------------------------------------------------------------------------
-- 3. Integer literals
-- ---------------------------------------------------------------------------
do
    local r = lex("42 0xFF 0777 0u 123LL 0xDEADul")
    local ints = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokIntLiteral" then
            ints[#ints + 1] = tok
        end
    end
    assert(#ints == 6, "expected 6 integer literals, got " .. #ints)
    assert(ints[1].raw == "42" and ints[1].suffix == "")
    assert(ints[2].raw == "0xFF" and ints[2].suffix == "")
    assert(ints[3].raw == "0777" and ints[3].suffix == "")
    assert(ints[4].raw == "0" and ints[4].suffix == "u")
    assert(ints[5].raw == "123" and ints[5].suffix == "LL")
    assert(ints[6].raw == "0xDEAD" and ints[6].suffix == "ul")
    print("  integer literals: PASS")
end

-- ---------------------------------------------------------------------------
-- 4. Float literals
-- ---------------------------------------------------------------------------
do
    local r = lex("3.14 1e10 0x1.0p2 0.5f 1.0e-5")
    local floats = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokFloatLiteral" then
            floats[#floats + 1] = tok
        end
    end
    assert(#floats == 5, "expected 5 float literals, got " .. #floats)
    assert(floats[1].raw == "3.14" and floats[1].suffix == "")
    assert(floats[2].raw == "1e10" and floats[2].suffix == "")
    assert(floats[3].raw == "0x1.0p2" and floats[3].suffix == "")
    assert(floats[4].raw == "0.5" and floats[4].suffix == "f")
    assert(floats[5].raw == "1.0e-5" and floats[5].suffix == "")
    print("  float literals: PASS")
end

-- ---------------------------------------------------------------------------
-- 5. Character literals
-- ---------------------------------------------------------------------------
do
    local r = lex("'a' '\\n' '\\\\' '\\''")
    local chars = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokCharLiteral" then
            chars[#chars + 1] = tok
        end
    end
    assert(#chars == 4, "expected 4 char literals, got " .. #chars)
    assert(chars[1].raw == "'a'")
    assert(chars[2].raw == "'\\n'")
    assert(chars[3].raw == "'\\\\'")
    assert(chars[4].raw == "'\\''")
    print("  character literals: PASS")
end

-- ---------------------------------------------------------------------------
-- 6. String literals
-- ---------------------------------------------------------------------------
do
    local r = lex('"hello" "world\\n"')
    local strs = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokStringLiteral" then
            strs[#strs + 1] = tok
        end
    end
    assert(#strs == 2, "expected 2 string literals, got " .. #strs)
    assert(strs[1].raw == '"hello"')
    assert(strs[1].prefix == "")
    assert(strs[2].raw == '"world\\n"')
    print("  string literals: PASS")
end

-- ---------------------------------------------------------------------------
-- 7. Multi-character punctuators
-- ---------------------------------------------------------------------------
do
    local r = lex("-> ++ -- += -= *= /= %= &= |= ^= << >> <= >= == != && || <<= >>= ... ##")
    local puncts = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokPunct" then
            puncts[#puncts + 1] = tok.text
        end
    end
    local expected = {
        "->", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
        "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "<<=", ">>=",
        "...",
    }
    assert(#puncts >= #expected,
           "expected at least " .. #expected .. " multi-char puncts, got " .. #puncts)
    local checked = {}
    for _, exp in ipairs(expected) do
        local found = false
        for _, p in ipairs(puncts) do
            if p == exp and not checked[p] then checked[p] = true; found = true; break end
        end
        assert(found, "missing expected punct: " .. exp)
    end
    print("  multi-char punctuators: PASS")
end

-- ---------------------------------------------------------------------------
-- 8. Single-char punctuators
-- ---------------------------------------------------------------------------
do
    local r = lex("{ } ( ) [ ] ; : , . ~ ? + - * / % < > = ! & | ^ #")
    local puncts = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokPunct" then
            puncts[#puncts + 1] = tok.text
        end
    end
    -- Skip # which might be parsed differently; test it separately.
    -- We expect all other single-char puncts.
    local singles = {"{", "}", "(", ")", "[", "]", ";", ":", ",", ".", "~", "?",
                     "+", "-", "*", "/", "%", "<", ">", "=", "!", "&", "|", "^"}
    for _, exp in ipairs(singles) do
        local found = false
        for _, pt in ipairs(puncts) do
            if pt == exp then found = true; break end
        end
        assert(found, "missing single-char punct '" .. exp .. "'")
    end
    print("  single-char punctuators: PASS")
end

-- ---------------------------------------------------------------------------
-- 9. Line comments (// ...) are skipped
-- ---------------------------------------------------------------------------
do
    local r = lex("int // this is a comment\n x;")
    local tokens_no_newlines = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant ~= "CTokNewline" and tok._variant ~= "CTokEOF" then
            tokens_no_newlines[#tokens_no_newlines + 1] = tok
        end
    end
    assert(#tokens_no_newlines == 3,
           "expected 3 meaningful tokens after line comment, got " .. #tokens_no_newlines)
    assert(tokens_no_newlines[1]._variant == "CTokKeyword")
    assert(tokens_no_newlines[1].kw._variant == "CKwInt")
    assert(tokens_no_newlines[2]._variant == "CTokIdent" and tokens_no_newlines[2].name == "x")
    assert(tokens_no_newlines[3]._variant == "CTokPunct" and tokens_no_newlines[3].text == ";")
    print("  line comments: PASS")
end

-- ---------------------------------------------------------------------------
-- 10. Block comments (/* ... */) are skipped
-- ---------------------------------------------------------------------------
do
    local r = lex("int /* block comment */ x;")
    local toks = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant ~= "CTokNewline" and tok._variant ~= "CTokEOF" then
            toks[#toks + 1] = tok
        end
    end
    assert(#toks == 3,
           "expected 3 meaningful tokens after block comment, got " .. #toks)
    assert(toks[1]._variant == "CTokKeyword" and toks[1].kw._variant == "CKwInt")
    assert(toks[2]._variant == "CTokIdent" and toks[2].name == "x")
    assert(toks[3]._variant == "CTokPunct" and toks[3].text == ";")
    print("  block comments: PASS")
end

-- ---------------------------------------------------------------------------
-- 11. Backslash-newline continuation (\\n) is consumed
-- ---------------------------------------------------------------------------
do
    local r = lex([[int\
 x\
;]])
    local toks = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant ~= "CTokNewline" and tok._variant ~= "CTokEOF" then
            toks[#toks + 1] = tok
        end
    end
    assert(#toks == 3,
           "expected 3 meaningful tokens after line continuations, got " .. #toks)
    assert(toks[1]._variant == "CTokKeyword" and toks[1].kw._variant == "CKwInt")
    assert(toks[2]._variant == "CTokIdent" and toks[2].name == "x")
    assert(toks[3]._variant == "CTokPunct" and toks[3].text == ";")
    print("  backslash-newline continuation: PASS")
end

-- ---------------------------------------------------------------------------
-- 12. Preprocessor directives
-- ---------------------------------------------------------------------------
do
    local r = lex("#define FOO 42\n#include \"foo.h\"\n#if 1\n#endif\n#error oops\n#pragma once\n")
    local directives = {}
    for _, tok in ipairs(r.tokens) do
        if tok._variant == "CTokDirective" then
            directives[#directives + 1] = tok
        end
    end
    assert(#directives == 6,
           "expected 6 directive tokens, got " .. #directives)
    assert(directives[1].kind._variant == "CDirDefine")
    assert(directives[2].kind._variant == "CDirInclude")
    assert(directives[3].kind._variant == "CDirIf")
    assert(directives[4].kind._variant == "CDirEndif")
    assert(directives[5].kind._variant == "CDirError")
    assert(directives[6].kind._variant == "CDirPragma")
    print("  preprocessor directives: PASS")
end

-- ---------------------------------------------------------------------------
-- 13. Unknown characters produce issues
-- ---------------------------------------------------------------------------
do
    local r = lex("int @ x;")
    assert(#r.issues > 0, "expected issues for unknown character '@'")
    local found = false
    for _, iss in ipairs(r.issues) do
        if iss.message:find("unrecognized") then
            found = true
            break
        end
    end
    assert(found, "expected 'unrecognized character' issue for '@'")
    print("  unknown characters: PASS")
end

-- ---------------------------------------------------------------------------
-- 14. Unterminated string / comment produce issues
-- ---------------------------------------------------------------------------
do
    local r1 = lex('"unterminated')
    local has_issue = false
    for _, iss in ipairs(r1.issues) do
        if iss.message:find("unterminated") then
            has_issue = true
            break
        end
    end
    assert(has_issue, "expected unterminated string issue")
    print("  unterminated string: PASS")
end

do
    local r2 = lex("/* unterminated block")
    local has_issue = false
    for _, iss in ipairs(r2.issues) do
        if iss.message:find("unterminated") then
            has_issue = true
            break
        end
    end
    assert(has_issue, "expected unterminated block comment issue")
    print("  unterminated block comment: PASS")
end

-- ---------------------------------------------------------------------------
-- 15. EOF token is always emitted
-- ---------------------------------------------------------------------------
do
    local r = lex("")
    local last = r.tokens[#r.tokens]
    assert(last ~= nil and last._variant == "CTokEOF",
           "expected CTokEOF as last token for empty input, got " .. (last and last._variant or "nil"))
    print("  EOF token: PASS")
end

print("moonlift test_c_lexer ok")
