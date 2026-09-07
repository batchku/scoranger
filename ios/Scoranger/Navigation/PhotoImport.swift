import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A score photographed rather than filed.
///
/// Ali: "in addition to opening files, I need an option to open the local
/// photo gallery too." A photograph of a page is how a score most often
/// arrives when it is not already a file, and Files cannot reach the camera
/// roll.
///
/// `PHPickerViewController` and NOT `UIImagePickerController`: the picker runs
/// OUT OF PROCESS, so it needs no photo-library permission and shows no
/// prompt. The app is handed the one image the reader chose and never gains
/// access to the library -- which is both the polite arrangement and one less
/// Info.plist key that could be missing on a device.
///
/// What comes back goes through the SAME pipeline a file does
/// (`AppState.receiveFile`), so a photograph becomes an IMAGE-tagged piece,
/// viewable as it is and readable through make-editable, exactly like a
/// share-in.
struct PhotoImport: UIViewControllerRepresentable {
    var onPicked: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        // Images only: this is a score, not a video.
        configuration.filter = .images
        // Several pages of one piece is the ordinary case for a photographed
        // score, and `receiveFile` already takes them one at a time.
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([URL]) -> Void
        private let onCancel: () -> Void

        init(onPicked: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onCancel()
                return
            }
            Task {
                var urls: [URL] = []
                for result in results {
                    if let url = await Self.file(from: result.itemProvider) {
                        urls.append(url)
                    }
                }
                await MainActor.run { self.onPicked(urls) }
            }
        }

        /// One picked item, copied out as a file.
        ///
        /// No conversion here: anything the engine will not take is
        /// normalised at the SHARED entry point (`ScanImage.normalised`, from
        /// `AppState.receiveFile`), because a picture from the camera roll and
        /// a picture from Files are the same thing once there is a file --
        /// §15 ruling 1, and a conversion on one route only is the drift it
        /// forbids.
        static func file(from provider: NSItemProvider) async -> URL? {
            await copy(from: provider)
        }

        private static func copy(from provider: NSItemProvider) async -> URL? {
            await withCheckedContinuation { continuation in
                _ = provider.loadFileRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { url, _ in
                    guard let url else {
                        continuation.resume(returning: nil)
                        return
                    }
                    // The provider's URL is deleted the moment this closure
                    // returns, so it is copied out before anything else looks
                    // at it. The name is kept: it is what the piece is called.
                    let destination = FileManager.default
                        .temporaryDirectory
                        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                    do {
                        try FileManager.default.createDirectory(
                            at: destination, withIntermediateDirectories: true)
                        let copy = destination.appending(path: url.lastPathComponent)
                        try FileManager.default.copyItem(at: url, to: copy)
                        continuation.resume(returning: copy)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

    }
}
