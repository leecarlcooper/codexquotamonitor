import Cocoa

enum MenuBarIconRenderer {
    static func renderTemplate(
        fiveHourPercent: Int?,
        weeklyPercent: Int?,
        signedIn: Bool,
        palette: UsageBarPalette = .codex
    ) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let barHeight: CGFloat = 4
        let spacing: CGFloat = 3
        let horizontalPadding: CGFloat = 1
        let fullWidth: CGFloat = size.width - (horizontalPadding * 2)
        let totalHeight = (barHeight * 2) + spacing
        let startY = max(0, (size.height - totalHeight) / 2)
        let bottomY = startY
        let topY = startY + barHeight + spacing

        drawTemplateBar(y: topY, width: fullWidth, height: barHeight, percent: fiveHourPercent, signedIn: signedIn)
        drawTemplateBar(y: bottomY, width: fullWidth, height: barHeight, percent: weeklyPercent, signedIn: signedIn)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func render(
        fiveHourPercent: Int?,
        weeklyPercent: Int?,
        signedIn: Bool,
        palette: UsageBarPalette = .codex
    ) -> NSImage {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let barHeight: CGFloat = 5
        let spacing: CGFloat = 3
        let fullWidth: CGFloat = size.width
        let totalHeight = (barHeight * 2) + spacing
        let startY = max(0, (size.height - totalHeight) / 2)
        let bottomY = startY
        let topY = startY + barHeight + spacing

        drawBar(y: topY, width: fullWidth, height: barHeight, percent: fiveHourPercent, signedIn: signedIn, palette: palette)
        drawBar(y: bottomY, width: fullWidth, height: barHeight, percent: weeklyPercent, signedIn: signedIn, palette: palette)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawBar(
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        percent: Int?,
        signedIn: Bool,
        palette: UsageBarPalette
    ) {
        let outlineColor = NSColor.separatorColor.withAlphaComponent(0.85)
        let backgroundColor: NSColor
        let fillColor: NSColor
        if signedIn {
            backgroundColor = NSColor.white.withAlphaComponent(0.85)
            fillColor = color(for: percent, palette: palette)
        } else {
            backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
            fillColor = NSColor.secondaryLabelColor
        }

        let rect = NSRect(x: 0, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        backgroundColor.setFill()
        path.fill()
        outlineColor.setStroke()
        path.lineWidth = 0.6
        path.stroke()

        let clamped = max(0, min(100, percent ?? 0))
        let fillWidth = max(height, width * CGFloat(clamped) / 100)
        let fillRect = NSRect(x: 0, y: y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: height / 2, yRadius: height / 2)
        fillColor.setFill()
        fillPath.fill()
    }

    private static func drawTemplateBar(
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        percent: Int?,
        signedIn: Bool
    ) {
        let x: CGFloat = 1
        let rect = NSRect(x: x, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)

        NSColor.black.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let clamped = max(0, min(100, percent ?? 0))
        let resolvedPercent: Int
        if signedIn {
            resolvedPercent = clamped
        } else {
            resolvedPercent = percent == nil ? 35 : clamped
        }

        let fillWidth = max(height, width * CGFloat(resolvedPercent) / 100)
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: height / 2, yRadius: height / 2)
        NSColor.black.setFill()
        fillPath.fill()
    }

    private static func color(for percent: Int?, palette: UsageBarPalette) -> NSColor {
        UsageBarStyle.appKitColor(for: percent, palette: palette)
    }
}
