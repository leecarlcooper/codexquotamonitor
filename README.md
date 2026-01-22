# CodexMonitor (macOS menu bar)

A lightweight menu bar app that polls the Codex usage page every 5 minutes and shows remaining 5‑hour and weekly limits with a reset countdown.

## Requirements

- macOS 13+
- Swift 5.9 (Xcode 15+)

## Run (local)

```bash
swift run
```

This launches the menu bar app (no Dock icon). Use the menu bar icon to open the popover.

## Build app bundle

```bash
scripts/build_app.sh
```

To install into `/Applications` and open it:

```bash
scripts/build_app.sh --install
```

## Sign in

Click **Open Sign In** in the popover to log in via the embedded browser window. Cookies are stored in the app’s WebKit data store.

## Notes

- Data source: `https://chatgpt.com/codex/settings/usage`
- Polling interval: 5 minutes
- Menu bar icon shows two stacked bars (5‑hour on top, weekly on bottom) with green/yellow/red warnings based on remaining % (green ≥26%, yellow 15–25%, red <15%)
- Usage cards show the percent remaining plus a “Resets in …” countdown parsed from the usage dashboard
- Popover usage bars use the same color thresholds as the menu bar icon via `UsageBarStyle`
- Optional: enable launch-at-login from the popover (requires running as a bundled app in /Applications)

If the page’s DOM changes, update the JS parser in `Sources/CodexMonitor/UsageService.swift`.
