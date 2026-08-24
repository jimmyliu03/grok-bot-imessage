# Grok Bot for iMessage

A local-first macOS gateway that lets approved people talk to Grok Bot through iMessage. Owners can also ask Grok Bot to read or send Messages and read, create, update, complete, or delete Apple Reminders.

Grok Bot is a real messaging bot, not a desktop chat wrapper. It watches new iMessages while running, keeps a separate conversation session per chat, calls the xAI Responses API, and replies through the same Messages conversation.

> [!IMPORTANT]
> This is an independent open-source project. It is not affiliated with, endorsed by, or supported by xAI or Apple. “Grok,” “iMessage,” and “Reminders” are trademarks of their respective owners.

## Why this architecture

Current agent gateways generally take one of three paths:

- OpenClaw's modern local path uses [`imsg`](https://github.com/openclaw/imsg) over JSON-RPC on stdin/stdout. Reads stay local, no port is exposed, and normal sends use Messages automation.
- Hermes Agent commonly uses BlueBubbles, which adds a macOS HTTP server and webhook, or managed relays such as Photon/Claw Messenger that provide a separate iMessage line.
- Direct database/AppleScript integrations reimplement a moving Messages schema and delivery edge cases themselves.

Grok Bot uses the first path. `imsg` already handles Messages database changes, WAL watching, group routing, message coalescing, and macOS delivery verification. Grok Bot deliberately uses only its normal read/watch/send surfaces; it does **not** enable private IMCore injection or ask users to disable System Integrity Protection.

```text
iPhone / iMessage
       │
       ▼
Messages.app ── read-only chat.db ──► imsg rpc (stdio)
       ▲                                  │
       │                                  ▼
       └── Messages automation ◄── Grok Bot gateway ──► xAI Responses API
                                          │
                                          └──► EventKit ──► Reminders
```

## Safety defaults

- Direct messages are owner/allowlist-only. Unknown senders are silently ignored unless pairing mode is explicitly enabled.
- Personal Messages and Reminders tools are exposed only when the current sender is an owner.
- Group support starts disabled. Allowed groups can require the word “Grok” in every request.
- Every send/create/update/delete tool call pauses for an exact approval code in iMessage by default.
- Bot-authored echoes are durably recorded, preventing self-chat reply loops across restarts.
- A replay cursor, GUID tombstones, and a two-hour age fence prevent duplicate replies and stale backlog floods.
- xAI API credentials live in macOS Keychain. Activity logs never contain message bodies or keys.
- Owner prompts and selected tool results use xAI's stateful Responses API so approval continuations work. API content may be retained under the xAI account's data controls, typically for up to 30 days; review [xAI's security FAQ](https://docs.x.ai/developers/faq/security) before use.
- Session history and gateway cursors stay in `~/Library/Application Support/GrokBot/` with owner-only file permissions.
- Terminal watch failures are surfaced and retried with bounded backoff. Uncertain message deliveries are never retried automatically.

See [SECURITY.md](SECURITY.md) for the trust model and reporting process.

## Requirements

- macOS 14 Sonoma or later
- Messages.app signed into iMessage
- [Homebrew](https://brew.sh/)
- An [xAI API key](https://console.x.ai/)
- Full Disk Access, Messages automation, and Reminders access granted during setup

A dedicated iMessage account on an always-on Mac is the cleanest deployment: sign Messages.app into the bot account and add your personal phone/email as the owner. A carefully selected self-chat also works, but should not be combined with general outgoing-message monitoring.

## Install from source

```bash
git clone https://github.com/jimmyliu03/grok-bot-imessage.git
cd grok-bot-imessage
make install
open /Applications/GrokBot.app
```

The first-run guide copies the exact `brew install steipete/tap/imsg` command for you to review and run in Terminal, stores the API key in Keychain, opens the correct privacy panes, and helps select owners/chats. Grok Bot resolves `imsg` only from Homebrew's standard locations and shows the canonical executable path before use.

To build without installing:

```bash
make app
open dist/GrokBot.app
```

The local build is ad-hoc signed. Public downloadable releases require a maintainer's Apple Developer ID signature and notarization; source builds do not.

## Use

Start the bot from the dashboard or menu bar, then send a message from an approved owner:

```text
You: Remind me tomorrow at 9 to send the proposal
Grok Bot: Approval needed: Create reminder “Send the proposal”.
          Reply “approve 483921” or “deny 483921” within 10 minutes.
You: approve 483921
Grok Bot: Done — I added it for tomorrow at 9:00 AM.
```

Useful channel commands:

- `/status` — show model and tool status
- `/reset` — clear this chat's Grok session context
- `approve <code>` / `deny <code>` — resolve a pending write

## Development

```bash
swift build
swift test
make check
```

The package has no third-party Swift dependencies. The app targets SwiftUI, EventKit, Security/Keychain, ServiceManagement, and the external `imsg` executable.

Project layout:

```text
Sources/GrokBotCore/   Gateway, xAI client, tools, persistence, imsg RPC
Sources/GrokBotApp/    SwiftUI setup, dashboard, permissions, settings
Tests/                 Unit and gateway integration tests with fakes
Resources/             Info.plist, entitlements, source app icon
scripts/               Reproducible app bundling and release checks
```

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
