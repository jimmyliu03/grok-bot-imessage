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
    case access = "Apple Access"
    case scopes = "Data Scopes"
    case activity = "Activity"

    var id: String { rawValue }
    var icon: String {
      switch self {
      case .dashboard: "gauge.with.dots.needle.67percent"
      case .access: "key.horizontal"
      case .scopes: "checklist.checked"
      case .activity: "waveform.path.ecg"
      }
    }
  }

  var selection: Page? = .dashboard
  var configuration: BridgeConfiguration
  var status: BridgeStatus = .stopped
  var activity: [ActivityEntry] = []
  var pendingApprovals: [BridgePendingApproval] = []
  var recentChats: [IMsgChat] = []
  var reminderLists: [ReminderListRecord] = []
  var connectorToken: String
  var imsgInstalled = false
  var imsgPath: String?
  var messagesReady = false
  var remindersStatus: EKAuthorizationStatus = .notDetermined
  var setupMessage: String?
  var isChecking = false
  var onboardingComplete: Bool {
    didSet { UserDefaults.standard.set(onboardingComplete, forKey: Self.onboardingKey) }
  }

  struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let text: String
  }

  private static let onboardingKey = "bridgeOnboardingComplete.v1"
  private let configurationStore: BridgeConfigurationStore
  private let tokenStore: BridgeTokenStore
  private let messageService: IMsgRPCService
  private let remindersService: EventKitRemindersService

  @ObservationIgnored private var engine: BridgeEngine!

  init(
    configurationStore: BridgeConfigurationStore = .shared,
    tokenStore: BridgeTokenStore = .shared,
    messageService: IMsgRPCService = IMsgRPCService(),
    remindersService: EventKitRemindersService? = nil
  ) {
    self.configurationStore = configurationStore
    self.tokenStore = tokenStore
    self.messageService = messageService
    self.remindersService = remindersService ?? EventKitRemindersService()
    self.configuration = configurationStore.load()
    self.connectorToken = (try? tokenStore.loadOrCreate()) ?? ""
    self.onboardingComplete = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    self.imsgPath = IMsgLocator.locate()?.path
    self.imsgInstalled = imsgPath != nil
    self.remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    self.engine = nil
    self.engine = BridgeEngine(
      configuration: self.configuration,
      token: self.connectorToken,
      messages: self.messageService,
      reminders: self.remindersService
    ) { [weak self] event in
      Task { @MainActor in self?.apply(event) }
    }
    if connectorToken.isEmpty {
      self.setupMessage =
        "The connector token could not be loaded from Keychain. Check Keychain access, then reopen the app."
    }
    Task { await refreshEnvironment() }
  }

  var checklistReadyCount: Int {
    [
      !connectorToken.isEmpty,
      !configuration.messagesEnabled || (imsgInstalled && messagesReady),
      !configuration.remindersEnabled || remindersStatus == .fullAccess,
      configuredAccess,
      !configuration.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    ].filter { $0 }.count
  }

  var configuredAccess: Bool {
    let messageAccess =
      configuration.messagesEnabled
      && (configuration.messageAccessMode == .allChats
        || !configuration.allowedChatIDs.isEmpty
        || configuration.allowNewRecipients
        || !configuration.allowedRecipients.isEmpty)
    let reminderAccess =
      configuration.remindersEnabled
      && (configuration.reminderAccessMode == .allLists
        || !configuration.allowedReminderListIDs.isEmpty)
    return messageAccess || reminderAccess
  }

  var canStart: Bool {
    !connectorToken.isEmpty
      && (configuration.messagesEnabled || configuration.remindersEnabled)
      && (!configuration.messagesEnabled || (imsgInstalled && messagesReady))
      && (!configuration.remindersEnabled || remindersStatus == .fullAccess)
      && configuredAccess
  }

  var localServerURL: String {
    "http://127.0.0.1:\(configuration.port)"
  }

  var localConnectorURL: String {
    "\(localServerURL)/mcp/\(connectorToken)"
  }

  var publicConnectorURL: String? {
    let base = configuration.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: base), url.scheme == "https", url.host != nil,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
    else { return nil }
    return "\(base)/mcp/\(connectorToken)"
  }

  var tunnelCommand: String {
    "cloudflared tunnel --url \(localServerURL)"
  }

  func saveConfiguration() {
    do {
      try configurationStore.save(configuration)
      Task { await engine.updateConfiguration(configuration) }
      setLaunchAtLogin(configuration.launchAtLogin)
      addActivity("Bridge settings saved.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func rotateConnectorToken() async {
    do {
      connectorToken = try tokenStore.regenerate()
      await engine.updateToken(connectorToken)
      setupMessage = "Connector token rotated. Update the connector URL in Grok Bot."
      addActivity("Connector token rotated; old connector URLs no longer work.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func toggleBridge() async {
    if status.isRunning || status == .starting {
      await engine.stop()
    } else {
      saveConfiguration()
      await engine.updateConfiguration(configuration)
      guard canStart else {
        setupMessage =
          "Finish Apple permissions and select at least one Messages or Reminders access scope."
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
    imsgPath = IMsgLocator.locate()?.path
    imsgInstalled = imsgPath != nil
    remindersStatus = await remindersService.authorizationStatus()
    if imsgInstalled {
      do {
        let raw = try await IMsgDiagnostics.status()
        messagesReady = Self.databaseIsReady(in: raw)
        if messagesReady {
          await reconcileMessagesDatabaseIdentity()
        } else {
          setupMessage =
            "imsg is installed, but Messages data is not readable. Grant Full Disk Access and restart the app."
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
      await refreshReminderLists()
      addActivity("Reminders permission updated.")
    } catch {
      setupMessage = error.localizedDescription
    }
  }

  func prepareIMsgInstall() {
    copy("brew install steipete/tap/imsg")
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    setupMessage =
      "The imsg Homebrew command was copied. Paste it into Terminal, review it, run it, then choose Recheck."
  }

  func prepareTunnelInstall() {
    copy("brew install cloudflared")
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    setupMessage = "The cloudflared install command was copied to your clipboard."
  }

  func copyTunnelCommand() {
    copy(tunnelCommand)
    setupMessage =
      "Tunnel command copied. Run it while Mac Bridge is started, then paste its https://…trycloudflare.com URL here."
  }

  func copyConnectorURL() {
    guard let publicConnectorURL else {
      setupMessage = "Paste a valid public HTTPS tunnel URL first."
      return
    }
    copy(publicConnectorURL)
    setupMessage = "Private Grok connector URL copied. Treat it like a password."
  }

  func openGrokConnectors() {
    NSWorkspace.shared.open(URL(string: "https://grok.com/connectors")!)
  }

  func refreshChats() async {
    guard status != .starting else { return }
    do {
      let wasRunning = status.isRunning
      if !wasRunning {
        try await messageService.start(
          sinceRowID: nil,
          onMessage: { _ in },
          onFailure: { _ in }
        )
      }
      recentChats = try await messageService.listChats(limit: 100, unreadOnly: false)
      if !wasRunning { await messageService.stop() }
    } catch {
      setupMessage = error.localizedDescription
      if !status.isRunning { await messageService.stop() }
    }
  }

  func refreshReminderLists() async {
    do {
      reminderLists = try await remindersService.lists()
    } catch {
      if remindersStatus == .fullAccess { setupMessage = error.localizedDescription }
    }
  }

  func approve(_ approval: BridgePendingApproval) async {
    await engine.approve(id: approval.id)
    addActivity("Approved a pending \(approval.toolName) request for one retry.")
  }

  func deny(_ approval: BridgePendingApproval) async {
    await engine.deny(id: approval.id)
    addActivity("Denied a pending \(approval.toolName) request.")
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

  private func apply(_ event: BridgeEvent) {
    switch event {
    case .status(let value): status = value
    case .activity(let value): addActivity(value)
    case .approvals(let value): pendingApprovals = value
    case .toolCompleted(let name): addActivity("Grok Bot completed \(name).")
    }
  }

  private func addActivity(_ text: String) {
    activity.insert(.init(text: text), at: 0)
    if activity.count > 200 { activity.removeLast(activity.count - 200) }
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  private func reconcileMessagesDatabaseIdentity() async {
    guard let identity = await messageService.databaseIdentity() else { return }
    if let previous = configuration.messagesDatabaseIdentity, previous != identity {
      configuration.allowedChatIDs.removeAll()
      recentChats.removeAll()
      configuration.messagesDatabaseIdentity = identity
      try? configurationStore.save(configuration)
      await engine.updateConfiguration(configuration)
      setupMessage =
        "Messages database changed. Previously selected chat IDs were cleared; choose allowed chats again."
      addActivity("Messages database changed; cleared selected chat IDs.")
    } else if configuration.messagesDatabaseIdentity == nil {
      configuration.messagesDatabaseIdentity = identity
      try? configurationStore.save(configuration)
      await engine.updateConfiguration(configuration)
    }
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

  private static func databaseIsReady(in raw: String) -> Bool {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = object["result"] as? [String: Any],
      let database = result["database"] as? [String: Any]
    else { return false }
    return database["ready"] as? Bool == true
  }
}

extension BridgeStatus {
  var isRunning: Bool {
    if case .running = self { return true }
    return false
  }
}
