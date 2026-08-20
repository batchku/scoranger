import AVFoundation
import Speech
import SwiftUI

/// Live speech-to-text for the chat input: press the mic to start, speak,
/// press again to stop. Streams the microphone through SFSpeechRecognizer and
/// publishes the running transcript so the view can mirror it into the draft.
@MainActor
final class SpeechDictation: ObservableObject {
    @Published var isRecording = false
    /// Best transcription of the current dictation session (grows/refines live).
    @Published var transcript = ""
    /// Permission or engine failure, phrased for the input placeholder.
    @Published var errorText: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        guard !isRecording else { return }
        errorText = nil
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.errorText = "Dictation is off — allow Speech Recognition in Settings"
                    return
                }
                let granted = await AVAudioApplication.requestRecordPermission()
                guard granted else {
                    self.errorText = "Dictation is off — allow the microphone in Settings"
                    return
                }
                self.beginSession()
            }
        }
    }

    func stop() {
        request?.endAudio()
        finishSession()
    }

    private func beginSession() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorText = "Speech recognition isn't available right now"
            return
        }
        self.recognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            // capture the request directly: the tap fires on an audio thread
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        if self.isRecording { self.finishSession() }
                    }
                }
            }
        } catch {
            errorText = "Couldn't start dictation: \(error.localizedDescription)"
            finishSession()
        }
    }

    private func finishSession() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
