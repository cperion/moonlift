-- MoonCAst schema: C Abstract Syntax Tree types
-- Defined per C_FRONTEND_DESIGN.md §4-6

return function(A)
    return A.module "MoonCAst" {
        ------------------------------------------------------------------
        -- Tokens (§4)
        ------------------------------------------------------------------

        A.sum "CKeyword" {
            A.variant "CKwAuto",       A.variant "CKwBreak",     A.variant "CKwCase",
            A.variant "CKwChar",       A.variant "CKwConst",     A.variant "CKwContinue",
            A.variant "CKwDefault",    A.variant "CKwDo",        A.variant "CKwDouble",
            A.variant "CKwElse",       A.variant "CKwEnum",      A.variant "CKwExtern",
            A.variant "CKwFloat",      A.variant "CKwFor",       A.variant "CKwGoto",
            A.variant "CKwIf",         A.variant "CKwInline",    A.variant "CKwInt",
            A.variant "CKwLong",       A.variant "CKwRegister",  A.variant "CKwRestrict",
            A.variant "CKwReturn",     A.variant "CKwShort",     A.variant "CKwSigned",
            A.variant "CKwSizeof",     A.variant "CKwStatic",    A.variant "CKwStruct",
            A.variant "CKwSwitch",     A.variant "CKwTypedef",   A.variant "CKwUnion",
            A.variant "CKwUnsigned",   A.variant "CKwVoid",      A.variant "CKwVolatile",
            A.variant "CKwWhile",
            A.variant "CKwBool",         -- _Bool (C99)
            A.variant "CKwComplex",      -- _Complex (C99, recognized but rejected)
            A.variant "CKwInline2",      -- __inline (alternate spelling)
            A.variant "CKwRestrict2",    -- __restrict (alternate spelling)
        },

        A.sum "CDirectiveKind" {
            A.variant "CDirDefine",    A.variant "CDirUndef",
            A.variant "CDirInclude",   A.variant "CDirIf",
            A.variant "CDirIfdef",     A.variant "CDirIfndef",
            A.variant "CDirElif",      A.variant "CDirElse",
            A.variant "CDirEndif",     A.variant "CDirError",
            A.variant "CDirPragma",    A.variant "CDirLine",
        },

        A.sum "CToken" {
            A.variant "CTokIdent" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "CTokKeyword" {
                A.field "kw" "MoonCAst.CKeyword",
                A.variant_unique,
            },
            A.variant "CTokIntLiteral" {
                A.field "raw" "string",
                A.field "suffix" "string",
                A.variant_unique,
            },
            A.variant "CTokFloatLiteral" {
                A.field "raw" "string",
                A.field "suffix" "string",
                A.variant_unique,
            },
            A.variant "CTokCharLiteral" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "CTokStringLiteral" {
                A.field "raw" "string",
                A.field "prefix" "string",
                A.variant_unique,
            },
            A.variant "CTokPunct" {
                A.field "text" "string",
                A.variant_unique,
            },
            A.variant "CTokDirective" {
                A.field "kind" "MoonCAst.CDirectiveKind",
                A.variant_unique,
            },
            A.variant "CTokNewline",
            A.variant "CTokEOF",
        },

        -- Preprocessor directive AST nodes
        A.sum "CppDirective" {
            A.variant "CCppDefine" {
                A.field "macro" "MoonCAst.CMacro",
                A.variant_unique,
            },
            A.variant "CCppUndef" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "CCppInclude" {
                A.field "kind" "MoonCAst.CIncludeKind",
                A.field "path" "string",
                A.variant_unique,
            },
            A.variant "CCppIf" {
                A.field "tokens" (A.many "MoonCAst.CToken"),
                A.variant_unique,
            },
            A.variant "CCppIfdef" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "CCppIfndef" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "CCppElif" {
                A.field "tokens" (A.many "MoonCAst.CToken"),
                A.variant_unique,
            },
            A.variant "CCppElse",
            A.variant "CCppEndif",
            A.variant "CCppError" {
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "CCppPragma" {
                A.field "tokens" (A.many "MoonCAst.CToken"),
                A.variant_unique,
            },
            A.variant "CCppLine" {
                A.field "line" "number",
                A.field "file" (A.optional "string"),
                A.variant_unique,
            },
        },

        A.sum "CIncludeKind" {
            A.variant "CIncludeAngle",    -- <file.h>
            A.variant "CIncludeQuoted",   -- "file.h"
        },

        -- Macro definitions
        A.sum "CMacroKind" {
            A.variant "CObjectLike",
            A.variant "CFunctionLike" {
                A.field "params" (A.many "string"),
                A.field "variadic" "boolean",
                A.variant_unique,
            },
        },

        A.product "CMacro" {
            A.field "name" "string",
            A.field "kind" "MoonCAst.CMacroKind",
            A.field "body" (A.many "MoonCAst.CToken"),
            A.field "location" "MoonSource.SourceRange",
            A.unique,
        },

        ------------------------------------------------------------------
        -- Translation unit (§6.1)
        ------------------------------------------------------------------

        A.product "TranslationUnit" {
            A.field "items" (A.many "MoonCAst.TopLevelItem"),
            A.unique,
        },

        A.sum "TopLevelItem" {
            A.variant "CATopDecl" {
                A.field "decl" "MoonCAst.Decl",
                A.variant_unique,
            },
            A.variant "CATopFuncDef" {
                A.field "func" "MoonCAst.FuncDef",
                A.variant_unique,
            },
            A.variant "CATopCpp" {
                A.field "directive" "MoonCAst.CppDirective",
                A.variant_unique,
            },
        },

        ------------------------------------------------------------------
        -- Declarations (§6.2)
        ------------------------------------------------------------------

        A.sum "StorageClass" {
            A.variant "CStorageTypedef",
            A.variant "CStorageExtern",
            A.variant "CStorageStatic",
            A.variant "CStorageAuto",
            A.variant "CStorageRegister",
        },

        A.sum "Qualifier" {
            A.variant "CQualConst",
            A.variant "CQualRestrict",
            A.variant "CQualVolatile",
            A.variant "CQualInline",
        },

        A.sum "TypeSpec" {
            A.variant "CTyVoid",
            A.variant "CTyChar",
            A.variant "CTyShort",
            A.variant "CTyInt",
            A.variant "CTyLong",
            A.variant "CTyLongLong",
            A.variant "CTyFloat",
            A.variant "CTyDouble",
            A.variant "CTyLongDouble",
            A.variant "CTySigned",
            A.variant "CTyUnsigned",
            A.variant "CTyBool",              -- _Bool
            A.variant "CTyComplex",           -- _Complex (parsed, rejected by cimport)
            A.variant "CTyStructOrUnion" {
                A.field "kind" "MoonCAst.StructKind",
                A.field "name" (A.optional "string"),
                A.field "members" (A.optional (A.many "MoonCAst.FieldDecl")),
                A.variant_unique,
            },
            A.variant "CTyEnum" {
                A.field "name" (A.optional "string"),
                A.field "enumerators" (A.optional (A.many "MoonCAst.Enumerator")),
                A.variant_unique,
            },
            A.variant "CTyNamed" {
                A.field "name" "string",
                A.variant_unique,
            },  -- typedef reference
            A.variant "CTyTypeof" {
                A.field "expr" "MoonCAst.Expr",
                A.variant_unique,
            },   -- GCC typeof
        },

        A.sum "StructKind" {
            A.variant "CStructKindStruct",
            A.variant "CStructKindUnion",
        },

        A.product "Decl" {
            A.field "storage" (A.optional "MoonCAst.StorageClass"),
            A.field "qualifiers" (A.many "MoonCAst.Qualifier"),
            A.field "type_spec" "MoonCAst.TypeSpec",
            A.field "declarators" (A.many "MoonCAst.Declarator"),
            A.unique,
        },

        ------------------------------------------------------------------
        -- Declarators (§6.3)
        ------------------------------------------------------------------

        A.product "Declarator" {
            A.field "name" (A.optional "string"),
            A.field "derived" (A.many "MoonCAst.DerivedType"),
            A.field "initializer" (A.optional "MoonCAst.Initializer"),
            A.unique,
        },

        A.sum "DerivedType" {
            A.variant "CDerivedPointer" {
                A.field "qualifiers" (A.many "MoonCAst.Qualifier"),
                A.variant_unique,
            },
            A.variant "CDerivedArray" {
                A.field "size" (A.optional "MoonCAst.Expr"),
                A.variant_unique,
            },
            A.variant "CDerivedFunction" {
                A.field "params" (A.many "MoonCAst.ParamDecl"),
                A.field "variadic" "boolean",
                A.variant_unique,
            },
        },

        A.product "FieldDecl" {
            A.field "type_spec" "MoonCAst.TypeSpec",
            A.field "declarators" (A.many "MoonCAst.FieldDeclarator"),
            A.unique,
        },

        A.product "FieldDeclarator" {
            A.field "declarator" (A.optional "MoonCAst.Declarator"),
            A.field "bit_width" (A.optional "MoonCAst.Expr"),
            A.unique,
        },

        A.product "Enumerator" {
            A.field "name" "string",
            A.field "value" (A.optional "MoonCAst.Expr"),
            A.unique,
        },

        A.product "ParamDecl" {
            A.field "type_spec" "MoonCAst.TypeSpec",
            A.field "qualifiers" (A.many "MoonCAst.Qualifier"),
            A.field "declarator" (A.optional "MoonCAst.Declarator"),
            A.unique,
        },

        A.product "FuncDef" {
            A.field "storage" (A.optional "MoonCAst.StorageClass"),
            A.field "qualifiers" (A.many "MoonCAst.Qualifier"),
            A.field "type_spec" "MoonCAst.TypeSpec",
            A.field "declarator" "MoonCAst.Declarator",
            A.field "body" "MoonCAst.Stmt",
            A.unique,
        },

        A.product "TypeName" {
            A.field "type_spec" "MoonCAst.TypeSpec",
            A.field "derived" (A.many "MoonCAst.DerivedType"),
            A.unique,
        },

        ------------------------------------------------------------------
        -- Expressions (§6.4)
        ------------------------------------------------------------------

        A.sum "Expr" {
            -- Literals
            A.variant "CEIntLit"      { A.field "raw" "string", A.field "suffix" "string", A.variant_unique },
            A.variant "CEFloatLit"    { A.field "raw" "string", A.field "suffix" "string", A.variant_unique },
            A.variant "CECharLit"     { A.field "raw" "string", A.variant_unique },
            A.variant "CEStrLit"      { A.field "raw" "string", A.variant_unique },
            A.variant "CEBoolLit"     { A.field "value" "boolean", A.variant_unique },

            -- Primary
            A.variant "CEIdent"       { A.field "name" "string", A.variant_unique },
            A.variant "CEParen"       { A.field "expr" "MoonCAst.Expr", A.variant_unique },

            -- Unary
            A.variant "CEPreInc"      { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEPreDec"      { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEPostInc"     { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEPostDec"     { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEAddrOf"      { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEDeref"       { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEPlus"        { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEMinus"       { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CEBitNot"      { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CENot"         { A.field "operand" "MoonCAst.Expr", A.variant_unique },
            A.variant "CESizeofExpr"  { A.field "expr" "MoonCAst.Expr", A.variant_unique },
            A.variant "CESizeofType"  { A.field "type_name" "MoonCAst.TypeName", A.variant_unique },
            A.variant "CECast"        { A.field "type_name" "MoonCAst.TypeName", A.field "expr" "MoonCAst.Expr", A.variant_unique },

            -- Binary
            A.variant "CEBinary" {
                A.field "op" "MoonCAst.BinaryOp",
                A.field "left" "MoonCAst.Expr",
                A.field "right" "MoonCAst.Expr",
                A.variant_unique,
            },

            -- Ternary
            A.variant "CETernary" {
                A.field "cond" "MoonCAst.Expr",
                A.field "then_expr" "MoonCAst.Expr",
                A.field "else_expr" "MoonCAst.Expr",
                A.variant_unique,
            },

            -- Assignment
            A.variant "CEAssign" {
                A.field "op" "MoonCAst.AssignOp",
                A.field "left" "MoonCAst.Expr",
                A.field "right" "MoonCAst.Expr",
                A.variant_unique,
            },

            -- Member access
            A.variant "CEDot"         { A.field "base" "MoonCAst.Expr", A.field "field" "string", A.variant_unique },
            A.variant "CEArrow"       { A.field "base" "MoonCAst.Expr", A.field "field" "string", A.variant_unique },

            -- Subscript & call
            A.variant "CESubscript"   { A.field "base" "MoonCAst.Expr", A.field "index" "MoonCAst.Expr", A.variant_unique },
            A.variant "CECall"        { A.field "callee" "MoonCAst.Expr", A.field "args" (A.many "MoonCAst.Expr"), A.variant_unique },

            -- Compound literal
            A.variant "CECompoundLit" {
                A.field "type_name" "MoonCAst.TypeName",
                A.field "initializer" "MoonCAst.Initializer",
                A.variant_unique,
            },

            -- GNU statement expression
            A.variant "CEStmtExpr" {
                A.field "items" (A.many "MoonCAst.BlockItem"),
                A.field "result" "MoonCAst.Expr",
                A.variant_unique,
            },

            -- Comma operator
            A.variant "CEComma"       { A.field "left" "MoonCAst.Expr", A.field "right" "MoonCAst.Expr", A.variant_unique },
        },

        A.sum "BinaryOp" {
            A.variant "CBinAdd",     A.variant "CBinSub",
            A.variant "CBinMul",     A.variant "CBinDiv",      A.variant "CBinMod",
            A.variant "CBinShl",     A.variant "CBinShr",
            A.variant "CBinLt",      A.variant "CBinLe",
            A.variant "CBinGt",      A.variant "CBinGe",
            A.variant "CBinEq",      A.variant "CBinNe",
            A.variant "CBinBitAnd",  A.variant "CBinBitXor",   A.variant "CBinBitOr",
            A.variant "CBinLogAnd",  A.variant "CBinLogOr",
        },

        A.sum "AssignOp" {
            A.variant "CAssign",       A.variant "CAddAssign",    A.variant "CSubAssign",
            A.variant "CMulAssign",    A.variant "CDivAssign",    A.variant "CModAssign",
            A.variant "CShlAssign",    A.variant "CShrAssign",
            A.variant "CAndAssign",    A.variant "CXorAssign",    A.variant "COrAssign",
        },

        ------------------------------------------------------------------
        -- Statements (§6.5)
        ------------------------------------------------------------------

        A.sum "Stmt" {
            A.variant "CSLabeled"   {
                A.field "label" "string",
                A.field "stmt" "MoonCAst.Stmt",
                A.variant_unique,
            },
            A.variant "CSCase"      {
                A.field "value" "MoonCAst.Expr",
                A.field "stmt" "MoonCAst.Stmt",
                A.variant_unique,
            },
            A.variant "CSDefault"   {
                A.field "stmt" "MoonCAst.Stmt",
                A.variant_unique,
            },
            A.variant "CSExpr"      {
                A.field "expr" (A.optional "MoonCAst.Expr"),
                A.variant_unique,
            },
            A.variant "CSCompound"  {
                A.field "items" (A.many "MoonCAst.BlockItem"),
                A.variant_unique,
            },
            A.variant "CSIf"        {
                A.field "cond" "MoonCAst.Expr",
                A.field "then_stmt" "MoonCAst.Stmt",
                A.field "else_stmt" (A.optional "MoonCAst.Stmt"),
                A.variant_unique,
            },
            A.variant "CSSwitch"    {
                A.field "cond" "MoonCAst.Expr",
                A.field "body" "MoonCAst.Stmt",
                A.variant_unique,
            },
            A.variant "CSWhile"     {
                A.field "cond" "MoonCAst.Expr",
                A.field "body" "MoonCAst.Stmt",
                A.variant_unique,
            },
            A.variant "CSDoWhile"   {
                A.field "body" "MoonCAst.Stmt",
                A.field "cond" "MoonCAst.Expr",
                A.variant_unique,
            },
            A.variant "CSFor"       {
                A.field "init" (A.optional "MoonCAst.ForInit"),
                A.field "cond" (A.optional "MoonCAst.Expr"),
                A.field "incr" (A.optional "MoonCAst.Expr"),
                A.field "body" "MoonCAst.Stmt",
                A.variant_unique,
            },
            A.variant "CSGoto"      {
                A.field "label" "string",
                A.variant_unique,
            },
            A.variant "CSContinue",
            A.variant "CSBreak",
            A.variant "CSReturn"    {
                A.field "expr" (A.optional "MoonCAst.Expr"),
                A.variant_unique,
            },
        },

        A.sum "ForInit" {
            A.variant "CFInitExpr"  {
                A.field "expr" "MoonCAst.Expr",
                A.variant_unique,
            },
            A.variant "CFInitDecl"  {
                A.field "decl" "MoonCAst.Decl",
                A.variant_unique,
            },
        },

        A.sum "BlockItem" {
            A.variant "CBlockDecl"  {
                A.field "decl" "MoonCAst.Decl",
                A.variant_unique,
            },
            A.variant "CBlockStmt"  {
                A.field "stmt" "MoonCAst.Stmt",
                A.variant_unique,
            },
        },

        ------------------------------------------------------------------
        -- Initializers (§6.6)
        ------------------------------------------------------------------

        A.sum "Initializer" {
            A.variant "CInitExpr"   {
                A.field "expr" "MoonCAst.Expr",
                A.variant_unique,
            },
            A.variant "CInitList"   {
                A.field "items" (A.many "MoonCAst.InitItem"),
                A.variant_unique,
            },
        },

        A.product "InitItem" {
            A.field "designator" (A.optional (A.many "MoonCAst.Designator")),
            A.field "value" "MoonCAst.Initializer",
            A.unique,
        },

        A.sum "Designator" {
            A.variant "CDesigField" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "CDesigIndex" {
                A.field "index" "MoonCAst.Expr",
                A.variant_unique,
            },
            A.variant "CDesigRange" {
                A.field "lo" "MoonCAst.Expr",
                A.field "hi" "MoonCAst.Expr",
                A.variant_unique,
            },
        },
    }
end
