import Foundation
import Testing

@testable import GrokBotCore

@Test func imsgChatDecodesUnreadCountAndDefaultsMissingFields() throws {
  let value = try JSONDecoder().decode(
    IMsgChat.self,
    from: Data(
      """
      {"id":42,"display_name":"Vendor","participants":["+14155551212"],"unread_count":3}
      """.utf8)
  )
  #expect(value.id == 42)
  #expect(value.unreadCount == 3)
  #expect(value.title == "Vendor")
  #expect(!value.isGroup)
}

@Test func recipientAllowlistNormalizesPhoneNumbersAndEmails() {
  var configuration = BridgeConfiguration()
  configuration.allowedRecipients = ["+1 (415) 555-1212", "Person@iCloud.com"]
  #expect(configuration.permitsRecipient("+1 415 555 1212"))
  #expect(configuration.permitsRecipient("person@icloud.com"))
  #expect(!configuration.permitsRecipient("+14155550000"))
}
