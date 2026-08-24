import Foundation
import Testing

@testable import GrokBotCore

@Test func handlesNormalizeForOwnerChecks() {
  let config = BotConfiguration(ownerHandles: ["+1 (415) 555-1212", "Owner@iCloud.com"])
  #expect(config.isOwner("14155551212"))
  #expect(config.isOwner("owner@icloud.com"))
  #expect(!config.isOwner("+14155550000"))
}

@Test func imsgMessageDecodesMissingOptionalReactionAndInfersGroup() throws {
  let data = Data(
    #"{"id":42,"chat_id":7,"chat_guid":"iMessage;+;group123","guid":"ABC","is_from_me":false,"text":"Hi"}"#
      .utf8)
  let message = try JSONDecoder().decode(IMsgMessage.self, from: data)
  #expect(message.id == 42)
  #expect(message.isGroup)
  #expect(!message.isReaction)
  #expect(message.participants.isEmpty)
}

@Test func persistedStateMigratesWhenNewFieldsAreAbsent() throws {
  let data = Data(#"{"sessions":{},"processedGUIDs":["A"]}"#.utf8)
  let state = try JSONDecoder().decode(PersistedGatewayState.self, from: data)
  #expect(state.processedGUIDs == ["A"])
  #expect(state.botSentFingerprints.isEmpty)
  #expect(state.pendingApprovals.isEmpty)
}
