local S = require("lalin.schema.dsl")
S.use()

return schema. LalinRpc {
  product. JsonMember { key [str], field. value [LalinRpc.JsonValue], },
  sum. JsonValue {
    JsonNull,
    JsonBool { field. value [bool], },
    JsonNumber { raw [str], },
    JsonString { field. value [str], },
    JsonArray { values [many [LalinRpc.JsonValue]], },
    JsonObject { members [many [LalinRpc.JsonMember]], },
  },
  sum. Incoming {
    RpcRequest {
      field. id [LalinEditor.RpcId],
      method [str],
      params [LalinRpc.JsonValue],
    },
    RpcIncomingNotification { method [str], params [LalinRpc.JsonValue], },
    RpcInvalid { reason [str], },
  },
  sum. Outgoing {
    RpcResult { field. id [LalinEditor.RpcId], payload [LalinLsp.Payload], },
    RpcError { field. id [LalinEditor.RpcId], code [number], message [str], },
    RpcOutgoingNotification { method [str], payload [LalinLsp.Payload], },
  },
  sum. OutCommand {
    SendMessage { outgoing [LalinRpc.Outgoing], },
    LogMessage { level [str], message [str], },
    StopServer,
  },
}
