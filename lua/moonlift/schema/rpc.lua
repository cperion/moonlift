local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonRpc {
  product. JsonMember { key [str], field. value [MoonRpc.JsonValue], },
  sum. JsonValue {
    JsonNull,
    JsonBool { field. value [bool], },
    JsonNumber { raw [str], },
    JsonString { field. value [str], },
    JsonArray { values [many [MoonRpc.JsonValue]], },
    JsonObject { members [many [MoonRpc.JsonMember]], },
  },
  sum. Incoming {
    RpcRequest {
      field. id [MoonEditor.RpcId],
      method [str],
      params [MoonRpc.JsonValue],
    },
    RpcIncomingNotification { method [str], params [MoonRpc.JsonValue], },
    RpcInvalid { reason [str], },
  },
  sum. Outgoing {
    RpcResult { field. id [MoonEditor.RpcId], payload [MoonLsp.Payload], },
    RpcError { field. id [MoonEditor.RpcId], code [number], message [str], },
    RpcOutgoingNotification { method [str], payload [MoonLsp.Payload], },
  },
  sum. OutCommand {
    SendMessage { outgoing [MoonRpc.Outgoing], },
    LogMessage { level [str], message [str], },
    StopServer,
  },
}
