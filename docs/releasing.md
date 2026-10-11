# GitHub releases

CopyShelf is distributed as an unsigned community beta on GitHub. ZIP and DMG files include an ad-hoc signed app with Apple Silicon and Intel binaries. There is no Developer Program signing or notarization workflow.

## Prepare

```sh
swift test
python3 -m unittest discover -s Tests/ReleaseTests -v
bash Scripts/build-app.sh --universal
bash Scripts/package-release.sh
```

The app is in `dist/build/CopyShelf.app`. The package script checks its version, architectures, local signature, and ZIP structure, then creates `CopyShelf-VERSION-macOS-unsigned.zip`, a DMG, and SHA-256 files. The DMG has an Applications link and installation instructions. No installed app is replaced.

Before publishing, open the packaged app on another Mac. Check text and image history, search, chosen shortcuts, manual and automatic paste, pause, clear, and login launch. Test Intel and the oldest supported macOS before claiming those environments are verified.

Keep local logs, benchmark data, debug output, and development notes out of Git. `.gitignore` excludes them; it also excludes clipboard history and credential files. Public source contains the product, tests, and user documentation. Check the staged file list before committing.

## Publish from a terminal

Sign into GitHub with `gh auth login`. Create a public repository only if it does not already exist:

```sh
gh repo create CopyShelf --public --source . --remote origin --push
```

After tests and packaged-app checks pass, publish the current beta:

```sh
gh release create v0.3.1 \
  dist/CopyShelf-0.3.1-macOS-unsigned.zip \
  dist/CopyShelf-0.3.1-macOS-unsigned.zip.sha256 \
  dist/CopyShelf-0.3.1-macOS-unsigned.dmg \
  dist/CopyShelf-0.3.1-macOS-unsigned.dmg.sha256 \
  --target main --prerelease --title "CopyShelf 0.3.1" \
  --notes-file docs/release-notes-0.3.1.md
```

Use a GitHub noreply address for commit authors if you do not want your personal email to be public. Build commands call Bash explicitly, so they work even when a web upload removes shell-script executable permissions.

## GitHub Actions

**Build and test** runs on main and pull requests, tests source, and uploads unsigned build artifacts. **Publish community beta** is manual. It checks the source version, rebuilds and tests the app, then publishes ZIP, DMG, and checksums as a prerelease. It uses GitHub's repository token and needs no external credentials. An existing release is not overwritten.

For another version, update `Resources/Info.plist`, increase its build number, and add the matching release-notes file. Review the result before running the publishing workflow.

## Installation and updates

Users install the app in Applications and grant clipboard and automatic-paste permissions through macOS. If they decide to run a blocked download, Apple's [opening guide](https://support.apple.com/en-us/102445) describes the per-app exception. Never tell users to disable Gatekeeper globally or strip security attributes.

To update, quit CopyShelf and replace the app in the same location. Saved history, pause choice, and chosen shortcut remain in the user's Library. An unsigned update can require permissions again; GitHub distribution cannot promise continuity. The app has no automatic updater.
