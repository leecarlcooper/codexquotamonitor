# Repository Guidelines

## Project Structure & Module Organization
- `Sources/CodexMonitor/` holds the Swift sources for the macOS menu bar app (AppKit + SwiftUI). Key flows live in `Main.swift`, `UsageService.swift`, and the popover/login UI files.
- `Sources/CodexMonitor/UsageBarStyle.swift` centralizes bar thresholds and colors for the menu bar icon and popover.
- `Package.swift` defines a single executable target for macOS 13+.
- `scripts/` contains build tooling, including the app-bundle script.
- `dist/` is the default output location for release app bundles created by the build script.

## Build, Test, and Development Commands
- `swift run` starts the menu bar app locally (no Dock icon). Use the menu bar icon to open the popover.
- `scripts/build_app.sh` builds a release binary and creates a `.app` bundle in `dist/`.
- `scripts/build_app.sh --install` installs to `/Applications` and opens the app.

## Coding Style & Naming Conventions
- Follow Swift 5.9 and Apple API design guidelines; keep code idiomatic and readable.
- Indentation is 4 spaces; avoid tabs.
- Types and files use `UpperCamelCase` (e.g., `UsageService.swift`); methods and properties use `lowerCamelCase`.
- Keep UI logic in view/controller files and parsing/network logic in services.

## Testing Guidelines
- No automated tests are present yet. If you add tests, create a `Tests/CodexMonitorTests/` XCTest target and run them with `swift test`.
- Prioritize unit tests for the usage-page parser in `UsageService.swift`, since DOM changes are the most likely regression.

## Commit & Pull Request Guidelines
- Commit messages are short, imperative, and single-line (e.g., “Update usage UI and refresh docs”).
- PRs should include: a brief description of what/why, testing notes (or “Not tested”), and screenshots for UI changes. Link issues if applicable.

## Configuration & Maintenance Notes
- The app scrapes `https://chatgpt.com/codex/settings/usage`; if the DOM changes, update the parsing logic in `Sources/CodexMonitor/UsageService.swift`.
- Avoid committing credentials or session data; authentication is handled via WebKit’s data store at runtime.
