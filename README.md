# Tacet

Noise cancelling for your Mac's screen.

The window you're working in stays sharp; everything else softens into a live blur that deepens the longer you leave it alone. Tacet turns itself on when you settle into a window and lifts when you start switching apps. Its whole interface is a circle in the menu bar (○ ◔ ◑ ●) and a Liquid Glass panel styled after Control Center: one on/off tile, Auto-focus, Share shield, a Depth slider, and a row of apps that always stay clear. macOS draws the blur, so Tacet never records your screen or reads what you type.

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
│   ├── App/      Entry point and menu bar icon
│   ├── Panel/    Liquid Glass control panel (tiles, Depth slider, Always clear)
│   ├── Engine/   Per-screen overlay windows that blur everything behind the focused window
│   ├── Focus/    Frontmost-window tracking, auto-focus, and blur decay over time
│   └── Shield/   Screen-share detection for Share shield
└── Tests/TacetTests/
```

Folders appear in the repo as code lands in them.
