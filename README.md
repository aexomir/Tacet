# Tacet

Noise cancelling for your Mac's screen.

The window you're working in stays sharp; everything else softens into a live blur that deepens the longer you leave it alone. Tacet turns itself on when you settle into a window and lifts when you start switching apps. Its whole interface is a circle in the menu bar (○ ◔ ◑ ●) and a Liquid Glass panel styled after Control Center: one on/off tile, Auto-focus, a Depth slider, and a row of apps that always stay clear. macOS draws the blur, so Tacet never records your screen or reads what you type.

## Requirements

- macOS 26 (Tahoe) or later, for Liquid Glass
- Swift 6

## Run

```bash
swift run
```

## Install

Download the DMG from [Releases](../../releases), open it, and drag Tacet to Applications. It isn't notarized yet, so the first time, right-click Tacet in Applications and choose Open.

## Release

Push a version tag and GitHub Actions builds the DMG and publishes the release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

To build the DMG locally instead: `scripts/make-dmg.sh 0.1.0` (output in `dist/`).

## Folder structure

```
Tacet/
├── Package.swift
├── Sources/
│   ├── App/      Entry point and the saved settings
│   ├── Panel/    Menu bar dial, the Liquid Glass control panel, and the Settings window
│   ├── Engine/   Per-screen overlay windows below the focused window, deeper layers over windows left alone
│   └── Focus/    Auto-focus: blur on when you settle in, lift when you hop between apps
├── Tests/
├── scripts/  make-dmg.sh: builds Tacet.app and the DMG
└── .github/workflows/release.yml
```
