# Contributing

Thank you for improving What The Model. Discuss large behavior, architecture, security,
or adapter changes in an issue before implementation.

## Development

1. Use macOS 15 or later and the Xcode version documented in `README.md`.
2. Create `Config/Local.xcconfig` from the example only when local signing is required.
3. Make a focused change with tests.
4. Run `./scripts/test` before opening a pull request.
5. Complete every applicable pull-request checklist item.

Swift code follows [the code style](docs/code-style.md). Architecture dependencies must
follow [the project structure](docs/project-structure.md).

## Adapter contributions

Start with [the adapter guide](docs/adapters.md). Open an adapter proposal before code.
Each adapter must declare its capability class, evidence hierarchy, permissions, failure
modes, fixtures, and ownership assumptions. Phase boundaries are enforced: a storage
scanner does not gain deletion or process-start capabilities.

Do not submit downloaded model weights, private filesystem paths, tokens, cookies, SSH
material, signing identities, or third-party data without a compatible redistribution
license.

## Commit and review policy

Use imperative, scoped commit messages. Keep mechanical formatting separate when it
would obscure behavior. Reviews prioritize correctness, privacy, least privilege,
accessibility, and maintainable native macOS behavior over convenience.
