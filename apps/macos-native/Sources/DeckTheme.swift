import SwiftUI

enum DeckMetrics {
    static let windowDefaultWidth: CGFloat = 1024
    static let windowDefaultHeight: CGFloat = 768
    static let windowMinWidth: CGFloat = 800
    static let windowMinHeight: CGFloat = 600

    static let sidebarWidth: CGFloat = 200
    static let topBarHeight: CGFloat = 56
    static let channelRowHeight: CGFloat = 44
    static let channelRowPadding: CGFloat = 6
    static let channelRowGap: CGFloat = 6
    static let composerHeight: CGFloat = 44
    static let composerAreaHeight: CGFloat = 68
    static let avatarSize: CGFloat = 32

    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24

    static let radius8: CGFloat = 8
    static let radius10: CGFloat = 10
    static let radius12: CGFloat = 12
    static let radius16: CGFloat = 16
}

enum DeckTypography {
    static let caption: CGFloat = 10
    static let meta: CGFloat = 11
    static let bodySmall: CGFloat = 12
    static let body: CGFloat = 13
    static let control: CGFloat = 14
    static let title: CGFloat = 16
}

enum DeckColor {
    static let sidebar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1) : NSColor(red: 250 / 255, green: 250 / 255, blue: 254 / 255, alpha: 1)
    })
    static let selectedRow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1) : NSColor(red: 232 / 255, green: 234 / 255, blue: 238 / 255, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1) : NSColor.white
    })
    static let composer = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1) : NSColor(red: 250 / 255, green: 250 / 255, blue: 254 / 255, alpha: 1)
    })
    static let border = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.29, green: 0.29, blue: 0.32, alpha: 1) : NSColor(red: 224 / 255, green: 224 / 255, blue: 224 / 255, alpha: 1)
    })
    static let text = Color(nsColor: NSColor.labelColor)
    static let headerText = Color(nsColor: NSColor.labelColor)
    static let muted = Color(nsColor: NSColor.secondaryLabelColor)
    static let placeholder = Color(nsColor: NSColor.placeholderTextColor)
    static let avatar = Color(red: 133 / 255, green: 133 / 255, blue: 125 / 255)
    static let online = Color(red: 48 / 255, green: 214 / 255, blue: 105 / 255)
    static let tableHeader = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1) : NSColor(red: 246 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1)
    })
    static let codeHeader = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1) : NSColor(red: 242 / 255, green: 244 / 255, blue: 247 / 255, alpha: 1)
    })
    static let codeBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1) : NSColor(red: 250 / 255, green: 251 / 255, blue: 253 / 255, alpha: 1)
    })
    static let codeKeyword = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.55, green: 0.70, blue: 1.00, alpha: 1) : NSColor(red: 0.20, green: 0.34, blue: 0.78, alpha: 1)
    })
    static let codeString = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.78, green: 0.66, blue: 0.44, alpha: 1) : NSColor(red: 0.57, green: 0.32, blue: 0.04, alpha: 1)
    })
    static let codeNumber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.73, green: 0.58, blue: 0.94, alpha: 1) : NSColor(red: 0.45, green: 0.25, blue: 0.74, alpha: 1)
    })
    static let codeComment = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.45, green: 0.55, blue: 0.49, alpha: 1) : NSColor(red: 0.36, green: 0.49, blue: 0.40, alpha: 1)
    })
}

extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
