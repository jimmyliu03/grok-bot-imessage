import Foundation

public enum GrokTurnResult: Equatable, Sendable {
  case message(String)
  case approvalRequired(PendingApproval)
}

public enum GrokToolLoopError: LocalizedError, Equatable {
  case tooManyToolCalls
  case multipleCallsUnsupported
  case authorizationRevoked
  case mutationOutcomeUncertain(String)

  public var errorDescription: String? {
    switch self {
    case .tooManyToolCalls: return "Grok exceeded the tool-call safety limit."
    case .multipleCallsUnsupported:
      return "Grok requested multiple local actions at once. Please retry."
    case .authorizationRevoked:
      return "This request was cancelled because Grok Bot access changed or stopped."
    case .mutationOutcomeUncertain(let message):
      return "\(message) Grok Bot stopped this action chain and will not retry automatically."
    }
  }
}

public final class GrokToolLoop: @unchecked Sendable {
  private let client: XAIResponding
  private let apiKeys: APIKeyProviding
  private let tools: BotTooling
  private let codeGenerator: @Sendable () -> String

  public init(
    client: XAIResponding = XAIResponsesClient(),
    apiKeys: APIKeyProviding = KeychainAPIKeyStore.shared,
    tools: BotTooling,
    codeGenerator: @escaping @Sendable () -> String = { String(Int.random(in: 100_000...999_999)) }
  ) {
    self.client = client
    self.apiKeys = apiKeys
    self.tools = tools
    self.codeGenerator = codeGenerator
  }

  public func respond(
    userText: String,
    history: [ConversationTurn],
    context: ToolContext,
    configuration: BotConfiguration,
    executionGuard: @escaping @Sendable () async -> Bool = { true }
  ) async throws -> GrokTurnResult {
    var messages = history.map { XAIMessageInput(role: $0.role.rawValue, content: $0.text) }
    messages.append(.init(role: "user", content: userText))
    let definitions = tools.definitions(context: context, configuration: configuration)
    let instructions = configuration.systemPrompt + contextInstructions(context)
    let response = try await client.respond(
      apiKey: apiKeys.apiKey(),
      model: configuration.model,
      instructions: instructions,
      messages: messages,
      functionOutput: nil,
      previousResponseID: nil,
      tools: definitions
    )
    return try await process(
      initialResponse: response,
      context: context,
      configuration: configuration,
      definitions: definitions,
      executionGuard: executionGuard
    )
  }

  public func continueApproval(
    _ approval: PendingApproval,
    approved: Bool,
    context: ToolContext,
    configuration: BotConfiguration,
    executionGuard: @escaping @Sendable () async -> Bool = { true }
  ) async throws -> GrokTurnResult {
    guard approval.expiresAt > Date(), context.requesterIsOwner,
      approval.chatID == context.conversationChatID,
      approval.conversationKey == context.conversationKey,
      BotConfiguration.normalizedHandle(approval.requesterHandle)
        == BotConfiguration.normalizedHandle(context.requesterHandle)
    else { throw GrokToolLoopError.authorizationRevoked }
    guard await executionGuard() else { throw GrokToolLoopError.authorizationRevoked }
    let call = XAIFunctionCall(
      callID: approval.callID, name: approval.toolName, arguments: approval.arguments)
    let output: JSONValue
    if approved {
      switch tools.plan(call: call, context: context, configuration: configuration) {
      case .execute, .requiresApproval:
        break
      case .reject:
        throw GrokToolLoopError.authorizationRevoked
      }
      do {
        output = try await tools.execute(call: call, context: context)
      } catch {
        if let error = error as? IMsgError, error.requiresManualDeliveryCheck {
          throw GrokToolLoopError.mutationOutcomeUncertain(error.localizedDescription)
        }
        output = .object(["error": .string(error.localizedDescription)])
      }
    } else {
      output = .object(["error": .string("The user denied this action.")])
    }
    let definitions = tools.definitions(context: context, configuration: configuration)
    let response = try await client.respond(
      apiKey: apiKeys.apiKey(),
      model: approval.model,
      instructions: configuration.systemPrompt + contextInstructions(context),
      messages: [],
      functionOutput: XAIFunctionOutput(
        callID: approval.callID, output: try output.encodedString()),
      previousResponseID: approval.responseID,
      tools: definitions
    )
    return try await process(
      initialResponse: response,
      context: context,
      configuration: configuration,
      definitions: definitions,
      executionGuard: executionGuard
    )
  }

  private func process(
    initialResponse: XAIResponse,
    context: ToolContext,
    configuration: BotConfiguration,
    definitions: [XAIToolDefinition],
    executionGuard: @escaping @Sendable () async -> Bool
  ) async throws -> GrokTurnResult {
    var response = initialResponse
    for _ in 0..<8 {
      if response.functionCalls.isEmpty {
        guard let text = response.outputText else { throw XAIClientError.emptyResponse }
        return .message(text)
      }
      guard response.functionCalls.count == 1, let call = response.functionCalls.first else {
        throw GrokToolLoopError.multipleCallsUnsupported
      }
      switch tools.plan(call: call, context: context, configuration: configuration) {
      case .requiresApproval(let summary):
        return .approvalRequired(
          PendingApproval(
            code: codeGenerator(),
            chatID: context.conversationChatID,
            requesterHandle: context.requesterHandle,
            toolName: call.name,
            arguments: call.arguments,
            summary: summary,
            responseID: response.id,
            callID: call.callID,
            model: configuration.model,
            conversationKey: context.conversationKey
          ))
      case .execute:
        guard await executionGuard() else { throw GrokToolLoopError.authorizationRevoked }
        let output: JSONValue
        do {
          output = try await tools.execute(call: call, context: context)
        } catch {
          if let error = error as? IMsgError, error.requiresManualDeliveryCheck {
            throw GrokToolLoopError.mutationOutcomeUncertain(error.localizedDescription)
          }
          output = .object(["error": .string(error.localizedDescription)])
        }
        response = try await continueResponse(
          prior: response,
          call: call,
          output: output,
          model: configuration.model,
          instructions: configuration.systemPrompt + contextInstructions(context),
          definitions: definitions
        )
      case .reject(let reason):
        response = try await continueResponse(
          prior: response,
          call: call,
          output: .object(["error": .string(reason)]),
          model: configuration.model,
          instructions: configuration.systemPrompt + contextInstructions(context),
          definitions: definitions
        )
      }
    }
    throw GrokToolLoopError.tooManyToolCalls
  }

  private func continueResponse(
    prior: XAIResponse,
    call: XAIFunctionCall,
    output: JSONValue,
    model: String,
    instructions: String,
    definitions: [XAIToolDefinition]
  ) async throws -> XAIResponse {
    try await client.respond(
      apiKey: apiKeys.apiKey(),
      model: model,
      instructions: instructions,
      messages: [],
      functionOutput: XAIFunctionOutput(callID: call.callID, output: try output.encodedString()),
      previousResponseID: prior.id,
      tools: definitions
    )
  }

  private func contextInstructions(_ context: ToolContext) -> String {
    """


    Current channel context:
    - iMessage chat ID: \(context.conversationChatID)
    - requester: \(context.requesterHandle)
    - requester is an owner: \(context.requesterIsOwner)
    - group chat: \(context.isGroup)
    Personal tools are omitted for non-owners. Do not ask a non-owner to work around that restriction.
    """
  }
}
