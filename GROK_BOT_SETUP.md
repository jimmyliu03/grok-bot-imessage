# Add the Mac Bridge to Grok Bot

The integration has two pieces:

1. The macOS companion supplies authenticated MCP tools backed by Messages and EventKit.
2. The Grok plugin skill teaches Grok Bot how to use those tools safely.

The Mac app does not call the xAI API and does not run a second agent. Grok Bot remains the agent.

## 1. Prepare the Mac mini

Install and open the companion:

```bash
git clone https://github.com/jimmyliu03/grok-bot-imessage.git
cd grok-bot-imessage
make install
open /Applications/GrokBot.app
```

Complete the in-app setup:

- Sign Messages.app into the Apple account that should send messages.
- Install `imsg` when prompted.
- Grant Full Disk Access to the app, then quit and reopen it.
- Grant Reminders Full Access.
- Select the chats, new recipients, and reminder lists Grok Bot may access.
- Keep local approval enabled for writes unless you have configured and tested Grok Bot approval rules.
- Enable launch at login and choose **Start Bridge**.

For SMS, the Mac normally needs an associated iPhone with **Settings → Apps → Messages → Text Message Forwarding** enabled for this Mac.

## 2. Give the connector a public HTTPS address

Grok's cloud must be able to reach the MCP endpoint. The companion listens only on `127.0.0.1`, so use a tunnel rather than opening a router port.

For a temporary test URL:

```bash
brew install cloudflared
cloudflared tunnel --url http://127.0.0.1:29333
```

Copy the generated `https://…trycloudflare.com` base URL into **Mac Bridge → Dashboard → Public HTTPS tunnel URL**. Then choose **Copy Private Connector URL**. The copied value resembles:

```text
https://example.trycloudflare.com/mcp/A_PRIVATE_256_BIT_TOKEN
```

The token is stored in macOS Keychain. The complete URL is a secret and may appear in tunnel access logs. Use a named stable Cloudflare Tunnel or another authenticated stable tunnel for an always-on installation. Never commit or publish the private URL.

## 3. Add the connector to Grok Bot

1. Open [grok.com/connectors](https://grok.com/connectors).
2. Choose **New Connector**, then **Custom**.
3. Name it **Grok Bot Mac Bridge**.
4. Paste the private connector URL copied from the app.
5. Save it and allow Grok to discover the tools.
6. Open the Grok Bot desktop app and go to **Settings → Plugins → Yours**.
7. Open **Grok Bot Mac Bridge**, enable the connector for the intended Bot, and enable only the tools that Bot needs.

If a team policy blocks it, an administrator must allow the connector's public tunnel host under the team's MCP configuration.

Test in a one-to-one Bot conversation:

```text
List the Apple reminder lists available through my Mac Bridge. Do not change anything.
```

Then test Messages without sending:

```text
List my unread Messages chats through the Mac Bridge. Do not send anything.
```

Finally, test a write against a safe recipient. With local approval enabled, the first call is blocked. Approve it in the Mac app and tell Grok Bot to retry the exact action.

## 4. Add the safety skill

This repository is also a Grok plugin marketplace. The plugin lives at `plugins/grok-bot-mac-bridge` and its skill at `skills/apple-messages-reminders/SKILL.md`.

For Grok Build, install it from the repository:

```bash
grok plugin marketplace add jimmyliu03/grok-bot-imessage
grok plugin install grok-bot-mac-bridge --trust
grok inspect
```

In Grok Bot, open **Settings → Plugins → Yours** and enable the installed **Apple Messages and Reminders** skill for the Bot. If custom marketplace installation is not exposed on your account yet, open the skill file from this repository, paste its contents into a one-to-one Bot conversation, and ask Grok Bot to save it as a private skill named **Apple Messages and Reminders**. Then enable it under **Settings → Plugins → Yours**.

The skill deliberately requires destination confirmation, treats message/reminder content as untrusted, minimizes reads, and handles the companion's one-time local approval workflow.

## 5. Use it

Examples:

```text
Check whether the plumber replied in Messages and summarize the latest exchange. Do not send anything.
```

```text
Draft a reply to Sarah saying I can meet at 6:30. Show it to me before sending.
```

```text
Add “follow up with the electrician” to my Personal reminders for tomorrow at 9 AM.
```

```text
Every weekday at 8 AM, check unread Messages in the selected chats and report anything that needs my response. Never send a message from this routine.
```

## Troubleshooting

- **Connector offline:** keep the Mac app, `cloudflared`, and the Mac mini running; verify `http://127.0.0.1:29333/health` locally.
- **401 Unauthorized:** recopy the private connector URL. If you rotated the token, replace the old Grok connector.
- **Messages unreadable:** grant Full Disk Access, quit the app completely, and reopen it.
- **Send fails:** open Messages.app, confirm the account can send manually, and review Automation permissions.
- **SMS fails:** verify Text Message Forwarding and use `service: auto` or `service: sms`.
- **Reminder blocked:** grant Full Access and select the target list in the companion.
- **Local approval repeats:** approve the pending request, then retry without changing any tool argument within ten minutes.
