# Contributing

Thanks for helping make Grok Bot safer and easier to use.

## Before opening a pull request

1. Keep changes local-first. New network services need a clear user benefit and explicit opt-in.
2. Never weaken owner checks, group admission, replay protection, or write approvals without a security analysis.
3. Add tests for routing, tool authorization, persistence, or API behavior that changes.
4. Run `make check` on macOS 14 or later.
5. Explain any new macOS entitlement or privacy permission in the pull request.

## Style

- Prefer small SwiftUI views and explicit service protocols.
- Keep model decisions separate from deterministic authorization and mutation code.
- Avoid logging message bodies, reminder contents, credentials, raw API responses, or attachment paths.
- Preserve compatibility with the documented stable `imsg rpc` surface.

By contributing, you agree that your contribution is licensed under the MIT License.
