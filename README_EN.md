# ClipNest Native

[简体中文](README.md) | English

ClipNest Native is the native AppKit edition for macOS.

Current version: `0.7.3`. It supports Apple Silicon and requires macOS 13 or later.

The repository also includes a Windows/Linux MVP under `cross-platform/`, built with Tauri. On Windows and Linux, `Alt+V` opens the quick panel while `Ctrl+V` remains the normal system paste shortcut. All three platforms are built and verified on native GitHub Actions runners.

## Why ClipNest?

In the AI era, we constantly move images and prompts between ChatGPT, image-generation tools, code editors, documents, and messaging apps. The same prompt, reference image, document link, or canned response may be copied many times a day, while a traditional clipboard remembers only the most recent item.

ClipNest solves that small but recurring problem. It puts recent clipboard items and frequently used material in a lightweight panel near your current input position, so you can select and paste without leaving your workflow. The management window stays out of the way until you need to organize content into your own groups.

- Automatically collect recent clipboard items and keep them locally.
- Organize prompts, images, links, and reusable replies into custom groups.
- Navigate and paste entirely from the keyboard in a compact five-row panel.
- Use platform-appropriate shortcuts without replacing normal paste behavior.
- Keep clipboard data on your device; nothing is uploaded.

## Download and Run

Download the package for your platform from [GitHub Releases](https://github.com/lyc403223157-source/ClipNest/releases/latest):

- macOS: `ClipNest-0.7.3-macos-arm64.zip`
- Windows: the `.exe` installer
- Ubuntu/Debian Linux: the `.deb` package

On macOS, unzip the archive and move `ClipNest.app` to Applications. This preview is ad-hoc signed and has not yet been notarized with an Apple Developer ID. If Gatekeeper blocks the first launch, right-click the app in Finder and choose **Open**.

## Current Behavior

- ClipNest launches as a menu bar app and does not open the management window automatically.
- Copied text and images are added to the built-in **Recent** group with no item limit.
- Screenshots are supported on macOS. Use `Control + Shift + Command + 3` to copy the full screen or `Control + Shift + Command + 4` to copy a selected area; ClipNest stores the image and displays a thumbnail.
- Custom groups have no item limit. Text or images from the current clipboard can be added, renamed, edited, or deleted in the management window.
- A selected item in **Recent** can be moved through **Add to Group…**, using an existing group or creating a new one. Once archived, the item is removed from **Recent**.
- The management window follows macOS System Settings conventions: a unified transparent title bar, vibrancy sidebar, SF Symbols, grouped cards, and borderless content lists.
- `Command+V` always remains the standard macOS paste shortcut and is never intercepted by ClipNest.
- In another app's input field, press `Control+V` to show the quick panel above the focused field, or below it when there is not enough space.
- A one-time, non-blocking guide appears the first time the quick panel is opened and disappears after the first successful paste.
- After selecting an item, ClipNest restores focus to the original input field and pastes at the current cursor or selection. The target app must support image paste for image items.
- Use Left/Right to switch groups, Up/Down to select an item, Return to paste, and Esc to close. Number keys 1–5 can also paste the corresponding visible item.
- The content area always uses a five-row height. Longer lists use the native macOS scrollbar.
- Every opening starts on the first item in **Recent**; the previous group and item selection are not remembered.
- The quick panel uses AppKit's native `NSVisualEffectView` popover material, continuous corners, system accent color, and WindowServer-managed `NSPanel.hasShadow` shadow.
- Multiline text is compressed to a single-line preview with `↵`, while the original line breaks are preserved when pasted.
- Text keeps its original clipboard content and name unless the user explicitly renames it. Images display their real pixel dimensions.
- Clicking outside closes the panel while allowing the external click to continue to the target app.
- The panel follows macOS menu dismissal rules: it closes after clicking an item or pressing Return, and also closes on Esc, an outside click, an app switch, or pressing the invocation shortcut again.

## First Launch on macOS

Opening the panel with `Control+V` does not itself require Input Monitoring permission. Locating the focused field and pasting back into it require Accessibility permission.

ClipNest does not request this permission unexpectedly at startup. It explains and requests access the first time you press `Control+V`. The management window can also open **System Settings → Privacy & Security → Accessibility** directly. If ClipNest is missing from the list, click the **+** button and select `ClipNest.app`. Move the app to Applications before granting access so that relocating it later does not invalidate the permission.

All text records and screenshots remain in `~/Library/Application Support/ClipNest`. Deleting an image item or group also removes its corresponding local image file.

## Build Locally on macOS

The native edition uses AppKit and ApplicationServices and can be built with Xcode or `swiftc` from a matching macOS SDK.

Run the build script from the repository root:

```sh
./build.sh
```

The resulting app is written to `dist/ClipNest.app`. The current script targets Apple Silicon and macOS 13 or later.

Local preview builds must retain a stable designated requirement. Otherwise, macOS may show Accessibility as enabled while rejecting a newly rebuilt binary:

```sh
codesign --force --deep --sign - --requirements '=designated => identifier "com.clipnest.native"' ClipNest.app
```

A production release should use a stable Apple Developer ID signature and notarization.

## Windows and Linux

The cross-platform implementation is in [`cross-platform/`](cross-platform/). It uses Tauri 2, Rust, and the system WebView.

- `Alt+V` opens the quick panel; `Ctrl+V` remains direct paste.
- Windows uses a low-level keyboard hook and does not require macOS-style Accessibility permission.
- Linux currently targets X11. Global shortcuts and simulated input on Wayland depend on the desktop environment and its security policy.
- The current Windows/Linux MVP supports text and URLs. Screenshot history is currently available in the native macOS edition.

To test the cross-platform code locally:

```sh
cd cross-platform
npm ci
npm test
npm run check
```

After installing Rust and the platform-specific [Tauri 2 prerequisites](https://v2.tauri.app/start/prerequisites/), build it with:

```sh
npm run tauri build
```

GitHub Actions runs tests and native builds on macOS, Windows, and Ubuntu. Release artifacts are published only after all three platform jobs succeed.
