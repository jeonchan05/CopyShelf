<img src="docs/images/icon.png" width="88" alt="CopyShelf icon">

# CopyShelf

A small clipboard history app for macOS. Open your history with a shortcut, search for an earlier copy, choose it with the arrow keys, and press Enter to paste it into the app you were using.

CopyShelf keeps text and copied images, including screenshots. It runs in the menu bar and saves history on your Mac. No account, analytics, or network connection is used by the app.

[한국어 안내](docs/README.ko.md) · [Downloads](https://github.com/jeonchan05/CopyShelf/releases)

## Install

Requires macOS 13 or later. The download includes Apple Silicon and Intel binaries; Intel runtime and macOS 13 still need testing.

1. Download the `macOS-unsigned.dmg` from GitHub Releases.
2. Open it and drag CopyShelf to Applications. Open that copy.
3. If macOS blocks the app because it cannot verify the developer, review the source and download origin. If you decide to run it, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. Apple's [opening guide](https://support.apple.com/en-us/102445) describes this per-app exception.
4. Enable **CopyShelf** in **Privacy & Security → Accessibility** for automatic paste. On newer macOS, this page may be called **Device Control and Data Access**. If macOS asks about clipboard reads, choose **Always Allow** to record in the background.

This is an unsigned community beta, without Apple notarization. The app uses an ad-hoc integrity signature. GitHub hosting does not remove macOS security prompts, and an update can require granting permissions again. The ZIP download contains the same app as the DMG. Check the supplied SHA-256 file if you want to verify your download.

## Use it

Recording starts automatically when the app is running. Open history with **Option-Command-V** by default, or click its menu bar icon.

- Type to search text, image categories, dimensions, or the source app name.
- **Up / Down** selects an item; **Enter** pastes; **Escape** closes history.
- **Command-C** copies the selected item for manual paste. If search text is highlighted, it copies that selection instead.
- Double-click an item to paste it.

The history window contains search, the list, a short status line, and a Settings button. Open Settings with the gear or **Command-Comma**.

In Settings, click **Open history**'s shortcut and press a new combination that includes **Command or Control**. Escape cancels. The choice is remembered after restarting. If registration fails, the previous shortcut stays in place. Command-V is reserved for paste. Key labels use the physical Mac key positions.

Settings also has background recording, launch at login, automatic-paste permissions, and clear history. Right-click the menu bar icon for quick pause, settings, or quit. Pause is remembered after restarting; closing history keeps the app running. Launch at login is optional and may need approval in macOS Login Items settings.

## Images

Use **Control-Shift-Command-4** to capture an area to the clipboard, or **Control-Shift-Command-3** for the whole screen. CopyShelf reads the copied image and needs no Screen Recording permission. It does not import captures saved as files or files copied in Finder. [Apple's screenshot guide](https://support.apple.com/en-us/102646) lists the shortcuts.

Copied images show a thumbnail and dimensions. Search for `image`, `screenshot`, `이미지`, a size such as `1920x1080`, or the source app. There is no OCR. Paste images into a destination that accepts them, such as a rich-text document or message composer.

## Privacy and limits

History stays in `~/Library/Application Support/CopyShelf/history.json` as unencrypted JSON with owner-only file permissions. Images are stored as base64. Keep up to 200 distinct items; copying one again moves it to the top. Text keeps its whitespace and is limited to 64 KiB per item.

PNG, TIFF, JPEG, HEIC/HEIF, GIF, and BMP clipboard data is converted to a static PNG. Input is limited to 32 MiB, stored PNG to 12 MiB per image, resolution to 32 million pixels and 16,384 pixels per edge. Stored images share a 32 MiB budget. Animated images keep the first frame. Files, rich-text formatting, animation playback, and full HDR fidelity are outside this version's scope.

CopyShelf skips marked sensitive items, some password managers, and copies while Secure Input is active. These filters depend on the source app; an unmarked password, API key, or private screenshot can still be saved. Pause before copying something you do not want stored.

**Settings → Clear history** removes saved text and images after confirmation. It preserves the current clipboard and reports deletion failures. It does not erase backups or securely overwrite old storage blocks. Normal quit flushes pending saves; a sudden crash can lose the most recent pending copies.

## If paste still asks for permission

Quit and reopen CopyShelf. If its permission switch is enabled but automatic paste still asks, remove only CopyShelf's stale entry from the permission page, add the exact app in Applications, enable it, and reopen that copy. Unsigned updates can change the identity macOS remembers. Without automatic-paste permission, use Command-C and paste manually with Command-V.

If another copy changes the clipboard while an automatic paste is pending, CopyShelf cancels the paste. Secure text fields reported through Accessibility use manual paste.

## Build

Use Swift 6.0 or later with Apple's developer tools:

```sh
swift test
python3 -m unittest discover -s Tests/ReleaseTests -v
bash Scripts/build-app.sh --universal
bash Scripts/package-release.sh
open dist/build/CopyShelf.app
```

The scripts create the app in `dist/build` and unsigned ZIP/DMG files in `dist`. They leave installed apps alone. To view generated sample history without reading or saving your clipboard:

```sh
open -n dist/build/CopyShelf.app --args --demo
```

The project uses AppKit and Carbon and has no third-party runtime dependencies. Automated tests use generated data and isolated storage. The repository excludes local logs, measurements, development notes, history files, and build output.

[Architecture](docs/architecture.md) · [Publishing guide](docs/releasing.md) · [Security](SECURITY.md) · [MIT license](LICENSE)
