-- Clean MoonParse schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonParse" {
        A.product "ParseIssue" {
            A.field "message" "string",
            A.field "offset" "number",
            A.field "line" "number",
            A.field "col" "number",
            A.unique,
        },

        A.sum "ParseResult" {
            A.variant "ParseResult" {
                A.field "module" "MoonTree.Module",
                A.field "issues" (A.many "MoonParse.ParseIssue"),
                A.variant_unique,
            },
        },
    }
end
