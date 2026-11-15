import AVFoundation
import Foundation
import RunalystCore
import WatchConnectivity
import WatchKit

// MARK: - Feedback Dispatcher

/// Multimodal feedback dispatcher delivering haptic taps and grounded voice cues on watchOS.
@MainActor
public final class FeedbackDispatcher: NSObject, AVSpeechSynthesizerDelegate {
    public static let shared = FeedbackDispatcher()

    public private(set) var latestAccentToken: PacingAccentToken = .neutral
    public private(set) var activeTactileCue: ActiveTactileCue?

    public var isTickerRunning: Bool {
        guard let task = tickerTask else { return false }
        return !task.isCancelled
    }

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var activeUtteranceID: ObjectIdentifier?
    private var lastHapticTime: TimeInterval = 0.0
    private let minHapticInterval: TimeInterval = 1.5
    private var tickerTask: Task<Void, Never>?

    /// Injectable haptic player closure for testing or previews.
    var hapticPlayer: @MainActor (WKHapticType) -> Void = { type in
        WKInterfaceDevice.current().play(type)
    }

    override private init() {
        super.init()
        speechSynthesizer.delegate = self
        speechSynthesizer.usesApplicationAudioSession = true
    }

    deinit {
        tickerTask?.cancel()
    }

    // MARK: - Public Dispatch Interface

    /// Dispatches multimodal feedback for emitted pacing events and synchronizes the active tactile cue.
    public func dispatch(events: [PacingEvent], activeTactileCue: ActiveTactileCue?) {
        updateTactileCue(activeTactileCue)
        dispatchDiscreteEvents(events)
    }

    /// Dispatches multimodal feedback for emitted pacing events and binds to display state tactile cues.
    public func dispatch(events: [PacingEvent], display: PacingDisplayState) {
        dispatch(events: events, activeTactileCue: display.activeTactileCue)
    }

    /// Dispatches multimodal feedback for emitted pacing events.
    /// Synchronizes active tactile cues from `PacingViewModel.shared` when present.
    public func dispatch(events: [PacingEvent]) {
        if PacingViewModel.shared.isPaused {
            stopTactileTicker()
        } else {
            updateTactileCue(PacingViewModel.shared.displayState.activeTactileCue)
        }
        dispatchDiscreteEvents(events)
    }

    /// Updates the duty-cycled tactile ticker task based on the provided active tactile cue.
    ///
    /// Silences the ticker immediately when `cue` is `nil` (lock-in, pause, cooldown, or end).
    /// Updates BPM and intervals smoothly without restarting the loop when cue mode is unchanged.
    public func updateTactileCue(_ cue: ActiveTactileCue?) {
        guard let newCue = cue else {
            stopTactileTicker()
            return
        }

        if let currentCue = self.activeTactileCue, let task = tickerTask, !task.isCancelled {
            if currentCue.mode == newCue.mode {
                // Same mode: smoothly update cue properties so the running loop adapts
                // on the next iteration without restarting the task or phase jitter.
                self.activeTactileCue = newCue
                return
            }
        }

        startTicker(for: newCue)
    }

    /// Stops and cancels the active tactile ticker immediately.
    public func stopTactileTicker() {
        tickerTask?.cancel()
        tickerTask = nil
        activeTactileCue = nil
    }

    /// Cleanly stops the tactile ticker during workout pause.
    public func pauseTactileTicker() {
        stopTactileTicker()
    }

    /// Resets all feedback state, cancelling audio and active tactile loops.
    public func reset() {
        stopTactileTicker()
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        activeUtteranceID = nil
        latestAccentToken = .neutral
    }

    // MARK: - Discrete Event Dispatching

    private func dispatchDiscreteEvents(_ events: [PacingEvent]) {
        guard !events.isEmpty else { return }

        let useMetric = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool
            ?? (Locale.current.measurementSystem == .metric)
        let voiceCuesEnabled = UserDefaults.standard.object(forKey: "watchVoiceCuesEnabled") as? Bool ?? true

        for event in events {
            let spec = event.feedbackSpec(useMetricSystem: useMetric)
            self.latestAccentToken = spec.accentToken
            playHaptic(spec.haptic)

            if voiceCuesEnabled,
               let cueText = spec.voiceCueText,
               !cueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                playVoiceCue(cueText)
            }
        }
    }

    // MARK: - Discrete Haptics

    private func playHaptic(_ semantic: PacingHapticSemantic) {
        guard semantic != .none else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHapticTime >= minHapticInterval else { return }
        lastHapticTime = now

        switch semantic {
        case .none:
            break
        case .directionUp:
            playHapticType(.directionUp)
        case .directionDown:
            playHapticType(.directionDown)
        case .retry:
            playHapticType(.retry)
        case .success:
            playHapticType(.success)
        case .subtleConfirmation:
            playHapticType(.click)
        case .ascendingDoublePulse:
            playHapticType(.directionUp)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 140_000_000)
                self?.playHapticType(.directionUp)
            }
        case .threeQuickLightTaps:
            playHapticType(.click)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 110_000_000)
                self?.playHapticType(.click)
                try? await Task.sleep(nanoseconds: 110_000_000)
                self?.playHapticType(.click)
            }
        case .descendingDoublePulse:
            playHapticType(.directionDown)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 160_000_000)
                self?.playHapticType(.directionDown)
            }
        }
    }

    private func playHapticType(_ type: WKHapticType) {
        hapticPlayer(type)
    }

    // MARK: - Duty-Cycled Tactile Ticker Loop

    private func startTicker(for cue: ActiveTactileCue) {
        stopTactileTicker()
        self.activeTactileCue = cue

        tickerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var nextTick = clock.now

            while !Task.isCancelled {
                guard let currentCue = self.activeTactileCue else { break }

                do {
                    try await self.playTickerPattern(for: currentCue.mode, clock: clock)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }

                guard let latestCue = self.activeTactileCue, latestCue.mode == currentCue.mode else {
                    break
                }

                let interval = self.tickerIntervalSeconds(for: latestCue)
                guard interval > 0 else { break }

                nextTick += .seconds(interval)
                let now = clock.now
                if nextTick < now {
                    nextTick = now + .seconds(interval)
                }

                do {
                    try await clock.sleep(until: nextTick)
                } catch {
                    break
                }
            }

            if self.tickerTask?.isCancelled == false {
                self.tickerTask = nil
                self.activeTactileCue = nil
            }
        }
    }

    private func playTickerPattern(for mode: TactileCueMode, clock: ContinuousClock) async throws {
        switch mode {
        case .cadenceMetronome:
            playHapticType(.click)
        case .effortDown:
            playHapticType(.directionDown)
            try await clock.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            playHapticType(.directionDown)
        case .effortUp:
            playHapticType(.directionUp)
            try await clock.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            playHapticType(.directionUp)
        }
    }

    private func tickerIntervalSeconds(for cue: ActiveTactileCue) -> TimeInterval {
        switch cue.mode {
        case .cadenceMetronome:
            if let bpm = cue.targetBPM, bpm > 0 {
                return 60.0 / Double(bpm)
            }
            if let pulseInterval = cue.pulseIntervalSeconds, pulseInterval > 0 {
                return pulseInterval
            }
            return 60.0 / 160.0
        case .effortDown, .effortUp:
            if let pulseInterval = cue.pulseIntervalSeconds, pulseInterval > 0 {
                return pulseInterval
            }
            return SteppedMetronomeRamp.effortPulseIntervalSeconds
        }
    }

    // MARK: - Audio Cue Playback

    private func playVoiceCue(_ text: String) {
        let localizedText = String(localized: String.LocalizationValue(text))
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en-US"

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )

        let hasBluetoothHeadphoneRoute = audioSession.currentRoute.outputs.contains {
            [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones].contains($0.portType)
        }

        let isCompanionReachable = WCSession.isSupported()
            && WCSession.default.activationState == .activated
            && WCSession.default.isReachable

        let target = WatchVoiceDeliveryTarget.resolve(
            watchHasBluetoothHeadphoneRoute: hasBluetoothHeadphoneRoute,
            isCompanionReachable: isCompanionReachable
        )

        switch target {
        case .companionRelayWithLocalFallback:
            Self.sendVoiceCueRelay(
                to: WCSession.default,
                text: localizedText,
                language: languageCode
            ) {
                Task { @MainActor [weak self] in
                    self?.speakLocally(localizedText, language: languageCode)
                }
            }
        case .watchLocal:
            speakLocally(localizedText, language: languageCode)
        }
    }

    nonisolated private static func sendVoiceCueRelay(
        to session: WCSession,
        text: String,
        language: String,
        onFallback: @escaping @Sendable () -> Void
    ) {
        session.sendMessage(
            ["voiceCueText": text, "voiceCueLanguage": language],
            replyHandler: { reply in
                let spoken = (reply["spoken"] as? Bool) ?? false
                if !spoken {
                    onFallback()
                }
            },
            errorHandler: { _ in
                onFallback()
            }
        )
    }

    private func speakLocally(_ localizedText: String, language languageCode: String) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try audioSession.setActive(true, options: [])
        } catch {
            // Audio session setup failed; safely proceed without crash
        }

        let utterance = AVSpeechUtterance(string: localizedText)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)

        activeUtteranceID = ObjectIdentifier(utterance)

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        speechSynthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.activeUtteranceID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.activeUtteranceID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
