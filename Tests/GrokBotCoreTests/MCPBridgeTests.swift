import Testing

@testable import GrokBotCore

@Test func initializeNegotiatesMCPAndAdvertisesTools() async throws {
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: MockReminders())
  let bridge = MCPBridge(configuration: .init(), toolbox: toolbox)
  let initialize = JSONValue.object([
    "jsonrpc": .string("2.0"),
    "id": .number(1),
    "method": .string("initialize"),
    "params": .object(["protocolVersion": .string("2025-06-18")]),
  ])
  let response = await bridge.handle(initialize)
  let result = response?.objectValue?["result"]?.objectValue
  #expect(result?.string("protocolVersion") == "2025-06-18")
  #expect(result?["capabilities"]?.objectValue?["tools"] != nil)

  let list = await bridge.handle(
    .object([
      "jsonrpc": .string("2.0"),
      "id": .string("tools"),
      "method": .string("tools/list"),
    ]))
  let tools = list?.objectValue?["result"]?.objectValue?["tools"]?.arrayValue
  #expect(tools?.count == 8)
}

@Test func toolFailuresUseMCPToolErrorResultInsteadOfJSONRPCFailure() async {
  var configuration = BridgeConfiguration()
  configuration.allowedChatIDs = []
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: MockReminders())
  let bridge = MCPBridge(configuration: configuration, toolbox: toolbox)
  let response = await bridge.handle(
    .object([
      "jsonrpc": .string("2.0"),
      "id": .number(2),
      "method": .string("tools/call"),
      "params": .object([
        "name": .string("read_imessage_history"),
        "arguments": .object(["chat_id": .number(9)]),
      ]),
    ]))
  let result = response?.objectValue?["result"]?.objectValue
  #expect(result?.bool("isError") == true)
  #expect(response?.objectValue?["error"] == nil)
}
