import SwiftUI
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaWidgetSnapshot
}

struct QuotaWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaWidgetEntry {
        QuotaWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaWidgetEntry) -> Void) {
        completion(QuotaWidgetEntry(date: Date(), snapshot: QuotaWidgetStore.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaWidgetEntry>) -> Void) {
        let now = Date()
        let entry = QuotaWidgetEntry(date: now, snapshot: QuotaWidgetStore.load() ?? .empty)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(300))))
    }
}

@main
struct CodexQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexQuotaWidget()
    }
}

struct CodexQuotaWidget: Widget {
    let kind = QuotaWidgetStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaWidgetProvider()) { entry in
            QuotaWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    QuotaWidgetBackground()
                }
        }
        .configurationDisplayName("AI Quota")
        .description("Shows Codex and Claude quota remaining.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct QuotaWidgetView: View {
    let entry: QuotaWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isFullColor: Bool {
        renderingMode == .fullColor
    }

    var body: some View {
        switch family {
        case .systemSmall:
            SmallQuotaWidget(
                product: selectedProduct,
                date: entry.date,
                isFullColor: isFullColor,
                isStale: selectedProduct.isStale(at: entry.date),
                updatedAt: selectedProduct.lastUpdated
            )
        case .systemLarge:
            LargeQuotaWidget(
                snapshot: entry.snapshot,
                date: entry.date,
                isFullColor: isFullColor
            )
        default:
            MediumQuotaWidget(
                snapshot: entry.snapshot,
                date: entry.date,
                isFullColor: isFullColor
            )
        }
    }

    private var selectedProduct: QuotaProductSnapshot {
        switch entry.snapshot.selectedProduct {
        case .codex:
            return entry.snapshot.codex
        case .claude:
            return entry.snapshot.claude
        }
    }
}

private struct MediumQuotaWidget: View {
    let snapshot: QuotaWidgetSnapshot
    let date: Date
    let isFullColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ProductQuotaRow(product: snapshot.codex, date: date, isFullColor: isFullColor)
            Divider().overlay(Color.white.opacity(isFullColor ? 0.10 : 0.16))
            ProductQuotaRow(product: snapshot.claude, date: date, isFullColor: isFullColor)

            HStack {
                Spacer()
                UpdatedFooter(updatedAt: snapshot.latestUpdatedAt, now: date, isStale: false)
            }
        }
        .padding(14)
    }
}

private struct SmallQuotaWidget: View {
    let product: QuotaProductSnapshot
    let date: Date
    let isFullColor: Bool
    let isStale: Bool
    let updatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProductHeader(product: product.product, isFullColor: isFullColor, isStale: isStale)
            QuotaMetricView(
                title: product.shortTitle,
                limit: product.shortLimit,
                authState: product.authState,
                date: date,
                referenceDate: product.lastUpdated,
                palette: product.palette,
                isFullColor: isFullColor,
                isStale: isStale
            )
            QuotaMetricView(
                title: product.weeklyTitle,
                limit: product.weeklyLimit,
                authState: product.authState,
                date: date,
                referenceDate: product.lastUpdated,
                palette: product.palette,
                isFullColor: isFullColor,
                isStale: isStale
            )
            if isStale {
                UpdatedFooter(updatedAt: updatedAt, now: date, isStale: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct LargeQuotaWidget: View {
    let snapshot: QuotaWidgetSnapshot
    let date: Date
    let isFullColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Quota")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                UpdatedFooter(updatedAt: snapshot.latestUpdatedAt, now: date, isStale: false)
            }

            VStack(alignment: .leading, spacing: 12) {
                ProductQuotaRow(product: snapshot.codex, date: date, isFullColor: isFullColor)
                ProductQuotaRow(product: snapshot.claude, date: date, isFullColor: isFullColor)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }
}

private struct ProductQuotaRow: View {
    let product: QuotaProductSnapshot
    let date: Date
    let isFullColor: Bool
    private var isStale: Bool {
        product.isStale(at: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProductHeader(product: product.product, isFullColor: isFullColor, isStale: isStale)
                .frame(width: 74, alignment: .leading)

            QuotaMetricView(
                title: product.shortTitle,
                limit: product.shortLimit,
                authState: product.authState,
                date: date,
                referenceDate: product.lastUpdated,
                palette: product.palette,
                isFullColor: isFullColor,
                isStale: isStale
            )

            QuotaMetricView(
                title: product.weeklyTitle,
                limit: product.weeklyLimit,
                authState: product.authState,
                date: date,
                referenceDate: product.lastUpdated,
                palette: product.palette,
                isFullColor: isFullColor,
                isStale: isStale
            )
        }
    }
}

private struct ProductHeader: View {
    let product: QuotaProduct
    let isFullColor: Bool
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: product.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(identityColor)
                .widgetAccentable()
            HStack(spacing: 3) {
                Text(product.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }

    private var identityColor: Color {
        if isFullColor {
            return product.identityColor
        }
        return product.identityColor.opacity(0.42)
    }
}

private struct QuotaMetricView: View {
    let title: String
    let limit: QuotaLimitSnapshot?
    let authState: QuotaAuthState
    let date: Date
    let referenceDate: Date?
    let palette: UsageBarPalette
    let isFullColor: Bool
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(percentText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if isLow {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(warningColor)
                        .widgetAccentable()
                }
            }

            QuotaProgressBar(percent: limit?.percentRemaining, palette: palette, isFullColor: isFullColor)
                .frame(height: 8)
                .opacity(isStale ? 0.55 : 1)

            Text(detailText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var percentText: String {
        guard let percent = limit?.percentRemaining else { return "--%" }
        return "\(percent)%"
    }

    private var detailText: String {
        if authState == .needsLogin {
            return "Sign in required"
        }
        guard let limit else { return "Waiting for update" }
        guard let countdown = ResetCountdownFormatter.countdown(
            from: limit.resetText,
            now: date,
            referenceDate: referenceDate
        ) else {
            return "Reset time unavailable"
        }
        return "Resets in \(countdown)"
    }

    private var isLow: Bool {
        guard let percent = limit?.percentRemaining else { return false }
        return percent < 15
    }

    private var warningColor: Color {
        isFullColor ? Color(NSColor.systemRed) : Color.white.opacity(0.78)
    }
}

private struct QuotaProgressBar: View {
    let percent: Int?
    let palette: UsageBarPalette
    let isFullColor: Bool

    private var clamped: CGFloat {
        CGFloat(max(0, min(100, percent ?? 0))) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(isFullColor ? 0.14 : 0.18))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(5, proxy.size.width * clamped))
                    .widgetAccentable()
            }
        }
    }

    private var barColor: Color {
        if isFullColor {
            return UsageBarStyle.swiftUIColor(for: percent, palette: palette)
        }

        guard let percent else {
            return Color.white.opacity(0.30)
        }
        if percent < 15 {
            return Color.white.opacity(0.86)
        }
        if percent < 26 {
            return Color.white.opacity(0.72)
        }
        return Color.white.opacity(0.58)
    }
}

private struct UpdatedFooter: View {
    let updatedAt: Date?
    let now: Date
    let isStale: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isStale {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 8, weight: .semibold))
            }
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(isStale ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
    }

    private var label: String {
        guard let updatedAt else { return "Waiting for update" }
        let time: String
        if Calendar.current.isDate(updatedAt, inSameDayAs: now) {
            time = updatedAt.formatted(date: .omitted, time: .shortened)
        } else {
            time = updatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return isStale ? "Stale · \(time)" : "Updated \(time)"
    }
}

private struct QuotaWidgetBackground: View {
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.12, blue: 0.17).opacity(0.82),
                            Color(red: 0.18, green: 0.10, blue: 0.12).opacity(0.78),
                            Color(red: 0.23, green: 0.13, blue: 0.06).opacity(0.72)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
            ContainerRelativeShape()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
}

private extension QuotaProductSnapshot {
    var palette: UsageBarPalette {
        switch product {
        case .codex:
            return .codex
        case .claude:
            return .claude
        }
    }
}

private extension QuotaProduct {
    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }

    var symbolName: String {
        switch self {
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .claude:
            return "sparkles"
        }
    }

    var identityColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.18, green: 0.62, blue: 0.95)
        case .claude:
            return Color(red: 0.84, green: 0.47, blue: 0.22)
        }
    }
}
