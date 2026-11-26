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

## Folder structure

```
Tacet/
├── Package.swift
├── Sources/Tacet/
│   ├── App/      Entry point, menu bar extra, and the saved settings
│   ├── Panel/    Liquid Glass control panel (tiles, Depth slider, Always clear) and the menu bar circle
│   ├── Engine/   Per-screen overlay windows below the focused window, deeper layers over windows left alone
│   └── Focus/    Auto-focus: blur on when you settle in, lift when you hop between apps
└── Tests/TacetTests/
```
