import Cocoa

enum MenuBarIconRenderer {
    static func render(fiveHourPercent: Int?, weeklyPercent: Int?, signedIn: Bool) -> NSImage {
        let size = NSSize(width: 26, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        let barHeight: CGFloat = 4
        let spacing: CGFloat = 3
        let fullWidth: CGFloat = size.width

        let topY = size.height - barHeight
        let bottomY = topY - barHeight - spacing

        drawBar(y: topY, width: fullWidth, height: barHeight, percent: fiveHourPercent, signedIn: signedIn)
        drawBar(y: bottomY, width: fullWidth, height: barHeight, percent: weeklyPercent, signedIn: signedIn)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawBar(y: CGFloat, width: CGFloat, height: CGFloat, percent: Int?, signedIn: Bool) {
        let outlineColor = NSColor.separatorColor.withAlphaComponent(0.6)
        let backgroundColor: NSColor
        let fillColor: NSColor
        if signedIn {
            backgroundColor = NSColor.white.withAlphaComponent(0.85)
            fillColor = color(for: percent)
        } else {
            backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
            fillColor = NSColor.secondaryLabelColor
        }

        let rect = NSRect(x: 0, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
        backgroundColor.setFill()
        path.fill()
        outlineColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        guard let percent else { return }
        let clamped = max(0, min(100, percent))
        let fillWidth = max(height, width * CGFloat(clamped) / 100)
        let fillRect = NSRect(x: 0, y: y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: height / 2, yRadius: height / 2)
        fillColor.setFill()
        fillPath.fill()
    }

    private static func color(for percent: Int?) -> NSColor {
        guard let percent else { return NSColor.secondaryLabelColor }
        switch percent {
        case 0..<25:
            return NSColor.systemRed
        case 25..<55:
            return NSColor.systemYellow
        default:
            return NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.40, alpha: 1.0)
        }
    }
}
