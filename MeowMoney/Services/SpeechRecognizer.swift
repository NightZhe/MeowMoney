import Foundation
import Speech
import AVFoundation
import Observation

/// 中文（zh-TW）即時語音辨識。支援裝置端辨識（可離線、不上傳），
/// 並在偵測到使用者停頓 1.6 秒後自動收工。
@MainActor
@Observable
final class SpeechRecognizer {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case denied(String)
        case failed(String)

        var isListening: Bool { self == .listening }
    }

    private(set) var state: State = .idle
    /// 即時逐字稿（含尚未定稿的部分）。
    private(set) var transcript: String = ""
    /// 目前音量（0...1），給波形動畫用。
    private(set) var level: Double = 0

    /// 停頓自動結束後呼叫，參數是最終逐字稿。
    var onFinish: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscriptChange = Date()

    private let silenceTimeout: TimeInterval = 1.6

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - 權限

    /// 同時要到語音辨識與麥克風權限。任一被拒就回 false。
    func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            state = .denied("需要「語音辨識」權限才能聽你說話。請到 設定 › 喵喵記帳 打開。")
            return false
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            state = .denied("需要「麥克風」權限才能錄音。請到 設定 › 喵喵記帳 打開。")
            return false
        }

        return true
    }

    // MARK: - 開始 / 結束

    func start() async {
        guard state != .listening, state != .preparing else { return }
        state = .preparing
        transcript = ""
        level = 0

        guard await requestPermissions() else { return }

        guard let recognizer, recognizer.isAvailable else {
            state = .failed("目前無法使用中文語音辨識，請確認裝置語言與網路後再試。")
            return
        }

        do {
            try configureAudioSession()
        } catch {
            state = .failed("無法啟動麥克風：\(error.localizedDescription)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 支援裝置端辨識時就用它：不需網路、語音不離開裝置。
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        if #available(iOS 16.0, *) {
            request.addsPunctuation = false
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let power = Self.averagePower(of: buffer)
            Task { @MainActor [weak self] in
                self?.level = power
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .failed("無法啟動錄音：\(error.localizedDescription)")
            cleanUp()
            return
        }

        lastTranscriptChange = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.transcript {
                        self.transcript = text
                        self.lastTranscriptChange = Date()
                    }
                    if result.isFinal {
                        self.finish()
                    }
                } else if error != nil, self.state.isListening {
                    // 停頓或逾時造成的結束，一律當成正常收工。
                    self.finish()
                }
            }
        }

        state = .listening
        startSilenceWatcher()
    }

    /// 使用者主動按下停止。
    func stop() {
        guard state == .listening || state == .preparing else { return }
        finish()
    }

    /// 放棄本次辨識，不觸發 onFinish。
    func cancel() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        cleanUp()
        transcript = ""
        state = .idle
    }

    private func finish() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let text = transcript
        cleanUp()
        state = .idle
        level = 0
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onFinish?(text)
        }
    }

    private func cleanUp() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 細節

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startSilenceWatcher() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state.isListening else { return }
                let quietFor = Date().timeIntervalSince(self.lastTranscriptChange)
                if !self.transcript.isEmpty, quietFor > self.silenceTimeout {
                    self.finish()
                }
            }
        }
    }

    /// 取 buffer 的平均音量，壓到 0...1 供動畫使用。
    private nonisolated static func averagePower(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += channel[i] * channel[i]
        }
        let rms = sqrt(sum / Float(count))
        // rms 大約落在 0...0.3，放大後夾在 0...1
        return Double(min(max(rms * 6, 0), 1))
    }
}
