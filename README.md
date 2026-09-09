# TermX

TermX is a native-feeling terminal emulator for macOS, built with Electron, xterm.js, Swift, and Node.js native addons.

> [!WARNING]
> TermX is currently alpha software. Features may change, and unexpected behavior may occur.

## Features

- Native macOS window appearance
- Native macOS tab management
- Multiple terminal tabs and windows
- Terminal output search
- Custom shell support
- Login shell option
- Configurable font family, size, and line height
- Bar, block, and underline cursor styles
- Optional blinking cursor
- Configurable scrollback history
- Adjustable window opacity
- Custom terminal colors
- True-color terminal support
- Responsive terminal resizing

## Download

Download the latest alpha release from the [GitHub Releases](https://github.com/Saksham-245/TermX/releases) page.

Current release:

- [TermX v1.0.0 Alpha 1](https://github.com/Saksham-245/TermX/releases/tag/v1.0.0-alpha.1)
- Platform: macOS
- Architecture: Apple Silicon (`arm64`)
- Format: ZIP

### Verify the download

SHA-256 for `TermX-v1.0.0-alpha.1-macos-arm64.zip`:

```text
9aaa84e65684c81da5b709741b4897666685cc4723570794907246389d8909ff
```

Verify it with:

```bash
shasum -a 256 TermX-v1.0.0-alpha.1-macos-arm64.zip
```

## Installation

1. Download the ZIP from the [latest release](https://github.com/Saksham-245/TermX/releases).
2. Extract the ZIP.
3. Move `TermX.app` into your `Applications` folder.
4. Open TermX.

The current alpha build is ad-hoc signed and is not Apple-notarized. If macOS blocks it, right-click `TermX.app`, select **Open**, and confirm that you want to launch it.

## Keyboard shortcuts

| Action                 | Shortcut |
| ---------------------- | -------- |
| New tab                | `⌘ T`    |
| New window             | `⌘ N`    |
| Close tab or window    | `⌘ W`    |
| Open settings          | `⌘ ,`    |
| Search terminal output | `⌘ F`    |

TermX also integrates with native macOS window tab commands.

## Settings

Open **TermX → Settings** to configure:

- Font family
- Font size
- Line height
- Cursor style and blinking
- Scrollback lines
- Shell path
- Login shell behavior
- Window opacity
- Foreground and background colors
- Cursor and selection colors
- ANSI terminal colors

Changes are applied to open terminal windows automatically.

## Development

### Requirements

- macOS
- Apple Silicon Mac
- Node.js and npm
- Xcode with the command-line tools
- Swift toolchain

Accept the Xcode licence before building:

```bash
sudo xcodebuild -license accept
```

### Install dependencies

```bash
npm install
```

### Build and run

```bash
npm start
```

This builds the native macOS bridge, bundles the renderer, and launches Electron.

### Build only

```bash
npm run build
```

### Build the native macOS components

```bash
npm run build:native:macos
```

### Package the application

```bash
npm run pack
```

The packaged application is written to:

```text
release/TermX-darwin-arm64/TermX.app
```

## Technology

- [Electron](https://www.electronjs.org/)
- [xterm.js](https://xtermjs.org/)
- [node-pty](https://github.com/microsoft/node-pty)
- [Node-API](https://nodejs.org/api/n-api.html)
- Swift and AppKit
- esbuild

## Project status

TermX currently targets macOS on Apple Silicon. Linux native-window support is not enabled yet, and Windows is not currently supported.

Bug reports and feedback are welcome through [GitHub Issues](https://github.com/Saksham-245/TermX/issues).

## License

This project is licensed under the ISC License.
