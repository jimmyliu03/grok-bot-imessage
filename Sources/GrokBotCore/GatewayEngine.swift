import Foundation

public actor GatewayEngine {
  private var configuration: BotConfiguration
  private let messages: IMsgServicing
  private let toolLoop: GrokToolLoop
  private let stateStore: GatewayStateStoring
  private let eventSink: @Sendable (GatewayEvent) -> Void
  private var state: PersistedGatewayState
  private var running = false
  private var drainingMessages = false
  private var queuedMessages: [IMsgMessage] = []
  private var admittedGUIDs: Set<String> = []

  public init(
    configuration: BotConfiguration,
    messages: IMsgServicing,
    toolLoop: GrokToolLoop,
    stateStore: GatewayStateStoring = JSONGatewayStateStore(),
    eventSink: @escaping @Sendable (GatewayEvent) -> Void = { _ in }
  ) {
    self.configuration = configuration
    self.messages = messages
    self.toolLoop = toolLoop
    self.stateStore = stateStore
    self.eventSink = eventSink
    self.state = (try? stateStore.load()) ?? PersistedGatewayState()
  }

  public func start() async {
    guard !running else { return }
    eventSink(.status(.starting))
    purgeExpiredState()
    do {
      if let identity = await messages.databaseIdentity() {
        if let previous = state.messagesDatabaseIdentity, previous != identity {
          state.lastMessageRowID = nil
          state.processedGUIDs.removeAll()
          eventSink(.activity("Messages database changed; reset the replay cursor safely."))
        }
        state.messagesDatabaseIdentity = identity
        try? stateStore.save(state)
      }
      try await messages.start(sinceRowID: state.lastMessageRowID) { [weak self] message in
        Task { await self?.receive(message) }
      }
      running = true
      eventSink(.status(.running))
      eventSink(.activity("Grok Bot is listening for iMessages."))
    } catch {
      running = false
      eventSink(.status(.failed(error.localizedDescription)))
      eventSink(.activity(error.localizedDescription))
    }
  }

  public func stop() async {
    guard running else {
      eventSink(.status(.stopped))
      return
    }
    await messages.stop()
    running = false
    drainingMessages = false
    queuedMessages.removeAll()
    admittedGUIDs.removeAll()
    try? stateStore.save(state)
    eventSink(.status(.stopped))
    eventSink(.activity("Grok Bot stopped."))
  }

  public func updateConfiguration(_ value: BotConfiguration) {
    configuration = value
  }

  public func currentState() -> PersistedGatewayState { state }

  public func approvePairing(id: UUID) -> String? {
    guard let request = state.pairingRequests.first(where: { $0.id == id }) else { return nil }
    state.pairingRequests.removeAll { $0.id == id }
    try? stateStore.save(state)
    eventSink(.pairingRequests(state.pairingRequests))
    return request.handle
  }

  public func rejectPairing(id: UUID) {
    state.pairingRequests.removeAll { $0.id == id }
    try? stateStore.save(state)
    eventSink(.pairingRequests(state.pairingRequests))
  }

  public func resolveApproval(id: UUID, approved: Bool) async {
    guard let approval = state.pendingApprovals.first(where: { $0.id == id }) else { return }
    await resolve(approval: approval, approved: approved)
  }

  public func resetSession(conversationKey: String) {
    state.sessions[conversationKey] = []
    try? stateStore.save(state)
  }

  private func receive(_ message: IMsgMessage) async {
    guard running else { return }
    guard !state.processedGUIDs.contains(message.guid), !admittedGUIDs.contains(message.guid) else {
      return
    }
    admittedGUIDs.insert(message.guid)
    queuedMessages.append(message)
    guard !drainingMessages else { return }
    drainingMessages = true
    while running, !queuedMessages.isEmpty {
      let next = queuedMessages.removeFirst()
      await processAdmission(next)
      guard running else {
        admittedGUIDs.remove(next.guid)
        break
      }
      admittedGUIDs.remove(next.guid)
      state.lastMessageRowID = max(state.lastMessageRowID ?? 0, next.id)
      state.processedGUIDs.append(next.guid)
      if state.processedGUIDs.count > 2_000 {
        state.processedGUIDs.removeFirst(state.processedGUIDs.count - 2_000)
      }
      purgeExpiredState()
      try? stateStore.save(state)
    }
    drainingMessages = false
  }

  private func processAdmission(_ message: IMsgMessage) async {
    guard !message.isReaction,
      let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else { return }
    if isStaleReplay(message) {
      eventSink(.activity("Skipped an old replayed message in chat \(message.chatID)."))
      return
    }
    if isBotEcho(message, text: text) { return }
    if message.isFromMe && !configuration.ownerSelfChatIDs.contains(message.chatID) { return }
    await process(message, text: text)
  }

  private func process(_ message: IMsgMessage, text: String) async {
    let handle = message.isFromMe ? "self" : (message.sender ?? "unknown")
    guard await authorize(message: message, handle: handle) else { return }
    let isOwner = message.isFromMe || configuration.isOwner(handle)
    let context = ToolContext(
      requesterHandle: handle,
      requesterIsOwner: isOwner,
      conversationChatID: message.chatID,
      conversationKey: message.conversationKey,
      isGroup: message.isGroup
    )

    if await handleCommand(text, message: message, context: context) { return }

    let history = Array(
      (state.sessions[message.conversationKey] ?? []).suffix(configuration.maxSessionMessages))
    eventSink(.activity("Grok is responding to \(handle) in chat \(message.chatID)…"))
    do {
      let result = try await toolLoop.respond(
        userText: text,
        history: history,
        context: context,
        configuration: configuration
      )
      guard running else { return }
      appendTurn(.init(role: .user, text: text), conversationKey: message.conversationKey)
      await deliver(result, context: context)
      eventSink(.handledMessage(chatID: message.chatID, sender: handle))
    } catch {
      guard running else { return }
      let reply = "I hit a problem: \(error.localizedDescription)"
      appendTurn(.init(role: .user, text: text), conversationKey: message.conversationKey)
      await sendReply(reply, chatID: message.chatID)
      appendTurn(.init(role: .assistant, text: reply), conversationKey: message.conversationKey)
      eventSink(.activity("Request failed: \(error.localizedDescription)"))
    }
  }

  private func authorize(message: IMsgMessage, handle: String) async -> Bool {
    if message.isFromMe { return configuration.ownerSelfChatIDs.contains(message.chatID) }
    if message.isGroup {
      guard configuration.groupMessagePolicy == .allowlist,
        configuration.allowedGroupChatIDs.contains(message.chatID),
        configuration.isAllowed(handle)
      else { return false }
      if configuration.requireMentionInGroups {
        let body = message.text?.lowercased() ?? ""
        guard configuration.mentionWords.contains(where: { body.contains($0.lowercased()) }) else {
          return false
        }
      }
      return true
    }
    switch configuration.directMessagePolicy {
    case .disabled:
      return false
    case .allowlist:
      return configuration.isAllowed(handle)
    case .pairing:
      if configuration.isAllowed(handle) { return true }
      let request: PairingRequest
      if let existing = state.pairingRequests.first(where: {
        BotConfiguration.normalizedHandle($0.handle) == BotConfiguration.normalizedHandle(handle)
          && $0.expiresAt > Date()
      }) {
        request = existing
      } else {
        request = PairingRequest(
          code: String(Int.random(in: 100_000...999_999)), handle: handle, chatID: message.chatID)
        state.pairingRequests.append(request)
        try? stateStore.save(state)
        eventSink(.pairingRequests(state.pairingRequests))
      }
      await sendReply(
        "This Grok Bot only responds to approved people. Pairing code: \(request.code). Ask the owner to approve it in the Grok Bot app.",
        chatID: message.chatID)
      return false
    }
  }

  private func handleCommand(_ text: String, message: IMsgMessage, context: ToolContext) async
    -> Bool
  {
    let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    guard let command = words.first else { return false }
    if command == "/status" {
      await sendReply(
        "Grok Bot is online. Model: \(configuration.model). Reminders: \(configuration.remindersEnabled ? "on" : "off").",
        chatID: message.chatID)
      return true
    }
    if command == "/reset" {
      state.sessions[message.conversationKey] = []
      try? stateStore.save(state)
      await sendReply("Session reset. We can start fresh.", chatID: message.chatID)
      return true
    }
    if command == "approve" || command == "/approve" || command == "deny" || command == "/deny",
      words.count == 2,
      let approval = state.pendingApprovals.first(where: {
        $0.chatID == message.chatID && $0.code == words[1] && $0.expiresAt > Date()
      })
    {
      guard context.requesterIsOwner else {
        await sendReply("Only a configured owner can approve actions.", chatID: message.chatID)
        return true
      }
      await resolve(approval: approval, approved: command.contains("approve"))
      return true
    }
    return false
  }

  private func resolve(approval: PendingApproval, approved: Bool) async {
    state.pendingApprovals.removeAll { $0.id == approval.id }
    try? stateStore.save(state)
    eventSink(.pendingApprovals(state.pendingApprovals))
    let context = ToolContext(
      requesterHandle: approval.requesterHandle,
      requesterIsOwner: true,
      conversationChatID: approval.chatID,
      conversationKey: approval.conversationKey,
      isGroup: configuration.allowedGroupChatIDs.contains(approval.chatID)
    )
    do {
      let result = try await toolLoop.continueApproval(
        approval,
        approved: approved,
        context: context,
        configuration: configuration
      )
      await deliver(result, context: context)
    } catch {
      let reply = "I couldn't finish that action: \(error.localizedDescription)"
      await sendReply(reply, chatID: approval.chatID)
      appendTurn(.init(role: .assistant, text: reply), conversationKey: approval.conversationKey)
    }
  }

  private func deliver(_ result: GrokTurnResult, context: ToolContext) async {
    switch result {
    case .message(let text):
      await sendReply(text, chatID: context.conversationChatID)
      appendTurn(.init(role: .assistant, text: text), conversationKey: context.conversationKey)
      eventSink(.activity("Replied in chat \(context.conversationChatID)."))
    case .approvalRequired(let approval):
      state.pendingApprovals.removeAll { $0.chatID == approval.chatID }
      state.pendingApprovals.append(approval)
      try? stateStore.save(state)
      eventSink(.pendingApprovals(state.pendingApprovals))
      await sendReply(
        "Approval needed: \(approval.summary). Reply “approve \(approval.code)” or “deny \(approval.code)” within 10 minutes.",
        chatID: context.conversationChatID
      )
    }
  }

  private func appendTurn(_ turn: ConversationTurn, conversationKey: String) {
    var turns = state.sessions[conversationKey, default: []]
    turns.append(turn)
    let limit = max(4, configuration.maxSessionMessages)
    if turns.count > limit { turns.removeFirst(turns.count - limit) }
    state.sessions[conversationKey] = turns
    try? stateStore.save(state)
  }

  private func sendReply(_ text: String, chatID: Int) async {
    for part in splitForIMessage(text) {
      state.botSentFingerprints.append(.init(chatID: chatID, text: part))
      purgeFingerprints()
      try? stateStore.save(state)
      do {
        try await messages.send(chatID: chatID, text: part)
      } catch {
        eventSink(.activity("Could not send to chat \(chatID): \(error.localizedDescription)"))
        return
      }
    }
  }

  private func splitForIMessage(_ text: String, limit: Int = 3_000) -> [String] {
    guard text.count > limit else { return [text] }
    var parts: [String] = []
    var remainder = text[...]
    while remainder.count > limit {
      let boundary = remainder.index(remainder.startIndex, offsetBy: limit)
      let prefix = remainder[..<boundary]
      let split = prefix.lastIndex(of: "\n") ?? prefix.lastIndex(of: " ") ?? boundary
      let part = remainder[..<split].trimmingCharacters(in: .whitespacesAndNewlines)
      if !part.isEmpty { parts.append(part) }
      remainder = remainder[split...].drop(while: { $0.isWhitespace })
    }
    let tail = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty { parts.append(tail) }
    return parts
  }

  private func isBotEcho(_ message: IMsgMessage, text: String) -> Bool {
    guard message.isFromMe else { return false }
    let messageDate = message.createdAt.flatMap(ISO8601DateFormatter.grokBotDate(from:)) ?? Date()
    return state.botSentFingerprints.contains {
      $0.chatID == message.chatID && $0.text == text
        && abs(messageDate.timeIntervalSince($0.sentAt)) < 120
    }
  }

  private func isStaleReplay(_ message: IMsgMessage) -> Bool {
    guard let raw = message.createdAt,
      let date = ISO8601DateFormatter.grokBotDate(from: raw)
    else { return false }
    return date < Date().addingTimeInterval(-7_200)
  }

  private func purgeExpiredState() {
    let now = Date()
    state.pairingRequests.removeAll { $0.expiresAt <= now }
    state.pendingApprovals.removeAll { $0.expiresAt <= now }
    purgeFingerprints()
    eventSink(.pairingRequests(state.pairingRequests))
    eventSink(.pendingApprovals(state.pendingApprovals))
  }

  private func purgeFingerprints() {
    let cutoff = Date().addingTimeInterval(-7_200)
    state.botSentFingerprints.removeAll { $0.sentAt < cutoff }
    if state.botSentFingerprints.count > 200 {
      state.botSentFingerprints.removeFirst(state.botSentFingerprints.count - 200)
    }
  }
}
