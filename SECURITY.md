# Security policy

## Trust model

Grok Bot Mac Bridge runs with access to highly sensitive local data. The Mac companion is a deterministic capability provider; Grok Bot remains a separate cloud agent. Content returned by a tool necessarily reaches Grok Bot and is subject to the account's Grok Bot/Cursor privacy and retention settings.

The bridge does not upload the whole Messages database or Reminders store. It returns only bounded tool results permitted by the configured chat, recipient, and reminder-list scopes. Those scopes are enforced in Swift outside the model.

Messages and reminder content are untrusted. They can contain prompt-injection attempts. The included skill tells Grok Bot not to execute instructions found in tool results, while deterministic scope checks and optional local write approvals provide the security boundary.

## Network boundary

- The MCP server binds only to IPv4 loopback (`127.0.0.1`).
- Every MCP request requires a random 256-bit token stored with Keychain accessibility `AfterFirstUnlock` so the always-on bridge can restart unattended.
- The token can be supplied as a Bearer header, `X-Grok-Bridge-Token`, query parameter, or path component. The app-generated Grok compatibility URL uses the path form.
- Authentication comparison is constant-time and unauthenticated callers cannot enumerate tools.
- Requests are limited to 1 MiB, require `application/json`, and do not support chunked request bodies.
- Responses disable caching and MIME sniffing. Message bodies, reminder data, tokens, and tool arguments are not logged by the app.

The HTTPS tunnel terminates outside this process. A path token can appear in provider access logs, browser history, screenshots, or copied configuration. Treat the complete connector URL as a credential. Prefer a tunnel account you control, minimize access logging, use a stable named tunnel, and rotate the token after any suspected exposure.

Do not open the bridge port on a router or change the listener to `0.0.0.0`.

## Write boundary

The default `localApproval` mode uses a two-call workflow:

1. A write tool call creates a pending request and returns an approval-required tool error.
2. The user reviews and approves it in the Mac app.
3. The exact same tool name and arguments may execute once within ten minutes.

Changing any argument requires a new approval. Grants are memory-only, consumed once, and lost on restart. `trustGrokBot` mode disables this local boundary and should be used only after configuring and testing Grok Bot approval rules.

Existing-chat sends must target an allowed chat. New-recipient sends follow a separate allowlist unless the user explicitly permits all recipients. Reminder mutations resolve the target's actual EventKit list before executing.

## Messages boundary

`imsg` reads `~/Library/Messages/chat.db` and uses Messages.app AppleScript for basic sends. The bridge resolves `imsg` only from canonical Homebrew Cellar paths whose executable is not group/world-writable. It does not enable private IMCore injection or require disabling System Integrity Protection.

If `imsg` reports a send as uncertain or non-retry-safe, the message service blocks later sends until the bridge is restarted. Inspect Messages before restarting so a retry does not duplicate a delivery.

## Recommended deployment

- Use a dedicated macOS user account on the Mac mini.
- Begin with selected-chat and selected-reminder-list modes.
- Keep new recipients disabled or tightly allowlisted.
- Keep local write approval enabled.
- Keep the app and tunnel under launch supervision and enable FileVault.
- Review Full Disk Access, Automation, Reminders, Login Items, tunnel logs, and Grok connector access periodically.
- Rotate the connector token when removing a Bot, changing operators, or suspecting exposure.
- For unattended routines, automate preparation and summaries, not contacting people or deletion.

## Reporting a vulnerability

Do not open a public issue for an unpatched vulnerability. Use GitHub private vulnerability reporting with reproduction steps, affected versions, impact, and suggested mitigation. Maintainers should acknowledge reports within seven days.

## Supported versions

Until 1.0, only the latest commit on `main` is supported.
