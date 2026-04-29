-- MoonPvmSurface: lowerable PVM phase bodies for generated Moonlift surface.
--
-- This is not a second low-level runtime.  It records the PVM producer
-- semantics that can be emitted as Moonlift region fragments: once/empty,
-- concatenation, phase calls, child loops, let/if, and tagged-union handlers.

return function(A)
    return A.module "MoonPvmSurface" {
        A.product "PhaseBody" {
            A.field "name" "string",
            A.field "input" "MoonPhase.TypeRef",
            A.field "output" "MoonPhase.TypeRef",
            A.field "cache" "MoonPhase.CachePolicy",
            A.field "result" "MoonPhase.ResultShape",
            A.field "handlers" (A.many "MoonPvmSurface.Handler"),
            A.field "default_body" (A.optional "MoonPvmSurface.Producer"),
            A.unique,
        },

        A.product "Handler" {
            A.field "ctor_name" "string",
            A.field "binds" (A.many "MoonPvmSurface.Bind"),
            A.field "body" "MoonPvmSurface.Producer",
            A.unique,
        },

        A.product "Bind" {
            A.field "name" "string",
            A.field "field_name" "string",
            A.unique,
        },

        A.sum "Producer" {
            A.variant "ProducerEmpty",
            A.variant "ProducerOnce" {
                A.field "value" "MoonPvmSurface.Expr",
                A.variant_unique,
            },
            A.variant "ProducerConcat" {
                A.field "parts" (A.many "MoonPvmSurface.Producer"),
                A.variant_unique,
            },
            A.variant "ProducerCallPhase" {
                A.field "phase_name" "string",
                A.field "subject" "MoonPvmSurface.Expr",
                A.field "args" (A.many "MoonPvmSurface.Expr"),
                A.variant_unique,
            },
            A.variant "ProducerChildren" {
                A.field "phase_name" "string",
                A.field "range" "MoonPvmSurface.Expr",
                A.variant_unique,
            },
            A.variant "ProducerLet" {
                A.field "name" "string",
                A.field "value" "MoonPvmSurface.Expr",
                A.field "body" "MoonPvmSurface.Producer",
                A.variant_unique,
            },
            A.variant "ProducerIf" {
                A.field "cond" "MoonPvmSurface.Expr",
                A.field "then_body" "MoonPvmSurface.Producer",
                A.field "else_body" "MoonPvmSurface.Producer",
                A.variant_unique,
            },
        },

        A.sum "Expr" {
            A.variant "ExprSubject",
            A.variant "ExprLocal" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ExprName" {
                A.field "name" "string",
                A.variant_unique,
            },
            A.variant "ExprField" {
                A.field "base" "MoonPvmSurface.Expr",
                A.field "field_name" "string",
                A.variant_unique,
            },
            A.variant "ExprCtor" {
                A.field "type_name" "string",
                A.field "ctor_name" "string",
                A.field "fields" (A.many "MoonPvmSurface.NamedExpr"),
                A.variant_unique,
            },
            A.variant "ExprCall" {
                A.field "func_name" "string",
                A.field "args" (A.many "MoonPvmSurface.Expr"),
                A.variant_unique,
            },
            A.variant "ExprLiteralInt" {
                A.field "text" "string",
                A.variant_unique,
            },
            A.variant "ExprLiteralBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
        },

        A.product "NamedExpr" {
            A.field "name" "string",
            A.field "value" "MoonPvmSurface.Expr",
            A.unique,
        },
    }
end
