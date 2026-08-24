import Foundation
import Testing

@testable import GrokBotCore

@Suite(.serialized)
struct XAIResponsesClientTests {
  @Test func encodesResponsesRequestAndDecodesText() async throws {
    StubURLProtocol.handler = { request in
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
      let body = try #require(request.bodyData)
      let json = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      #expect(json["model"] as? String == "grok-test")
      #expect(json["parallel_tool_calls"] as? Bool == false)
      #expect(json["store"] as? Bool == true)
      #expect((json["tools"] as? [[String: Any]])?.first?["name"] as? String == "example")
      let response =
        #"{"id":"resp-1","output":[{"type":"message","content":[{"type":"output_text","text":"Hello"}]}]}"#
      return (200, Data(response.utf8))
    }
    let session = URLSession(configuration: StubURLProtocol.configuration)
    let client = XAIResponsesClient(
      session: session,
      endpoint: URL(string: "https://example.invalid/v1/responses")!
    )
    let tool = XAIToolDefinition(
      name: "example",
      description: "Example",
      parameters: .object(["type": .string("object")])
    )
    let response = try await client.respond(
      apiKey: "secret",
      model: "grok-test",
      instructions: "Be helpful",
      messages: [.init(role: "user", content: "Hi")],
      functionOutput: nil,
      previousResponseID: nil,
      tools: [tool]
    )
    #expect(response.id == "resp-1")
    #expect(response.outputText == "Hello")
  }

  @Test func decodesFunctionCallArguments() async throws {
    StubURLProtocol.handler = { _ in
      let response =
        #"{"id":"resp-2","output":[{"type":"function_call","call_id":"call-1","name":"send_imessage","arguments":"{\"text\":\"Hi\",\"chat_id\":7}"}]}"#
      return (200, Data(response.utf8))
    }
    let client = XAIResponsesClient(
      session: URLSession(configuration: StubURLProtocol.configuration),
      endpoint: URL(string: "https://example.invalid/v1/responses")!
    )
    let response = try await client.respond(
      apiKey: "secret",
      model: "grok-test",
      instructions: nil,
      messages: [.init(role: "user", content: "Send it")],
      functionOutput: nil,
      previousResponseID: nil,
      tools: []
    )
    #expect(response.functionCalls.first?.name == "send_imessage")
    #expect(response.functionCalls.first?.arguments.int("chat_id") == 7)
  }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  static var handler: ((URLRequest) throws -> (Int, Data))?

  static var configuration: URLSessionConfiguration {
    let value = URLSessionConfiguration.ephemeral
    value.protocolClasses = [StubURLProtocol.self]
    return value
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      let (status, data) = try Self.handler?(request) ?? (500, Data())
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

extension URLRequest {
  fileprivate var bodyData: Data? {
    if let httpBody { return httpBody }
    guard let stream = httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: 4_096)
      guard count >= 0 else { return nil }
      if count == 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
