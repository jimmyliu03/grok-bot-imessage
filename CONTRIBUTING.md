# Contributing

Thanks for helping make Grok Bot Mac Bridge safer and easier to use.

## Before opening a pull request

1. Preserve the split: Grok Bot is the agent; this project is a deterministic Messages/Reminders capability bridge.
2. Treat tool results and inputs as untrusted. Authorization cannot depend on model instructions.
3. Never weaken connector authentication, loopback binding, access scopes, or write approvals without a security analysis.
4. Add tests for MCP behavior, authorization, approval binding, or Apple adapter behavior that changes.
5. Run `make check` on macOS 14 or later.
6. Explain any new entitlement, privacy permission, listener, tunnel, dependency, or data disclosure in the pull request.

## Style

- Prefer small SwiftUI views and explicit service protocols.
- Keep Network.framework parsing, MCP dispatch, deterministic policy, and Apple adapters separate.
- Avoid logging message bodies, reminder contents, connector credentials, tool arguments, or attachment paths.
- Preserve compatibility with documented MCP Streamable HTTP and stable `imsg rpc` surfaces.
- Do not add private Apple APIs or a requirement to disable SIP.

By contributing, you agree that your contribution is licensed under the MIT License.
