# Product screenshots

Generate English macOS screenshots and prepare the selected ten images locally:

```sh
bundle install
./scripts/run-logged build/screenshots-run.log bundle exec fastlane mac prepare_screenshots
```

`run-logged` requires Python 3. It waits for the command locally, writes complete stdout
and stderr to the log, and reports the exit code and log path when the command finishes.
On failure it also prints the last 20 lines, limited to 300 characters each. It preserves
the command's exit code and forwards interruption signals to its process group.
The adjacent `.lock` file prevents concurrent wrapper runs using the same log path.
Keep the original tool session while it runs; no additional status polling is needed.
The same wrapper can run the regular checks:

```sh
./scripts/run-logged build/test-run.log ./scripts/test
```

The lane stops existing WTM processes, then runs the `WTMAppUITests` target against the
native macOS destination. Tests use
isolated settings namespaces and generated model fixtures; they do not delete real models
or start a model runtime. Named XCTest attachments are exported with `xcresulttool`.
The captures include fixture paths and machine-specific Settings values; they are local
review artifacts. No simulator, copied snapshot helper, runner-cache access, or `HOME`
override is required.
Coverage is disabled only for this capture lane; regular test gates retain coverage.

Outputs under ignored `build/`:

| Output | Purpose |
|---|---|
| `screenshots/en-US/` | Original application-window PNGs |
| `screenshots.xcresult` | UI test results and original screenshot attachments |
| `screenshot-logs/` | Xcode and Fastlane test reports |
| `app-store-screenshots/en-US/` | Selected ten opaque PNGs, 1440 × 900 |

Preparation requires ImageMagick (`magick`). It preserves aspect ratio, avoids upscaling,
and centers each window on an opaque background after resetting PNG canvas metadata. Missing selected screenshots fail the
lane. Each capture/prepare run replaces its previous generated output.

To capture only one UI test while iterating:

```sh
./scripts/run-logged build/screenshots-run.log bundle exec fastlane mac screenshots only_testing:WTMAppUITests/WTMAppUITests/testSettingsSectionsForScreenshots
```

`mac upload_screenshots` is a separate external action that generates the complete set and
replaces screenshots on an editable App Store Connect version. It requires the relevant
App Store account/API credentials. Preparing images does not upload them or make the
current application an App Store build: [ADR-002](decisions/ADR-002-direct-distribution.md)
continues to define direct distribution as the shipping product profile.

## UI test interruptions

macOS system dialogs can intercept clicks even when WTM controls are present in the
accessibility tree. Dismiss such dialogs manually before running capture. The settings
capture test stops on its first failed assertion. A failed run is not a verified screenshot
set, and existing prepared images must not be mistaken for that run's output.
