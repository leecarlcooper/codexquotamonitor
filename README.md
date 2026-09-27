# CodexMonitor (macOS menu bar)

A macOS menu bar app showing remaining Codex and Claude five-hour/session and weekly limits, with reset countdowns and a desktop widget.

## Requirements

- macOS 13+ for the app; macOS 14+ for the widget
- Swift 5.9+ and Xcode for building
- A current Codex CLI signed into a ChatGPT account (`codex login`) for Codex usage

## Run and build

```bash
swift run
swift test
scripts/build_app.sh
scripts/build_app.sh --install
```

The bundle build includes the desktop widget. If XcodeGen is installed, the build script regenerates the Xcode project from `project.yml`; otherwise it uses the checked-in project. Quit the running monitor before installing a replacement.

## Connect accounts

**Codex:** The monitor uses the existing Codex CLI account through the documented [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt), calling `account/rateLimits/read`. Run `codex login` in Terminal, sign in with ChatGPT, then click Refresh. API-key-only accounts do not supply ChatGPT subscription limits. The monitor discovers Codex in Homebrew locations, `~/.npm-global/bin`, the Codex app bundle, or PATH. It never reads, copies, or logs authentication tokens. It uses the CLI account, which can differ from your browser account.

**Claude:** Click Open Claude Sign In and authenticate in the embedded browser. Cookies remain in the app's WebKit data store. Claude usage is still read from `https://claude.ai/settings/usage`.

**Disconnect** pauses Codex monitoring persistently and clears the monitor's browser sessions. It does not sign the Codex CLI or desktop app out. Click Connect Codex to resume monitoring.

## Reliability and troubleshooting

- Polls every five minutes; Refresh fetches immediately. Opening the popover also refreshes Codex data older than one minute.
- Codex usage is structured data, independent of dashboard HTML, labels, or WebKit login cookies. Only the `codex` bucket and windows of 300/10080 minutes populate the two cards; unrelated model buckets are never substituted.
- Requests time out after 30 seconds and terminate their child process. Errors retain the last successful values and timestamp and display a warning instead of treating cached values as a new reading.
- If usage is unavailable, update Codex CLI, check your network, run `codex login`, and Refresh. No API key is needed.
- Reset timestamps are absolute, so countdowns remain correct as the snapshot ages.
- The Codex title opens `https://chatgpt.com/codex/settings/usage` for manual inspection; that page is no longer scraped for Codex data.
- Menu bar bars show five-hour usage above weekly usage. Green means at least 26% remaining, yellow 15–25%, red below 15%.
- Launch at login is enabled by default for bundles installed in `/Applications`.

## Local integrations

The app preserves the MiniToo-compatible snapshot at `~/Library/Application Support/CodexMonitor/quota-status.json`. It contains remaining percentages, reset text, an additive ISO-8601 `resetAt` field for Codex limits, authentication state, last successful update, and any error. Consumers should check the timestamp and error before displaying data as current.

```bash
/Applications/CodexMonitor.app/Contents/MacOS/CodexMonitor --quota-status
/Applications/CodexMonitor.app/Contents/MacOS/CodexMonitor --quota-status-path
```

These commands read the saved snapshot; they do not fetch fresh usage. Widget snapshots are published separately.

## Development

`CodexRateLimitsClient.swift` owns Codex process/protocol handling and response decoding. `UsageService.swift` owns polling state and the Claude DOM parser. `swift test` covers bucket/window selection, percentages, timestamps, fragmented protocol responses, unavailable executables, timeouts, early process exit, companion export compatibility, and widget error preservation.
