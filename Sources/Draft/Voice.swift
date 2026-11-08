import Foundation
import AVFoundation
import Speech
import Observation

/// Assistant voice: dictation with Apple's on-device recognizer only (requiresOnDeviceRecognition,
/// so audio never leaves the Mac) and answers read aloud with the system voice.
@MainActor @Observable
final class VoiceIO: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var listening = false
    private(set) var speaking = false
    var problem: String?
    /// 0…1, from the microphone while listening; drives the glow.
    @ObservationIgnored var level = 0.0

    @ObservationIgnored private let audio = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let synth = AVSpeechSynthesizer()

    override init() { super.init(); synth.delegate = self }

    func toggleListening(onText: @escaping (String) -> Void) {
        if listening { stopListening(); return }
        problem = nil
        guard let rec = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), rec.isAvailable else {
            problem = "Dictation isn't available for this language on this Mac."; return
        }
        guard rec.supportsOnDeviceRecognition else {
            problem = "On-device dictation isn't available for \(rec.locale.localizedString(forIdentifier: rec.locale.identifier) ?? "this language"). Draft won't send your voice to a server."
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { self.problem = "Allow Speech Recognition for Draft in System Settings › Privacy & Security to dictate."; return }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    Task { @MainActor in
                        guard ok else { self.problem = "Allow the microphone for Draft in System Settings › Privacy & Security to dictate."; return }
                        self.start(rec, onText: onText)
                    }
                }
            }
        }
    }

    private func start(_ rec: SFSpeechRecognizer, onText: @escaping (String) -> Void) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req
        let input = audio.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buf, _ in
            req.append(buf)
            guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buf.frameLength) { sum += ch[i] * ch[i] }
            let rms = Double(sqrt(sum / Float(buf.frameLength)))
            Task { @MainActor in self?.level = min(1, rms * 12) }
        }
        do { audio.prepare(); try audio.start() } catch { problem = "The microphone couldn't start: \(error.localizedDescription)"; input.removeTap(onBus: 0); return }
        listening = true
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                if let t = result?.bestTranscription.formattedString { onText(t) }
                if error != nil || result?.isFinal == true { self?.stopListening() }
            }
        }
    }

    func stopListening() {
        guard listening else { return }
        audio.stop(); audio.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.finish()
        request = nil; task = nil
        listening = false; level = 0
    }

    func speak(_ text: String) {
        if speaking { synth.stopSpeaking(at: .immediate); return }
        let u = AVSpeechUtterance(string: text.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression))
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        speaking = true
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in self.level = 0.35 + Double((r.location * 7) % 10) / 20 }
    }
}
