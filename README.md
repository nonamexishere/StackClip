# StackClip

A tiny macOS menu bar utility that adds two missing clipboard features:

- **Append copy** — press **⌘⇧C** to copy the current selection *onto the end* of what's already on your clipboard, instead of replacing it. Collect snippets from several places, paste them all at once.
- **Clipboard history** — like Windows' Win+V. The menu bar icon lists your last 50 copied texts; click one to put it back on the clipboard. History survives restarts.

Passwords are safe: copies marked as concealed (the convention used by password managers, `org.nspasteboard.ConcealedType`) are never recorded.

## Build & run

Requires macOS 13+ and Xcode (or the Swift toolchain).

```sh
swift build -c release
.build/release/StackClip
```

Or during development: `swift run StackClip`.

## Accessibility permission

Append copy works by simulating ⌘C, which macOS gates behind the **Accessibility** permission. The first time you press ⌘⇧C you'll be prompted; grant it in **System Settings → Privacy & Security → Accessibility**, then restart the app.

Note: when you launch StackClip from a terminal, macOS attributes the permission to your *terminal app* — grant it there and it persists across rebuilds. If you run the binary directly, the grant is tied to the binary's signature and resets on every rebuild.

## Usage

1. Copy something normally (⌘C).
2. Select more text anywhere and press **⌘⇧C** — it's appended to the clipboard (joined with a newline).
3. Paste (⌘V) to get everything at once.
4. Click the clipboard icon in the menu bar to browse history; click an entry to restore it.

## Roadmap

- [ ] Proper `.app` bundle + signed releases (Homebrew cask)
- [ ] Configurable separator (newline / space / custom)
- [ ] Configurable hotkey
- [ ] Paste-on-click option for history items

## License

[MIT](LICENSE)
