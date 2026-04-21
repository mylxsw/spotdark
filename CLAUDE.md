# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Spotdark is a macOS (14+) Spotlight-style launcher prototype shipped as a Swift Package. The working directory is named `superflux` for historical reasons; the product name is Spotdark.

## Build, run, test

```bash
swift build
swift run SpotdarkApp      # or: make run
swift test
swift test --filter SpotdarkCoreTests.SearchEngineTests                             # run one test class
swift test --filter SpotdarkCoreTests.SearchEngineTests/testAppPrefixMatchRanksHigherThanSubstring   # run one test
```

The package can also be opened directly in Xcode (`File → Open…` on the repo root, then run the `SpotdarkApp` scheme).

## Architecture

Two SwiftPM targets with a strict dependency direction: `SpotdarkApp` → `SpotdarkCore`.

- **`SpotdarkCore`** is platform-abstract (no AppKit/SwiftUI imports). It holds the models, search engine, app-indexing abstractions, command registry, and the Carbon hot-key manager. Everything here is unit-testable without a UI.
- **`SpotdarkApp`** is the AppKit + SwiftUI executable. It owns the `NSPanel`, SwiftUI views, usage persistence, icon/name caches, and wires `SpotdarkCore` pieces together.

### Flow of a keystroke

1. `AppDelegate` registers a global hot key through `CarbonHotKeyManager` — tries `Cmd+Space`, falls back to `Opt+Space` on failure (Spotlight usually owns `Cmd+Space`).
2. The handler calls `LauncherCoordinator.shared.toggle()`, which shows/hides the `LauncherPanel` (borderless floating `NSPanel`, `.accessory` activation policy — no Dock icon).
3. `LauncherStore` (an `@Observable @MainActor` store) owns query text, results, selection, and drives the search via `SearchEngine`.

### App indexing

Two providers exist; the running app uses the streaming one:

- `SpotlightIndexStream` (used by `LauncherStore`) wraps `NSMetadataQuery` and exposes changes as `AsyncStream<AppIndexDelta>` (`.initial` snapshot, then `.update(added:removed:)`). Because `NSMetadataQuery` is not `Sendable` but `AsyncStream.Continuation.onTermination` requires `@Sendable`, the stream captures query/observer tokens in an `@unchecked Sendable` `Handle` class and tears down on the main thread.
- `DefaultAppProvider` / `MetadataAppProvider` / `CachedAppProvider` are simpler synchronous alternatives retained for tests and as building blocks.

### Search & ranking

`SearchEngine.search` returns items sorted by a lower-is-better score:

- `0` prefix match, `1` word-boundary match, `2` substring match.
- Score is multiplied by `1000` and then `UsageScoring` subtracts a boost, so usage only breaks ties within the same match tier.
- `UsageStore` (in `SpotdarkApp`) persists launch counts to `UserDefaults` and implements `UsageScoring`.

### Swift 6 concurrency gotchas (already encountered here)

- `UsageScoring` is nonisolated because `SearchEngine` is not actor-bound. `UsageStore` therefore **must not** be `@MainActor` — it uses an `NSLock` instead.
- `LauncherStore` holds `Task`s inside a separate `TaskBox` (a plain `final class` with a lock) so that `deinit` can cancel them without crossing actor isolation.
- In `LauncherStore.selectedIndex`, **do not** clamp by reassigning inside `didSet` — with the Observation macros that re-enters and crashes. Clamp at the call sites (`select(index:)`, `performSearchNow`) instead.

### Command system

In-app actions (not shell commands) live in `CommandRegistry` and are handled inside `LauncherStore.handle(command:)` by string id (`open-settings`, `quit`). Adding a new command requires both: registering a `CommandItem` in `LauncherPanelController.init` and adding its case to `handle(command:)`.
