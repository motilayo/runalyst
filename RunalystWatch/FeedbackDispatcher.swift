import AVFoundation
import Foundation
import RunalystCore
import WatchKit

// MARK: - Feedback Dispatcher

/// Multimodal feedback dispatcher delivering haptic taps and grounded voice cues on watchOS.
@MainActor
public final class FeedbackDispatcher: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = FeedbackDispatcher()

    public private(set) var latestAccentToken: PacingAccentToken = .neutral

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastHapticTime: TimeInterval = 0.0
    private let minHapticInterval: TimeInterval = 1.5

    override private init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    /// Dispatches multimodal feedback for emitted pacing events.
    public func dispatch(events: [PacingEvent]) {
        guard !events.isEmpty else { return }

        for event in events {
            let spec = event.feedbackSpec
            self.latestAccentToken = spec.accentToken
            playHaptic(spec.haptic)

            if UserDefaults.standard.bool(forKey: "watchVoiceCuesEnabled"),
               let cueText = spec.voiceCueText {
                playVoiceCue(cueText)
            }
        }
    }

    // MARK: - Haptics

    private func playHaptic(_ semantic: PacingHapticSemantic) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHapticTime >= minHapticInterval else { return }

        let hapticType: WKHapticType? = {
            switch semantic {
            case .directionUp:
                return .directionUp
            case .directionDown:
                return .directionDown
            case .retry:
                return .retry
            case .success:
                return .success
            case .none:
                return nil
            }
        }()

        if let hapticType {
            WKInterfaceDevice.current().play(hapticType)
            lastHapticTime = now
        }
    }

    // MARK: - Audio Cue Playback

    private func playVoiceCue(_ text: String) {
        let localizedText = String(localized: String.LocalizationValue(text))
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            // Audio session setup failed; safely proceed without crash
        }

        let utterance = AVSpeechUtterance(string: localizedText)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        speechSynthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
