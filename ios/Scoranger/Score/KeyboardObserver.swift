import SwiftUI
import UIKit

/// The live keyboard height, for the panels that lift themselves.
///
/// Measured as what the keyboard's end frame actually COVERS at the bottom of
/// the screen, not its height: an undocked or floating keyboard on an iPad sits
/// away from the bottom edge and covers nothing, and padding a panel by its
/// height would push the input off the top.
final class KeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0

    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        let change = center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                self?.height = Self.covered(by: note)
            }
        let hide = center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.height = 0
            }
        tokens = [change, hide]
    }

    deinit {
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
    }

    private static func covered(by note: Notification) -> CGFloat {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                            as? NSValue)?.cgRectValue else { return 0 }
        let screen = (note.object as? UIScreen)?.bounds
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds }.first
            ?? .zero
        guard screen.height > 0 else { return 0 }
        return min(max(screen.maxY - frame.minY, 0), screen.height)
    }
}
