import AppKit
import EventKit
import GrokBotCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
  enum Page: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case access = "Access"
    case people = "People & Chats"
    case activity = "Activity"

    var id: String { rawValue }
    var icon: String {
      switch self {
      case .dashboard: "gauge.with.dots.needle.67percent"
      case .access: "key.horizontal"
      case .people: "person.2"
      case .activity: "waveform.path.ecg"
      }
    }
  }

  var selection: Page? = .dashboard
  var configuration: BotConfiguration
  var status: GatewayStatus = .stopped
  var activity: [ActivityEntry] = []
  var pairingRequests: [PairingRequest] = []
  var pendingApprovals: [PendingApproval] = []
  var recentChats: [IMsgChat] = []
  var apiKeyDraft = ""
  var hasAPIKey = false
  var imsgInstalled = false
  var messagesReady = false
  var remindersStatus: EKAuthorizationStatus = .notDetermined
  var setupMessage: String?
  var isChecking = false
  var isInstallingIMsg = false
  var onboardingComplete: Bool {
    didSet { UserDefaults.standard.set(onboardingComplete, forKey: "onboardingComplete") }
  }

  struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let text: String
  }

  private let configurationStore: ConfigurationStore
  private let keychain: KeychainAPIKeyStore
  private let messageService: IMsgRPCService
  private let remindersService: EventKitRemindersService
  private let stateStore: JSONGatewayStateStore

  @ObservationIgnored private var engine: GatewayEngine!

  init(
    configurationStore: ConfigurationStore = .shared,
    keychain: KeychainAPIKeyStore = .shared,
    messageService: IMsgRPCService = IMsgRPCService(),
    remindersService: EventKitRemindersService? = nil,
    stateStore: JSONGatewayStateStore = JSONGatewayStateStore()
  ) {
    self.configurationStore = configurationStore
    self.keychain = keychain
    self.messageService = messageService
    self.remindersService = remindersService ?? EventKitRemindersService()
    self.stateStore = stateStore
    self.engine = nil
    self.configuration = configurationStore.load()
    self.onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    self.hasAPIKey = keychain.hasAPIKey()
    self.imsgInstalled = IMsgLocator.locate() != nil
    self.remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    if let state = try? stateStore.load() {
      pairingRequests = state.pairingRequests.filter { $0.expiresAt > Date() }
      pendingApprovals = state.pendingApprovals.filter { $0.expiresAt > Date() }
    }
    let toolbox = BotToolbox(messages: self.messageService, reminders: self.remindersService)
    let toolLoop = GrokToolLoop(apiKeys: self.keychain, tools: toolbox)
    self.engine = GatewayEngine(
      configuration: self.configuration,
      messages: self.messageService,
      toolLoop: toolLoop,
      stateStore: self.stateStore
    ) { [weak self] event in
      Task { @MainActor in self?.apply(event) }
    }
    Task { await refreshEnvironment() }
  }

  var checklistReadyCount: Int {
    [
      hasAPIKey, imsgInstalled, messagesReady, remindersStatus == .fullAccess,
      !configuration.ownerHandles.isEmpty || !configuration.ownerSelfChatIDs.isEmpty,
    ]
    .filter { $0 }.count
  }

  var canStart: Bool {
    hasAPIKey
      && imsgInstalled
      && messagesReady
      && (!configuration.remindersEnabled || remindersStatus == .fullAccess)
      && (!configuration.ownerHandles.isEmpty || !configuration.ownerSelfChatIDs.isEmpty)
  }

  func saveConfiguration() {
    do {
      try configurationStore.save(configuration)
      Task { await engine.updateConfiguration(configuration) }
      setLaunchAtLogin(configuration.launchAtLogin)
      addActivity("Settings saved.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func saveAPIKey() {
    do {
      try keychain.save(apiKeyDraft)
      apiKeyDraft = ""
      hasAPIKey = keychain.hasAPIKey()
      setupMessage = "API key saved securely in Keychain."
      addActivity("xAI API key updated.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func removeAPIKey() {
    do {
      try keychain.delete()
      hasAPIKey = false
      addActivity("xAI API key removed.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func toggleGateway() async {
    if status == .running || status == .starting {
      await engine.stop()
    } else {
      saveConfiguration()
      guard canStart else {
        setupMessage =
          "Finish the required access steps and add at least one owner before starting."
        selection = .access
        return
      }
      await engine.start()
    }
  }

  func refreshEnvironment() async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    hasAPIKey = keychain.hasAPIKey()
    imsgInstalled = IMsgLocator.locate() != nil
    remindersStatus = await remindersService.authorizationStatus()
    if imsgInstalled {
      do {
        let raw = try await IMsgDiagnostics.status()
        messagesReady = Self.databaseIsReady(in: raw)
        if !messagesReady {
          setupMessage =
            "imsg is installed, but Messages data is not readable yet. Grant Full Disk Access and restart Grok Bot."
        }
      } catch {
        messagesReady = false
        setupMessage = error.localizedDescription
      }
    } else {
      messagesReady = false
    }
  }

  func requestRemindersAccess() async {
    do {
      _ = try await remindersService.requestAccess()
      remindersStatus = await remindersService.authorizationStatus()
      addActivity("Reminders permission updated.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func installIMsg() async {
    guard !isInstallingIMsg else { return }
    isInstallingIMsg = true
    defer { isInstallingIMsg = false }
    do {
      let output = try await runBrewInstall()
      setupMessage = output.isEmpty ? "imsg installed." : output
      await refreshEnvironment()
      addActivity("imsg installation finished.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func refreshChats() async {
    do {
      let wasRunning = status == .running
      if !wasRunning {
        try await messageService.start(sinceRowID: nil) { _ in }
      }
      recentChats = try await messageService.listChats(limit: 40)
      if !wasRunning { await messageService.stop() }
    } catch {
      setupMessage = error.localizedDescription
      if status != .running { await messageService.stop() }
    }
  }

  func approvePairing(_ request: PairingRequest) async {
    if let handle = await engine.approvePairing(id: request.id), !configuration.isAllowed(handle) {
      configuration.allowedSenders.append(handle)
      saveConfiguration()
    }
  }

  func rejectPairing(_ request: PairingRequest) async {
    await engine.rejectPairing(id: request.id)
  }

  func resolveApproval(_ approval: PendingApproval, approved: Bool) async {
    await engine.resolveApproval(id: approval.id, approved: approved)
  }

  func openFullDiskAccess() {
    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
  }

  func openAutomationAccess() {
    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
  }

  func openRemindersAccess() {
    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
  }

  func finishOnboarding() {
    saveConfiguration()
    onboardingComplete = true
    selection = .dashboard
  }

  func showOnboarding() { onboardingComplete = false }

  private func apply(_ event: GatewayEvent) {
    switch event {
    case .status(let value): status = value
    case .activity(let value): addActivity(value)
    case .pairingRequests(let value): pairingRequests = value
    case .pendingApprovals(let value): pendingApprovals = value
    case .handledMessage(let chatID, let sender):
      addActivity("Handled a message from \(sender) in chat \(chatID).")
    }
  }

  private func addActivity(_ text: String) {
    activity.insert(.init(text: text), at: 0)
    if activity.count > 200 { activity.removeLast(activity.count - 200) }
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled, SMAppService.mainApp.status == .notRegistered {
        try SMAppService.mainApp.register()
      } else if !enabled, SMAppService.mainApp.status != .notRegistered {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      setupMessage = "Launch at login: \(error.localizedDescription)"
    }
  }

  private func openSettings(_ rawURL: String) {
    guard let url = URL(string: rawURL) else { return }
    NSWorkspace.shared.open(url)
  }

  private func runBrewInstall() async throws -> String {
    let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    guard let brew = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      throw IMsgError.processFailed(
        "Homebrew is required. Install it from brew.sh, then try again.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "steipete/tap/imsg"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
          try process.run()
          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()
          let output = String(data: data, encoding: .utf8) ?? ""
          if process.terminationStatus == 0 {
            continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
          } else {
            continuation.resume(throwing: IMsgError.processFailed(output))
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func databaseIsReady(in raw: String) -> Bool {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = object["result"] as? [String: Any],
      let database = result["database"] as? [String: Any]
    else { return false }
    return database["ready"] as? Bool == true
  }
}
