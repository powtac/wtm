# Homebrew Cask

WTM is a native, signed macOS application distributed as an Apple Silicon DMG. It belongs
in Homebrew Cask, not Homebrew Formula: a Formula is for command-line software built from
source; a Cask installs an application bundle.

The source definition is [`packaging/homebrew/Casks/wtm.rb`](../packaging/homebrew/Casks/wtm.rb).
It is intentionally pinned to the public `v0.4.0` release. Do not point a Cask at `main`,
an unpublished tag, or a mutable download URL.

## Publish the tap

Create a public GitHub repository named `homebrew-wtm`. Homebrew maps the user-facing tap
name `powtac/wtm` to `powtac/homebrew-wtm`. Copy the Cask into that repository as
`Casks/wtm.rb`, then validate it from the tap checkout:

```sh
brew update
brew audit --new --cask --tap powtac/wtm
brew install --cask powtac/wtm/wtm
brew uninstall --cask wtm
```

Users then install the tap explicitly:

```sh
brew tap powtac/wtm
brew install --cask wtm
```

An explicit third-party tap is deliberate: tap code can run with the user's privileges.
Users should trust only the requested Cask, not an unrelated whole tap.

## Release procedure

1. Run the normal WTM release gates and publish the signed, notarized GitHub Release from
   an exact `vMAJOR.MINOR.PATCH` tag. The release must contain the final
   `WTM-<version>-arm64.dmg` and its checksum manifest.
2. Confirm the release asset and checksum from GitHub:

   ```sh
   version=0.4.0
   gh release view "v$version" --repo powtac/wtm
   curl -fsSL "https://github.com/powtac/wtm/releases/download/v$version/WTM-$version.sha256"
   ```

3. Update `version`, the DMG URL pattern if the asset name changes, and `sha256` in
   `Casks/wtm.rb`. The SHA must be the checksum of the final published DMG, not the app,
   zip, or an intermediate disk image.
4. Run the audit and install/uninstall smoke test above. Also check that Homebrew sees the
   new release:

   ```sh
   brew livecheck --cask --json --quiet wtm
   ```

5. Commit and push the Cask update to `powtac/homebrew-wtm`. Tagging the WTM repository
   alone does not update Homebrew.

## Upstreaming later

Once the tap and release cadence are stable, submit the Cask to
[`Homebrew/homebrew-cask`](https://github.com/Homebrew/homebrew-cask). The upstream Cask
must still point to the immutable GitHub Release asset and pass the current Cask audit and
acceptance rules. Keep the tap as the controlled fallback while upstream review is open.
