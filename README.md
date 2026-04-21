# Spotdark

A minimal macOS launcher prototype.

## What this starter provides

- Global hotkey toggles a centered launcher panel.
  - Default tries **Command+Space**.
  - If it fails (Spotlight usually owns it), the app shows a warning and falls back to **Option+Space**.
- Spotlight-like UI:
  - Borderless floating panel
  - System blur / vibrancy ("glass" look)
  - Rounded selection highlight
- Search box with real-time results.
- Results include:
  - Installed applications (scanned from common locations)
  - In-app commands (in-memory registry)

## Application indexing

`DefaultAppProvider` scans multiple common app locations and supports limited recursion to catch nested folders like Utilities.

Default roots include:

- `/Applications`
- `/Applications/Utilities`
- `/System/Applications`
- `/System/Applications/Utilities`
- `~/Applications`

If you need more coverage (e.g. Setapp or custom install paths), add directories when constructing `DefaultAppProvider`.

## Build & Run

This repo is structured as a Swift Package:

- `SpotdarkCore` (library): search engine, models, app provider, hotkey abstraction
- `SpotdarkApp` (executable): AppKit UI and app entry point

In Xcode:

1. File → Open… → select the `Spotdark` folder
2. Select the `SpotdarkApp` scheme
3. Run

Or via SwiftPM:

```bash
swift run SpotdarkApp
```

## Testing

Run unit tests in Xcode, or via SwiftPM:

```bash
swift test
```

## Notes

- `Command+Space` is typically reserved by macOS Spotlight.
- The app uses `.accessory` activation policy (menu bar style app).
