# Grok Bot Mac Bridge

A native macOS companion that gives the actual Grok Bot controlled access to Messages and Apple Reminders.

Talk to Grok Bot in the Grok Bot app. Grok Bot calls this bridge when it needs to check correspondence, message another person or business, or manage reminders. The bridge does **not** call the xAI API or run a separate agent.

> [!IMPORTANT]
> This is an independent open-source project. It is not affiliated with, endorsed by, or supported by xAI, Cursor, or Apple. “Grok,” “Grok Bot,” “iMessage,” and “Reminders” are trademarks of their respective owners.

```text
You ──► Grok Bot app ──► Grok Bot cloud agent
                              │
                        MCP over HTTPS
                              │
                    authenticated tunnel
                              │
                 Mac Bridge on 127.0.0.1
                       │              │
                  imsg rpc         EventKit
                       │              │
                  Messages.app    Reminders.app
                       │
                people / businesses
```

## Capabilities

Messages:

- List recent or unread chats.
- Read bounded history from an allowed chat.
- Send plain-text iMessage or SMS to an allowed chat or recipient.
- Keep basic mode: public AppleScript sending, no private IMCore injection, and no SIP changes.

Reminders:

- List permitted reminder lists and reminders.
- Create, update, complete, and delete reminders.
- Resolve every mutation against the local EventKit object and selected list scope.

Safety:

- The MCP server binds only to `127.0.0.1` and requires a random 256-bit token stored in Keychain.
- Users select individual chats, new recipients, and reminder lists—or explicitly allow all.
- Writes require one-time approval in the Mac app by default. Approval is bound to the exact tool arguments, expires after ten minutes, and is consumed on retry.
- MCP tool annotations mark reads and writes, including destructive reminder deletion.
- Message bodies, reminder text, connector tokens, and tool arguments are not written to the activity log.
- `imsg` is accepted only from canonical, non-world-writable Homebrew locations.
- Uncertain Messages deliveries are blocked from automatic retry.

Read [SECURITY.md](SECURITY.md) before exposing the connector.

## Requirements

- An always-on Mac running macOS 14 Sonoma or later.
- Messages.app signed into the sending Apple account.
- Grok Bot access and permission to add a custom MCP connector.
- [Homebrew](https://brew.sh/), [`imsg`](https://github.com/openclaw/imsg), and an HTTPS tunnel such as `cloudflared`.
- Full Disk Access, Messages Automation, and Reminders Full Access.
- For SMS, an associated iPhone with Text Message Forwarding enabled for the Mac.

No xAI API key is required.

## Install

```bash
git clone https://github.com/jimmyliu03/grok-bot-imessage.git
cd grok-bot-imessage
make install
open /Applications/GrokBot.app
```

The first-run guide installs `imsg`, walks through Apple permissions, selects data scopes, creates the Keychain token, and builds the private connector URL.

For a local build without installation:

```bash
make app
open dist/GrokBot.app
```

Source builds are ad-hoc signed. Public binary releases require a Developer ID signature and Apple notarization.

## Add it to Grok Bot

Follow [GROK_BOT_SETUP.md](GROK_BOT_SETUP.md). In short:

1. Finish the companion setup and start the bridge.
2. Run a stable HTTPS tunnel to `http://127.0.0.1:29333`.
3. Paste its public base URL into the app and copy the private MCP URL.
4. At [grok.com/connectors](https://grok.com/connectors), add a **Custom** connector using that URL.
5. In Grok Bot, open **Settings → Plugins → Yours** and enable the connector for the intended Bot.
6. Install or save the included `apple-messages-reminders` safety skill.

The server implements stateless MCP Streamable HTTP. It supports MCP protocol versions `2025-06-18`, `2025-03-26`, and `2024-11-05`.

## Example tasks

```text
Check whether the plumber replied in Messages. Summarize the latest exchange and do not send anything.
```

```text
Draft a message to Sarah saying I can meet at 6:30. Show me the destination and text before sending.
```

```text
Add “follow up with the electrician” to Personal reminders tomorrow at 9 AM.
```

```text
Every weekday at 8 AM, check unread Messages in my selected chats and report what needs a response. Never send from the routine.
```

## Development

```bash
swift build
swift test
make check
```

The Swift package has no third-party library dependencies. The native app uses SwiftUI, Network.framework, EventKit, Security/Keychain, ServiceManagement, and the external `imsg` executable.

```text
Sources/GrokBotCore/   MCP transport, tool policy, imsg and EventKit adapters
Sources/GrokBotApp/    Setup, scopes, approvals, status and activity UI
Tests/                 Policy, MCP protocol and HTTP transport tests
plugins/               Grok plugin skill
.grok-plugin/          Marketplace metadata
```

## Current limitations

- The Mac, companion app, Messages.app, and tunnel must remain available for tool calls.
- The bridge handles text sends; attachments and advanced private-API Messages features are intentionally out of scope.
- Cloudflare quick-tunnel URLs change after restart. Use a named tunnel for a permanent setup.
- The bearer token is embedded in the compatibility connector URL because Grok Bot's public custom-connector instructions do not document static custom headers. It can appear in tunnel access logs; rotate it if exposed.
- This release does not turn incoming iMessages into Grok Bot conversations. Grok Bot checks Messages when asked or from a routine.

## License

MIT
