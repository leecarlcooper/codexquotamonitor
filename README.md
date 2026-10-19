# CodexMonitor (macOS menu bar)

A macOS menu bar app showing remaining Codex and Claude limits plus Cursor’s monthly Cursor Models and Other Models buckets, with reset countdowns and a desktop widget.

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

**Codex:** The monitor uses the existing Codex CLI account through the documented [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt), calling `account/rateLimits/read`. Run `codex login` in Terminal, sign in with ChatGPT, then click Refresh. API-key-only accounts do not supply ChatGPT subscription limits. The monitor discovers Codex in Homebrew locations, `~/.local/bin`, `~/.npm-global/bin`, the Codex app bundle, or PATH. It never reads, copies, or logs authentication tokens. It uses the CLI account, which can differ from your browser account.

**Claude:** Click Open Claude Sign In and authenticate in the embedded browser. Cookies remain in the app's WebKit data store. Claude usage is still read from `https://claude.ai/settings/usage`.

**Cursor:** Click Open Cursor Sign In and authenticate in the embedded browser. The monitor requests `https://cursor.com/api/usage-summary` in that authenticated WebKit session. `individualUsage.plan.autoPercentUsed` supplies Cursor Models usage, `apiPercentUsed` supplies Other Models usage, and `billingCycleEnd` supplies the shared reset timestamp. Percentages are converted from used to remaining and shown with up to one decimal place. The app follows the current billing cycle automatically; daily usage-event filters do not affect it.

This is an internal dashboard endpoint, not a supported public personal-quota API. If it changes, the monitor falls back to the two aggregate rows in the dashboard’s Included Usage section. The fallback uses the displayed cycle-end date at local midnight because the page does not specify an hour; only the API gives an exact reset time. Missing buckets stay unavailable. Cursor cookies remain in WebKit, with no API key setup or browser-cookie extraction. Cursor’s documented [Admin API](https://cursor.com/docs/account/teams/admin-api) is intended for team administration.

Select Cursor’s circle to show its two buckets in the menu bar. Its reset countdowns use days and hours (`15d 6h`, or `<1h`). Each provider’s two usage cards sit side by side so all three providers fit in the popover. The small widget follows the selection, the medium widget shows Codex and either Claude or the selected Cursor provider, and the large widget shows all three.

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

The app preserves the MiniToo-compatible snapshot at `~/Library/Application Support/CodexMonitor/quota-status.json`. Existing Codex and Claude fields are preserved. An additive `cursor` object exports `cursorModels` and `otherModels` limits, including decimal `precisePercentRemaining` values. It contains remaining percentages, reset text, an additive ISO-8601 `resetAt` field for Codex limits, authentication state, last successful update, and any error. Consumers should check the timestamp and error before displaying data as current.

```bash
/Applications/CodexMonitor.app/Contents/MacOS/CodexMonitor --quota-status
/Applications/CodexMonitor.app/Contents/MacOS/CodexMonitor --quota-status-path
```

These commands read the saved snapshot; they do not fetch fresh usage. Widget snapshots are published separately.

## Development

`CodexRateLimitsClient.swift` owns Codex process/protocol handling and response decoding. `UsageService.swift` owns polling state and the Claude DOM parser. `CursorUsageParser.swift` handles Cursor’s summary response and dashboard fallback. `swift test` covers bucket/window selection, percentages, timestamps, fragmented protocol responses, unavailable executables, timeouts, early process exit, companion export compatibility, widget error preservation, Cursor bucket selection, decimal percentages, missing data, dashboard fallback, and billing-cycle countdowns.
