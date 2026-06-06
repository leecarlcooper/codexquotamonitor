import SwiftUI
import AppKit
import Foundation

struct PopoverView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var claudeUsageService: UsageService
    @ObservedObject var settings: SettingsStore
    let onSignIn: () -> Void
    let onClaudeSignIn: () -> Void
    let onRefresh: () -> Void
    let onLogout: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 16) {
                header
                    .layoutPriority(1)
                content
                claudeSection
                settingsSeparator
                settingsSection
                footer
            }
            .padding(18)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(width: 340, height: 700)
    }

    private var header: some View {
        HStack {
            selectionButton(for: .codex)
            Text("Codex")
                .font(.system(size: 17, weight: .semibold))
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(usageService.usageURL)
                }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        usageContent(
            for: usageService,
            signInLabel: "Open Codex Sign In",
            signInAction: onSignIn,
            titles: ("5 hour limit", "Weekly limit"),
            palette: .codex
        )
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                selectionButton(for: .claude)
                Text("Claude")
                    .font(.system(size: 15, weight: .semibold))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSWorkspace.shared.open(claudeUsageService.usageURL)
                    }
            }
            usageContent(
                for: claudeUsageService,
                signInLabel: "Open Claude Sign In",
                signInAction: onClaudeSignIn,
                titles: ("Current session", "Weekly limits"),
                palette: .claude
            )
        }
    }

    @ViewBuilder
    private func usageContent(
        for service: UsageService,
        signInLabel: String,
        signInAction: @escaping () -> Void,
        titles: (String, String),
        palette: UsageBarPalette
    ) -> some View {
        if service.authState == .needsLogin {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to view limits")
                    .font(.system(size: 14, weight: .medium))
                Button(action: signInAction) {
                    Text(signInLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else if service.fiveHourLimit == nil && service.weeklyLimit == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading usage…")
                    .font(.system(size: 14, weight: .medium))
                Button(action: signInAction) {
                    Text(signInLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 12) {
                UsageCard(
                    title: titles.0,
                    limit: service.fiveHourLimit,
                    referenceDate: service.lastUpdated,
                    showTitle: true,
                    palette: palette
                )
                UsageCard(
                    title: titles.1,
                    limit: service.weeklyLimit,
                    referenceDate: service.lastUpdated,
                    showTitle: true,
                    palette: palette
                )
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .disabled(!settings.canRegisterLoginItem)
        }
    }

    private var settingsSeparator: some View {
        Divider()
            .opacity(0.5)
    }

    private var footer: some View {
        HStack {
            if let error = usageService.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if let lastUpdated = usageService.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Waiting for update...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Log out") {
                onLogout()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
    }
}

private struct UsageCard: View {
    let title: String
    let limit: UsageLimit?
    let referenceDate: Date?
    let showTitle: Bool
    let palette: UsageBarPalette

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            cardBody(now: context.date)
        }
    }

    private var percentText: String {
        guard let percent = limit?.percentRemaining else { return "--%" }
        return "\(percent)%"
    }

    private var metricText: String {
        "remaining"
    }

    private func resetText(now: Date) -> String {
        guard let limit, !limit.resetText.isEmpty else { return "Reset time unavailable" }
        guard let countdown = ResetCountdownFormatter.countdown(
            from: limit.resetText,
            now: now,
            referenceDate: referenceDate
        ) else {
            return "Reset time unavailable"
        }
        return "Resets in \(countdown)"
    }

    private func cardBody(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .layoutPriority(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percentText)
                    .font(.system(size: 24, weight: .bold))
                Text(metricText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            UsageBar(fillPercent: limit?.percentRemaining, stylePercent: limit?.percentRemaining, palette: palette)
                .frame(height: 10)

            Text(resetText(now: now))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.black.opacity(0.12))
        .cornerRadius(12)
    }
}

private struct UsageBar: View {
    let fillPercent: Int?
    let stylePercent: Int?
    let palette: UsageBarPalette

    private var clamped: CGFloat {
        CGFloat(max(0, min(100, fillPercent ?? 0))) / 100
    }

    private var resolvedBarColor: Color {
        UsageBarStyle.swiftUIColor(for: stylePercent, palette: palette)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 6)
                    .fill(resolvedBarColor)
                    .frame(width: proxy.size.width * clamped)
            }
        }
    }
}

private extension PopoverView {
    func selectionButton(for source: UsageSource) -> some View {
        Button(action: { settings.selectedUsageSource = source }) {
            Image(systemName: settings.selectedUsageSource == source ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source == .codex ? "Show Codex in menu bar" : "Show Claude in menu bar")
    }
}
