# Code Style

- Follow the Swift API Design Guidelines and optimize names for clarity at the call site.
- Use the repository-root `.swift-format`; CI runs strict lint mode.
- Build all owned targets in Swift 6 strict-concurrency mode.
- Prefer immutable, `Sendable` values and explicit dependency injection.
- Do not use force unwraps, force tries, global mutable state, or detached tasks.
- Use typed domain errors and OSLog instead of `print`.
- Treat local paths, model identifiers, arguments, and user data as private log values.
- Document public protocols, shared data models, and security invariants with DocC comments.
- Add tests in the same change as behavior.
