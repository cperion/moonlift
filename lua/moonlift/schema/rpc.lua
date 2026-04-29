-- Clean MoonRpc schema, generated from the current ASDL schema.
-- Source of truth is now Lua builder data; edit deliberately.

return function(A)
    return A.module "MoonRpc" {
        A.product "JsonMember" {
            A.field "key" "string",
            A.field "value" "MoonRpc.JsonValue",
            A.unique,
        },

        A.sum "JsonValue" {
            A.variant "JsonNull",
            A.variant "JsonBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
            A.variant "JsonNumber" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "JsonString" {
                A.field "value" "string",
                A.variant_unique,
            },
            A.variant "JsonArray" {
                A.field "values" (A.many "MoonRpc.JsonValue"),
                A.variant_unique,
            },
            A.variant "JsonObject" {
                A.field "members" (A.many "MoonRpc.JsonMember"),
                A.variant_unique,
            },
        },

        A.sum "Incoming" {
            A.variant "RpcRequest" {
                A.field "id" "MoonEditor.RpcId",
                A.field "method" "string",
                A.field "params" "MoonRpc.JsonValue",
                A.variant_unique,
            },
            A.variant "RpcIncomingNotification" {
                A.field "method" "string",
                A.field "params" "MoonRpc.JsonValue",
                A.variant_unique,
            },
            A.variant "RpcInvalid" {
                A.field "reason" "string",
                A.variant_unique,
            },
        },

        A.sum "Outgoing" {
            A.variant "RpcResult" {
                A.field "id" "MoonEditor.RpcId",
                A.field "payload" "MoonLsp.Payload",
                A.variant_unique,
            },
            A.variant "RpcError" {
                A.field "id" "MoonEditor.RpcId",
                A.field "code" "number",
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "RpcOutgoingNotification" {
                A.field "method" "string",
                A.field "payload" "MoonLsp.Payload",
                A.variant_unique,
            },
        },

        A.sum "OutCommand" {
            A.variant "SendMessage" {
                A.field "outgoing" "MoonRpc.Outgoing",
                A.variant_unique,
            },
            A.variant "LogMessage" {
                A.field "level" "string",
                A.field "message" "string",
                A.variant_unique,
            },
            A.variant "StopServer",
        },
    }
end
