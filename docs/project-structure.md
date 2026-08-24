# Project Structure

```text
WTM.xcodeproj                    Thin macOS app and test targets
App/WTMApp                      SwiftUI shell and composition root
App/WTMAppTests                 App integration tests
App/WTMAppUITests               XCUITest smoke tests
Packages/WTMKit                 Domain, contracts, inventory, actions, persistence, adapters
Config                          Versioned build settings; Local.xcconfig is ignored
docs                            Contributor-facing English documentation
scripts                         Local equivalents of required CI checks
.github                         Workflows and community configuration
```

Folders use Xcode file-system-synchronized groups. Disk and navigator structure must stay
aligned. New targets require one clear responsibility, inward-only dependencies, an owner,
and tests.
