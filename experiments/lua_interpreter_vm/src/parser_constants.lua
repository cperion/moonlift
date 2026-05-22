-- Lua Interpreter VM — Parser/compiler constants (first source→Proto slice)

local Tok = {}
Tok.EOF = 0
Tok.NAME = 1
Tok.INT = 2
Tok.FLOAT = 3
Tok.STRING = 4
Tok.PLUS = 5
Tok.ASSIGN = 6
Tok.LPAREN = 7
Tok.RPAREN = 8
Tok.SEMI = 9

local Kw = {}
Kw.LOCAL = 32
Kw.RETURN = 33
Kw.FUNCTION = 34
Kw.END = 35
Kw.IF = 36
Kw.THEN = 37
Kw.ELSE = 38
Kw.FOR = 39
Kw.DO = 40
Kw.WHILE = 41
Kw.TRUE = 42
Kw.FALSE = 43
Kw.NIL = 44

local ExpKind = {}
ExpKind.VNIL = 0
ExpKind.VTRUE = 1
ExpKind.VFALSE = 2
ExpKind.VKINT = 3
ExpKind.VKFLT = 4
ExpKind.VKSTR = 5
ExpKind.VLOCAL = 6
ExpKind.VNONRELOC = 7
ExpKind.VRELOC = 8
ExpKind.VCALL = 9
ExpKind.VVARARG = 10
ExpKind.VJMP = 11

local VarKind = {}
VarKind.REG = 0
VarKind.CONST = 1
VarKind.TBC = 2
VarKind.VARGTAB = 3

local ParseErr = {}
ParseErr.NONE = 0
ParseErr.UNEXPECTED_CHAR = 1
ParseErr.UNEXPECTED_TOKEN = 2
ParseErr.EXPECTED_NAME = 3
ParseErr.EXPECTED_EXPR = 4
ParseErr.EXPECTED_ASSIGN = 5
ParseErr.UNDECLARED_NAME = 6
ParseErr.TOO_MANY_REGS = 7
ParseErr.CODE_TOO_LARGE = 8
ParseErr.CONST_TOO_LARGE = 9

return {
    Tok = Tok,
    Kw = Kw,
    ExpKind = ExpKind,
    VarKind = VarKind,
    ParseErr = ParseErr,
}
