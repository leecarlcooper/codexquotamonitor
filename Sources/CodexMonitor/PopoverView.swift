import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var usageService: UsageService
    @ObservedObject var settings: SettingsStore
    let onSignIn: () -> Void
    let onRefresh: () -> Void

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
                content
                settingsSection
                footer
            }
            .padding(18)
        }
        .frame(width: 340, height: 320)
    }

    private var header: some View {
        HStack {
            Text("Codex Usage")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if usageService.authState == .needsLogin {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to view limits")
                    .font(.system(size: 14, weight: .medium))
                Button(action: onSignIn) {
                    Text("Open Sign In")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else if usageService.fiveHourLimit == nil && usageService.weeklyLimit == nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Loading usage…")
                    .font(.system(size: 14, weight: .medium))
                Button(action: onSignIn) {
                    Text("Open Sign In")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(spacing: 12) {
                UsageCard(title: "5 hour usage limit", limit: usageService.fiveHourLimit, showTitle: true)
                UsageCard(title: "Weekly usage limit", limit: usageService.weeklyLimit, showTitle: true)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .disabled(!settings.canRegisterLoginItem)
            if !settings.canRegisterLoginItem {
                Text("Launch at login requires a bundled app in /Applications.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else if let message = settings.loginItemMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Toggle("Low usage notifications", isOn: $settings.notificationsEnabled)
                .toggleStyle(.switch)
                .disabled(!NotificationManager.isSupported)
            if let message = settings.notificationsMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
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
            Button("Usage Page") {
                NSWorkspace.shared.open(UsageService.usageURL)
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
    let showTitle: Bool

    var body: some View {
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
                Text("remaining")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            UsageBar(percent: limit?.percentRemaining)
                .frame(height: 10)

            Text(resetText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.black.opacity(0.12))
        .cornerRadius(12)
    }

    private var percentText: String {
        guard let percent = limit?.percentRemaining else { return "--%" }
        return "\(percent)%"
    }

    private var resetText: String {
        guard let limit, !limit.resetText.isEmpty else { return "Reset time unavailable" }
        return "Resets \(limit.resetText)"
    }
}

private struct UsageBar: View {
    let percent: Int?

    private var clamped: CGFloat {
        CGFloat(max(0, min(100, percent ?? 0))) / 100
    }

    private var barColor: Color {
        guard let percent else { return .gray }
        switch percent {
        case 0..<25: return .red
        case 25..<55: return .yellow
        default: return .green
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 6)
                    .fill(barColor)
                    .frame(width: proxy.size.width * clamped)
            }
        }
    }
}
