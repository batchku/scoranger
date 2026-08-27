import SwiftUI
import UIKit

/// Apple's share sheet, wrapped so SwiftUI can present it.
///
/// The no-modal rule (NAV_MODAL_FREE_0.4.2 §1) is about surfaces this app
/// invents. This one is the system's: it is how a file reaches Files, Mail,
/// AirDrop or another notation program, every iOS user already knows it, and
/// there is no way to reimplement it. It is the single exception, and it is
/// only ever raised by a deliberate tap on an export row.
struct SystemShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
