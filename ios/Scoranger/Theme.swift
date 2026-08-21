import SwiftUI

/// The app's small colour vocabulary, so the same idea is the same colour
/// wherever it appears.
enum Theme {
    /// Structure: section headings, carets, row icons. The system accent.
    static let structure = Color.accentColor

    /// The arrangement number. Deliberately not the accent colour: "#3" is a
    /// handle you type into chat, not navigation chrome, and at accent blue it
    /// read as just another piece of the sidebar's furniture.
    static let arrangementNumber = Color(.systemPurple)
}
