fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac screenshots

```sh
[bundle exec] fastlane mac screenshots
```

Generate product and settings screenshots from macOS UI tests

### mac prepare_screenshots

```sh
[bundle exec] fastlane mac prepare_screenshots
```

Generate and prepare ten screenshots locally without uploading

### mac upload_screenshots

```sh
[bundle exec] fastlane mac upload_screenshots
```

Upload the selected App Store-ready screenshots to the editable App Store version

### mac preflight

```sh
[bundle exec] fastlane mac preflight
```

Check that the macOS distribution toolchain is available

### mac validate

```sh
[bundle exec] fastlane mac validate
```

Validate release scripts and workflow gates without signing or notarizing

### mac build

```sh
[bundle exec] fastlane mac build
```

Build, sign, notarize, staple, and verify WTM release artifacts

### mac release

```sh
[bundle exec] fastlane mac release
```

Run validation and create locally verified release artifacts

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
