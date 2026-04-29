-- Clean MoonCore schema, authored as MoonAsdl data through Lua builders.
--
-- This is the first hand-authored replacement for the historical Moon2Core text
-- schema.  It intentionally uses the future names (`MoonCore.*`) instead of the
-- compatibility names consumed by the current compiler implementation.

return function(A)
    return A.module "MoonCore" {
        A.product "Name" {
            A.field "text" "string",
            A.unique,
        },

        A.product "Path" {
            A.field "parts" (A.many "MoonCore.Name"),
            A.unique,
        },

        A.product "Id" {
            A.field "text" "string",
            A.unique,
        },

        A.product "ModuleId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "ItemId" {
            A.field "text" "string",
            A.unique,
        },

        A.product "FieldId" {
            A.field "text" "string",
            A.unique,
        },

        A.sum "Phase" {
            A.variant "PhaseSurface",
            A.variant "PhaseTyped",
            A.variant "PhaseOpen",
            A.variant "PhaseSem",
            A.variant "PhaseCode",
        },

        A.sum "Visibility" {
            A.variant "VisibilityLocal",
            A.variant "VisibilityExport",
        },

        A.sum "Scalar" {
            A.variant "ScalarVoid",
            A.variant "ScalarBool",
            A.variant "ScalarI8",
            A.variant "ScalarI16",
            A.variant "ScalarI32",
            A.variant "ScalarI64",
            A.variant "ScalarU8",
            A.variant "ScalarU16",
            A.variant "ScalarU32",
            A.variant "ScalarU64",
            A.variant "ScalarF32",
            A.variant "ScalarF64",
            A.variant "ScalarRawPtr",
            A.variant "ScalarIndex",
        },

        A.sum "ScalarFamily" {
            A.variant "ScalarFamilyVoid",
            A.variant "ScalarFamilyBool",
            A.variant "ScalarFamilySignedInt",
            A.variant "ScalarFamilyUnsignedInt",
            A.variant "ScalarFamilyFloat",
            A.variant "ScalarFamilyRawPtr",
            A.variant "ScalarFamilyIndex",
        },

        A.product "ScalarBits" {
            A.field "bits" "number",
            A.unique,
        },

        A.product "ScalarInfo" {
            A.field "family" "MoonCore.ScalarFamily",
            A.field "bits" "MoonCore.ScalarBits",
            A.unique,
        },

        A.sum "Literal" {
            A.variant "LitInt" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "LitFloat" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "LitBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
            A.variant "LitNil",
        },

        A.sum "UnaryOp" {
            A.variant "UnaryNeg",
            A.variant "UnaryNot",
            A.variant "UnaryBitNot",
        },

        A.sum "BinaryOp" {
            A.variant "BinAdd",
            A.variant "BinSub",
            A.variant "BinMul",
            A.variant "BinDiv",
            A.variant "BinRem",
            A.variant "BinBitAnd",
            A.variant "BinBitOr",
            A.variant "BinBitXor",
            A.variant "BinShl",
            A.variant "BinLShr",
            A.variant "BinAShr",
        },

        A.sum "CmpOp" {
            A.variant "CmpEq",
            A.variant "CmpNe",
            A.variant "CmpLt",
            A.variant "CmpLe",
            A.variant "CmpGt",
            A.variant "CmpGe",
        },

        A.sum "LogicOp" {
            A.variant "LogicAnd",
            A.variant "LogicOr",
        },

        A.sum "SurfaceCastOp" {
            A.variant "SurfaceCast",
            A.variant "SurfaceTrunc",
            A.variant "SurfaceZExt",
            A.variant "SurfaceSExt",
            A.variant "SurfaceBitcast",
            A.variant "SurfaceSatCast",
        },

        A.sum "MachineCastOp" {
            A.variant "MachineCastIdentity",
            A.variant "MachineCastBitcast",
            A.variant "MachineCastIreduce",
            A.variant "MachineCastSextend",
            A.variant "MachineCastUextend",
            A.variant "MachineCastFpromote",
            A.variant "MachineCastFdemote",
            A.variant "MachineCastSToF",
            A.variant "MachineCastUToF",
            A.variant "MachineCastFToS",
            A.variant "MachineCastFToU",
        },

        A.sum "Intrinsic" {
            A.variant "IntrinsicPopcount",
            A.variant "IntrinsicClz",
            A.variant "IntrinsicCtz",
            A.variant "IntrinsicRotl",
            A.variant "IntrinsicRotr",
            A.variant "IntrinsicBswap",
            A.variant "IntrinsicFma",
            A.variant "IntrinsicSqrt",
            A.variant "IntrinsicAbs",
            A.variant "IntrinsicFloor",
            A.variant "IntrinsicCeil",
            A.variant "IntrinsicTruncFloat",
            A.variant "IntrinsicRound",
            A.variant "IntrinsicTrap",
            A.variant "IntrinsicAssume",
        },

        A.sum "UnaryOpClass" {
            A.variant "UnaryClassArithmetic",
            A.variant "UnaryClassLogical",
            A.variant "UnaryClassBitwise",
        },

        A.sum "BinaryOpClass" {
            A.variant "BinaryClassArithmetic",
            A.variant "BinaryClassDivision",
            A.variant "BinaryClassRemainder",
            A.variant "BinaryClassBitwise",
            A.variant "BinaryClassShift",
        },

        A.sum "CmpOpClass" {
            A.variant "CmpClassEquality",
            A.variant "CmpClassOrdering",
        },

        A.sum "IntrinsicClass" {
            A.variant "IntrinsicClassBit",
            A.variant "IntrinsicClassFloat",
            A.variant "IntrinsicClassFused",
            A.variant "IntrinsicClassControl",
        },

        A.product "TypeSym" {
            A.field "key" "string",
            A.field "name" "string",
            A.unique,
        },

        A.product "FuncSym" {
            A.field "key" "string",
            A.field "name" "string",
            A.unique,
        },

        A.product "ExternSym" {
            A.field "key" "string",
            A.field "name" "string",
            A.field "symbol" "string",
            A.unique,
        },

        A.product "ConstSym" {
            A.field "key" "string",
            A.field "name" "string",
            A.unique,
        },

        A.product "StaticSym" {
            A.field "key" "string",
            A.field "name" "string",
            A.unique,
        },
    }
end
