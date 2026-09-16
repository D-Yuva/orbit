import AppKit
import SwiftUI

enum OrbitTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let text = Color(nsColor: .labelColor)
    static let line = Color(nsColor: .separatorColor).opacity(0.5)
    static let accent = Color(nsColor: .systemBlue)
}

struct OrbitSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content
        }
    }
}
