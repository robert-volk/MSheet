import Foundation
import Speech
import AVFoundation

/// Drives on-device speech-to-text for the search field's mic button.
/// Uses `requiresOnDeviceRecognition` whenever the device/language supports
/// it, so a spoken search never leaves the phone — see the on-device
/// fallback note in `beginSession`.
@MainActor
final class DictationController: ObservableObject {
    enum PermissionState {
        case notDetermined, granted, denied
    }

    @Published private(set) var isRecording = false
    @Published var permissionState: PermissionState = .notDetermined
    @Published var errorMessage: String?
    @Published private(set) var isOnDeviceOnly = false

    var onPartialResult: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Auto-stops (and, since the search field is bound to `onPartialResult`,
    /// auto-searches) once this long passes with no new transcription —
    /// reset on every partial result, started the moment recording begins
    /// so silence from the very start also closes the mic instead of
    /// listening forever.
    private let silenceTimeout: TimeInterval = 1.0
    private var silenceTimer: Timer?

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        errorMessage = nil
        Task {
            let speechOK = await requestSpeechAuthorization()
            let micOK = await requestMicAuthorization()
            guard speechOK, micOK else {
                permissionState = .denied
                return
            }
            permissionState = .granted
            beginSession()
        }
    }

    func stop() {
        guard isRecording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't start the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep this phone-only when the language/device supports it; older
        // devices or uncommon languages silently fall back to Apple's
        // server-based recognizer if this stays false.
        isOnDeviceOnly = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = isOnDeviceOnly
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Couldn't start the microphone."
            return
        }

        isRecording = true
        resetSilenceTimer()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.onPartialResult?(result.bestTranscription.formattedString)
                    self.resetSilenceTimer()
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }
}
