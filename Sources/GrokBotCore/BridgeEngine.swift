import Foundation

public actor BridgeEngine {
  private var configuration: BridgeConfiguration
  private var token: String
  private let messages: IMsgServicing
  private let toolbox: BridgeToolbox
  private let bridge: MCPBridge
  private let eventSink: @Sendable (BridgeEvent) -> Void
  private var server: MCPHTTPServer?
  private var running = false
  private var starting = false
  private var desiredRunning = false
  private var lifecycleGeneration = 0

  public init(
    configuration: BridgeConfiguration,
    token: String,
    messages: IMsgServicing,
    reminders: RemindersServicing,
    eventSink: @escaping @Sendable (BridgeEvent) -> Void = { _ in }
  ) {
    self.configuration = configuration
    self.token = token
    self.messages = messages
    self.eventSink = eventSink
    let toolbox = BridgeToolbox(
      messages: messages,
      reminders: reminders,
      approvalEventSink: { eventSink(.approvals($0)) }
    )
    self.toolbox = toolbox
    self.bridge = MCPBridge(
      configuration: configuration,
      toolbox: toolbox,
      eventSink: eventSink
    )
  }

  public func start() async {
    guard !running, !starting else { return }
    desiredRunning = true
    starting = true
    lifecycleGeneration &+= 1
    let generation = lifecycleGeneration
    eventSink(.status(.starting))
    var candidateServer: MCPHTTPServer?
    do {
      if configuration.messagesEnabled {
        try await messages.start(
          sinceRowID: nil,
          onMessage: { _ in },
          onFailure: { [weak self] error in
            Task { await self?.handleMessagesFailure(error) }
          }
        )
      }
      guard desiredRunning, lifecycleGeneration == generation else {
        await messages.stop()
        return
      }
      let server = MCPHTTPServer(bridge: bridge, token: token)
      candidateServer = server
      self.server = server
      try await server.start(port: configuration.port)
      guard desiredRunning, lifecycleGeneration == generation else {
        server.stop()
        if self.server === server { self.server = nil }
        await messages.stop()
        return
      }
      starting = false
      running = true
      eventSink(.status(.running(port: configuration.port)))
      eventSink(.activity("Mac Bridge is ready for Grok Bot MCP connections."))
    } catch {
      candidateServer?.stop()
      if let candidateServer, server === candidateServer { server = nil }
      await messages.stop()
      guard lifecycleGeneration == generation else { return }
      starting = false
      running = false
      desiredRunning = false
      eventSink(.status(.failed(error.localizedDescription)))
      eventSink(.activity("Bridge start failed: \(error.localizedDescription)"))
    }
  }

  public func stop() async {
    desiredRunning = false
    lifecycleGeneration &+= 1
    server?.stop()
    server = nil
    await messages.stop()
    starting = false
    running = false
    eventSink(.status(.stopped))
    eventSink(.activity("Mac Bridge stopped."))
  }

  public func updateConfiguration(_ value: BridgeConfiguration) async {
    let requiresRestart =
      value.port != configuration.port
      || value.messagesEnabled != configuration.messagesEnabled
    configuration = value
    await bridge.updateConfiguration(value)
    if running || starting, requiresRestart {
      await stop()
      await start()
    }
  }

  public func updateToken(_ value: String) async {
    token = value
    if running || starting {
      await stop()
      await start()
    }
  }

  public func approve(id: UUID) async {
    await bridge.approve(id: id)
  }

  public func deny(id: UUID) async {
    await bridge.deny(id: id)
  }

  public func pendingApprovals() async -> [BridgePendingApproval] {
    await toolbox.pendingApprovals()
  }

  private func handleMessagesFailure(_ error: Error) async {
    guard desiredRunning else { return }
    desiredRunning = false
    lifecycleGeneration &+= 1
    server?.stop()
    server = nil
    await messages.stop()
    starting = false
    running = false
    let message = "Messages bridge stopped: \(error.localizedDescription)"
    eventSink(.status(.failed(message)))
    eventSink(.activity(message))
  }
}
