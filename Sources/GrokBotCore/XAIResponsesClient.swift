import Foundation

public struct XAIToolDefinition: Codable, Equatable, Sendable {
  public let type: String
  public let name: String
  public let description: String
  public let parameters: JSONValue

  public init(name: String, description: String, parameters: JSONValue) {
    self.type = "function"
    self.name = name
    self.description = description
    self.parameters = parameters
  }
}

public struct XAIMessageInput: Codable, Equatable, Sendable {
  public let role: String
  public let content: String

  public init(role: String, content: String) {
    self.role = role
    self.content = content
  }
}

public struct XAIFunctionOutput: Codable, Equatable, Sendable {
  public let type = "function_call_output"
  public let callID: String
  public let output: String

  enum CodingKeys: String, CodingKey {
    case type, output
    case callID = "call_id"
  }

  public init(callID: String, output: String) {
    self.callID = callID
    self.output = output
  }
}

public struct XAIFunctionCall: Equatable, Sendable {
  public let callID: String
  public let name: String
  public let arguments: [String: JSONValue]

  public init(callID: String, name: String, arguments: [String: JSONValue]) {
    self.callID = callID
    self.name = name
    self.arguments = arguments
  }
}

public struct XAIResponse: Equatable, Sendable {
  public let id: String
  public let outputText: String?
  public let functionCalls: [XAIFunctionCall]

  public init(id: String, outputText: String?, functionCalls: [XAIFunctionCall]) {
    self.id = id
    self.outputText = outputText
    self.functionCalls = functionCalls
  }
}

public enum XAIClientError: LocalizedError, Equatable {
  case invalidResponse
  case api(status: Int, message: String)
  case invalidToolArguments(tool: String)
  case emptyResponse

  public var errorDescription: String? {
    switch self {
    case .invalidResponse: return "xAI returned an unreadable response."
    case .api(let status, let message): return "xAI request failed (\(status)): \(message)"
    case .invalidToolArguments(let tool): return "Grok returned invalid arguments for \(tool)."
    case .emptyResponse: return "Grok returned no message or tool call."
    }
  }
}

public protocol XAIResponding: Sendable {
  func respond(
    apiKey: String,
    model: String,
    instructions: String?,
    messages: [XAIMessageInput],
    functionOutput: XAIFunctionOutput?,
    previousResponseID: String?,
    tools: [XAIToolDefinition]
  ) async throws -> XAIResponse
}

public final class XAIResponsesClient: XAIResponding, @unchecked Sendable {
  private let session: URLSession
  private let endpoint: URL
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(
    session: URLSession = .shared,
    endpoint: URL = URL(string: "https://api.x.ai/v1/responses")!
  ) {
    self.session = session
    self.endpoint = endpoint
  }

  public func respond(
    apiKey: String,
    model: String,
    instructions: String?,
    messages: [XAIMessageInput],
    functionOutput: XAIFunctionOutput?,
    previousResponseID: String?,
    tools: [XAIToolDefinition]
  ) async throws -> XAIResponse {
    let requestBody = RequestBody(
      model: model,
      instructions: instructions,
      input: functionOutput.map { .functionOutput($0) } ?? .messages(messages),
      previousResponseID: previousResponseID,
      tools: tools
    )

    var attempt = 0
    while true {
      var request = URLRequest(url: endpoint)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.timeoutInterval = 180
      request.httpBody = try encoder.encode(requestBody)

      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw XAIClientError.invalidResponse }
      if (200..<300).contains(http.statusCode) {
        return try decodeResponse(data)
      }
      let message =
        decodeAPIError(data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
      if http.statusCode == 429 || http.statusCode >= 500, attempt < 3 {
        attempt += 1
        try await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << (attempt - 1))))
        continue
      }
      throw XAIClientError.api(status: http.statusCode, message: message)
    }
  }

  private func decodeResponse(_ data: Data) throws -> XAIResponse {
    let decoded = try decoder.decode(ResponseBody.self, from: data)
    var textParts: [String] = []
    var calls: [XAIFunctionCall] = []
    for item in decoded.output {
      if item.type == "message" {
        textParts.append(contentsOf: item.content?.compactMap(\.text) ?? [])
      } else if item.type == "function_call",
        let callID = item.callID,
        let name = item.name,
        let argumentsText = item.arguments,
        let argumentsData = argumentsText.data(using: .utf8),
        let arguments = try? decoder.decode([String: JSONValue].self, from: argumentsData)
      {
        calls.append(.init(callID: callID, name: name, arguments: arguments))
      } else if item.type == "function_call", let name = item.name {
        throw XAIClientError.invalidToolArguments(tool: name)
      }
    }
    let outputText = textParts.joined(separator: "\n").trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard !outputText.isEmpty || !calls.isEmpty else { throw XAIClientError.emptyResponse }
    return XAIResponse(
      id: decoded.id, outputText: outputText.isEmpty ? nil : outputText, functionCalls: calls)
  }

  private func decodeAPIError(_ data: Data) -> String? {
    (try? decoder.decode(APIErrorEnvelope.self, from: data))?.error.message
  }
}

private struct RequestBody: Encodable {
  let model: String
  let instructions: String?
  let input: RequestInput
  let previousResponseID: String?
  let tools: [XAIToolDefinition]
  let parallelToolCalls = false
  let store = true

  enum CodingKeys: String, CodingKey {
    case model, instructions, input, tools, store
    case previousResponseID = "previous_response_id"
    case parallelToolCalls = "parallel_tool_calls"
  }
}

private enum RequestInput: Encodable {
  case messages([XAIMessageInput])
  case functionOutput(XAIFunctionOutput)

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .messages(let value): try container.encode(value)
    case .functionOutput(let value): try container.encode([value])
    }
  }
}

private struct ResponseBody: Decodable {
  let id: String
  let output: [ResponseItem]
}

private struct ResponseItem: Decodable {
  let type: String
  let callID: String?
  let name: String?
  let arguments: String?
  let content: [ResponseContent]?

  enum CodingKeys: String, CodingKey {
    case type, name, arguments, content
    case callID = "call_id"
  }
}

private struct ResponseContent: Decodable {
  let type: String
  let text: String?
}

private struct APIErrorEnvelope: Decodable {
  struct Detail: Decodable { let message: String }
  let error: Detail
}
