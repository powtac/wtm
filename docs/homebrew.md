# Homebrew Cask

WTM is a native, signed macOS application distributed as an Apple Silicon DMG. It belongs
in Homebrew Cask, not Homebrew Formula: a Formula is for command-line software built from
source; a Cask installs an application bundle.

The source definition is [`packaging/homebrew/Casks/wtm.rb`](../packaging/homebrew/Casks/wtm.rb).
It is intentionally pinned to the public `v0.5.0` release. Do not point a Cask at `main`,
an unpublished tag, or a mutable download URL.

## Published tap

The official public repository is [powtac/homebrew-wtm](https://github.com/powtac/homebrew-wtm),
published on 2026-09-05. Homebrew maps the tap name `powtac/wtm` to that repository.
The Cask is stored there as `Casks/wtm.rb`; this repository retains the source copy.

```sh
brew tap powtac/wtm
brew install --cask wtm
```

An explicit third-party tap is deliberate: tap code can run with the user's privileges.
Users should trust only the requested Cask, not an unrelated whole tap.

## Verification — 2026-09-09

Version 0.5.0's Cask pins the published DMG SHA-256
`1b7b5400fd11de5dfd06806ddfbb567afe6d90722b8282b3b39e9a0fdeb206c1`.
The downloaded digest and release manifest match; GitHub artifact attestation verification
passes. Strict online Cask audit, isolated install, strict/deep code-signature validation,
notarized Gatekeeper acceptance, staple validation and uninstall pass. Livecheck reports
current/latest 0.5.0, not outdated. The public tap update is commit `71eda32`.
Full local log: `build/homebrew-release-verify.log`. See the
[2026-09-09 audit](audits/adapter-release-review-2026-09-09.md).

## Historical verification — 2026-09-08

Version 0.4.3's public tap, local source Cask and published DMG digest match.
`brew audit --strict --online --cask powtac/wtm/wtm` passes. Installation to
`build/homebrew-release-smoke` passes strict/deep signature verification, Gatekeeper and
staple validation. Uninstall removes that test application. Full local logs:
`build/homebrew-release-audit.log` and `build/homebrew-release-smoke.log`.

## Historical verification — 2026-09-05

- `brew audit --strict --online --cask powtac/wtm/wtm` passes.
- Installation to an isolated `--appdir` succeeds; the installed application passes strict
  code-signature and notarized Gatekeeper checks. Uninstall removes that test application.
  The existing `/Applications/WTM.app` is not replaced by the smoke test.
- `brew livecheck --cask --json powtac/wtm/wtm` reports current/latest 0.4.2, not outdated.
- `brew audit --new` reports only the GitHub notability threshold (fewer than 30 forks,
  30 watchers, and 75 stars). That blocks upstream submission, not this independent tap.
  Do not describe the upstream admission check as passed.

For a future update, validate from the installed tap:

```sh
brew audit --strict --online --cask powtac/wtm/wtm
brew install --cask powtac/wtm/wtm
brew uninstall --cask wtm
```

## Release procedure

1. Run the normal WTM release gates and publish the signed, notarized GitHub Release from
   an exact `vMAJOR.MINOR.PATCH` tag. The release must contain the final
   `WTM-<version>-arm64.dmg` and its checksum manifest.
2. Update the README's download link, installation commands, and displayed version to
   the newly published DMG. Keep this documentation update in the same release change.
3. Confirm the release asset and checksum from GitHub:

   ```sh
   version=0.5.0
   gh release view "v$version" --repo powtac/wtm
   curl -fsSL "https://github.com/powtac/wtm/releases/download/v$version/WTM-$version.sha256"
   ```

4. Update `version`, the DMG URL pattern if the asset name changes, and `sha256` in
   `Casks/wtm.rb`. The SHA must be the checksum of the final published DMG, not the app,
   zip, or an intermediate disk image.
5. Run the audit and install/uninstall smoke test above. Also check that Homebrew sees the
   new release:

   ```sh
   brew livecheck --cask --json --quiet wtm
   ```

6. Commit and push the Cask update to `powtac/homebrew-wtm`. Tagging the WTM repository
   alone does not update Homebrew.
7. Immediately after every published release, raise `MARKETING_VERSION` in
   `Config/Base.xcconfig` by exactly one patch version (`0.0.1`). The next code change
   must therefore already carry the next version; after `0.5.0`, set it to `0.5.1`.

## Upstreaming later

Once the tap and release cadence are stable, submit the Cask to
[`Homebrew/homebrew-cask`](https://github.com/Homebrew/homebrew-cask). The upstream Cask
must still point to the immutable GitHub Release asset and pass the current Cask audit and
acceptance rules. Keep the tap as the controlled fallback while upstream review is open.
