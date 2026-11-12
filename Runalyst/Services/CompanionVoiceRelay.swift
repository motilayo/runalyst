import AVFoundation
import Foundation

/// Companion AirPods Voice Relay service for synthesizing speech on iOS when headphones are connected.
///
/// Designed to receive real-time coaching cues relayed from Apple Watch and speak them into
/// connected headphones (e.g. AirPods) without blasting audio out of the phone speaker.
@MainActor
public final class CompanionVoiceRelay: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = CompanionVoiceRelay()

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var activeUtteranceID: ObjectIdentifier?

    override private init() {
        super.init()
        speechSynthesizer.delegate = self
        speechSynthesizer.usesApplicationAudioSession = true
    }

    /// Speaks the given text if headphones are connected to the iOS device.
    ///
    /// - Parameters:
    ///   - text: The voice cue text to speak.
    ///   - language: The BCP 47 language code for speech synthesis (defaults to system language or "en-US").
    /// - Returns: `true` if headphones were connected and speech was initiated, `false` otherwise.
    @discardableResult
    public func speakIfHeadphonesConnected(text: String, language: String? = nil) -> Bool {
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
        } catch {
            return false
        }

        let headphonePorts: [AVAudioSession.Port] = [
            .bluetoothA2DP,
            .bluetoothHFP,
            .bluetoothLE,
            .headphones
        ]
        let hasHeadphones = audioSession.currentRoute.outputs.contains { output in
            headphonePorts.contains(output.portType)
        }

        guard hasHeadphones else { return false }

        do {
            try audioSession.setActive(true, options: [])
        } catch {
            return false
        }

        let utterance = AVSpeechUtterance(string: text)
        let resolvedLanguage = language ?? Locale.current.language.languageCode?.identifier ?? "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: resolvedLanguage)

        activeUtteranceID = ObjectIdentifier(utterance)

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        speechSynthesizer.speak(utterance)
        return true
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.handleUtteranceCompleted(utteranceID)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.handleUtteranceCompleted(utteranceID)
        }
    }

    private func handleUtteranceCompleted(_ utteranceID: ObjectIdentifier) {
        guard utteranceID == activeUtteranceID else { return }
        activeUtteranceID = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
