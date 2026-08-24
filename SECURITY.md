# Security policy

## Trust model

Grok Bot runs with access to highly sensitive local data. A configured owner can ask it to read Messages and Reminders, and approved write tools can contact people or change reminder data. The xAI API necessarily receives the owner's bot prompts, selected tool results, and bounded per-chat session context. Approval continuations use the stateful Responses API (`store: true`), so API content may be retained under the xAI account's data controls, typically for up to 30 days. Operators who require Zero Data Retention should not run this release.

The bot does not upload the whole Messages database. Its local watch sees new-message content and metadata so deterministic routing rules can be enforced, but unauthorized messages are never sent to xAI. For an authorized turn, xAI receives the triggering message; additional Messages content is sent only if Grok Bot invokes a bounded history tool. Non-owner sessions receive no personal tool definitions.

Inbound message content is untrusted. The system prompt tells Grok not to treat content read from Messages or Reminders as higher-priority instructions, but model-level prompt injection can never be eliminated completely. Owner checks and deterministic write approvals are enforced in Swift outside the model.

## Important deployment guidance

- Prefer a dedicated iMessage account and a dedicated macOS user account.
- Keep direct messages on allowlist mode and group support disabled unless needed.
- Keep “Always ask” write approvals enabled.
- Install `imsg` only from its documented Homebrew tap. Grok Bot uses only canonical Homebrew paths and displays the resolved executable; review it after upgrades.
- Do not expose the Mac through port forwarding. Grok Bot and `imsg rpc` open no listening port.
- Review Full Disk Access, Automation, Reminders, and Login Items permissions periodically.
- Revoke the xAI API key immediately if the Mac or account is compromised.

## Reporting a vulnerability

Do not open a public issue for an unpatched vulnerability. Use GitHub's private vulnerability reporting feature on this repository with reproduction steps, affected versions, impact, and any suggested mitigation. Maintainers should acknowledge reports within seven days.

## Supported versions

Until a 1.0 release, only the latest commit on `main` is supported.
