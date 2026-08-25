import Foundation
import Testing

@testable import GrokBotCore

@Test func streamableHTTPServerAuthenticatesAndHandlesInitialize() async throws {
  var configuration = BridgeConfiguration()
  configuration.messagesEnabled = false
  let toolbox = BridgeToolbox(messages: MockMessages(), reminders: MockReminders())
  let bridge = MCPBridge(configuration: configuration, toolbox: toolbox)
  let token = "test-token-that-is-not-a-real-secret"
  let server = MCPHTTPServer(bridge: bridge, token: token)
  let port = UInt16.random(in: 42_000...49_000)
  try await server.start(port: port)
  defer { server.stop() }

  var unauthorized = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
  unauthorized.httpMethod = "POST"
  unauthorized.setValue("application/json", forHTTPHeaderField: "Content-Type")
  unauthorized.httpBody = Data("{}".utf8)
  let (_, unauthorizedResponse) = try await URLSession.shared.data(for: unauthorized)
  #expect((unauthorizedResponse as? HTTPURLResponse)?.statusCode == 401)

  var initialize = URLRequest(
    url: URL(string: "http://127.0.0.1:\(port)/mcp/\(token)")!)
  initialize.httpMethod = "POST"
  initialize.setValue("application/json", forHTTPHeaderField: "Content-Type")
  initialize.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
  initialize.httpBody = try JSONEncoder().encode(
    JSONValue.object([
      "jsonrpc": .string("2.0"),
      "id": .number(1),
      "method": .string("initialize"),
      "params": .object(["protocolVersion": .string("2025-06-18")]),
    ]))
  let (data, response) = try await URLSession.shared.data(for: initialize)
  #expect((response as? HTTPURLResponse)?.statusCode == 200)
  let json = try JSONDecoder().decode(JSONValue.self, from: data)
  #expect(
    json.objectValue?["result"]?.objectValue?.string("protocolVersion") == "2025-06-18")
}
