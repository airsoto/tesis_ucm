import AVFoundation
import Combine
import Foundation

@MainActor
final class ReaderSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String, rate: Double) {
        if isPaused {
            if synthesizer.continueSpeaking() { isPaused = false }
        } else if isSpeaking {
            if synthesizer.pauseSpeaking(at: .immediate) { isPaused = true }
        } else {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate))
            currentUtterance = utterance
            isSpeaking = true
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finish(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finish(utterance)
    }

    private nonisolated func finish(_ utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let currentUtterance, ObjectIdentifier(currentUtterance) == identifier else { return }
            self.currentUtterance = nil
            isSpeaking = false
            isPaused = false
        }
    }
}
