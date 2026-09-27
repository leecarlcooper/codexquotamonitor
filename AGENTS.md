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
- Run the XCTest target in `Tests/CodexMonitorTests/` with `swift test`.
- Cover Codex protocol/response handling in `CodexRateLimitsClient.swift` and the Claude usage-page parser in `UsageService.swift`.

## Commit & Pull Request Guidelines
- Commit messages are short, imperative, and single-line (e.g., “Update usage UI and refresh docs”).
- PRs should include: a brief description of what/why, testing notes (or “Not tested”), and screenshots for UI changes. Link issues if applicable.

## Configuration & Maintenance Notes
- Codex uses `codex app-server` and `account/rateLimits/read` with the existing CLI ChatGPT account. Claude still uses the WebKit DOM parser in `UsageService.swift`.
- Minimum deployment target is macOS 13 (set in `Package.swift`).
- Avoid committing credentials or session data; Codex owns its CLI authentication and Claude uses WebKit’s data store. Preserve the local `quota-status.json` export for companion apps.
