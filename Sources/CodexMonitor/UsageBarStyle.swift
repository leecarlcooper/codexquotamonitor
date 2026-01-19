import Cocoa
import SwiftUI

enum UsageBarStyle {
    static let redRange = 0..<15
    static let yellowRange = 15..<26
    static let greenColor = NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.40, alpha: 1.0)

    static func appKitColor(for percent: Int?) -> NSColor {
        guard let percent else { return NSColor.secondaryLabelColor }
        switch percent {
        case redRange:
            return NSColor.systemRed
        case yellowRange:
            return NSColor.systemYellow
        default:
            return greenColor
        }
    }

    static func swiftUIColor(for percent: Int?) -> Color {
        guard let percent else { return .gray }
        switch percent {
        case redRange:
            return Color(NSColor.systemRed)
        case yellowRange:
            return Color(NSColor.systemYellow)
        default:
            return Color(greenColor)
        }
    }
}
