import SwiftData
import SwiftUI
import WorkoutKit

/// Interactive chat view allowing athletes to converse with the AI Biomechanics Analyst.
struct AnalystChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @StateObject private var engine: AnalystChatEngine
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    enum SheetDestination: Identifiable {
        case readout(ActiveDrillReadoutItem)
        case drillsLibrary
        case explainer(MetricExplainerInfo)

        var id: String {
            switch self {
            case .readout(let item):
                return "readout_\(item.id)"
            case .drillsLibrary:
                return "drills_library"
            case .explainer(let info):
                return "explainer_\(info.id)"
            }
        }
    }

    @State private var activeSheet: SheetDestination?
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""
    @AppStorage("preferredWorkoutIsIndoor") private var preferredWorkoutIsIndoor: Bool = false

    let runRecord: RunRecord?
    let mode: AnalystChatMode

    init(runRecord: RunRecord? = nil, mode: AnalystChatMode? = nil, modelContext: ModelContext? = nil) {
        let resolvedMode = mode ?? (runRecord == nil ? .macroCoach : .runInspection)
        self.runRecord = runRecord
        self.mode = resolvedMode
        _engine = StateObject(wrappedValue: AnalystChatEngine(modelContext: modelContext ?? runRecord?.modelContext, runRecord: runRecord, mode: resolvedMode))
    }

    private var headerSubtitle: String {
        if mode == .macroCoach {
            if let latest = runRecords.first {
                let cal = Calendar.current
                let isRunToday = cal.isDateInToday(latest.date)
                let typeStr = latest.detectedTypeRaw.isEmpty ? "Run" : latest.detectedTypeRaw
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, MMM d"
                let dateStr = formatter.string(from: latest.date)
                if isRunToday {
                    return "🔒 On-Device • Today's \(typeStr) Logged"
                } else {
                    return "🔒 On-Device • Last Run: \(dateStr)"
                }
            } else {
                return "🔒 On-Device • Daily Training Guidance"
            }
        } else if let runRecord {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, MMM d"
            let dateStr = formatter.string(from: runRecord.date)
            let isIndoor = runRecord.isIndoor ?? false
            let envStr = isIndoor ? "Indoor" : "Outdoor"
            let typeStr = runRecord.detectedTypeRaw.isEmpty ? "Run" : runRecord.detectedTypeRaw
            return "🔒 On-Device • \(dateStr) \(envStr) \(typeStr)"
        } else {
            return "🔒 On-Device • Daily Training Guidance"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 34))
                .foregroundStyle(.purple.gradient)
            Text(mode == .macroCoach ? "Ask Your AI Coach" : "Ask about this run")
                .font(.system(.headline, design: .rounded))
            Text(mode == .macroCoach
                ? "Readiness, today's workout, recovery, or training guidance from your Health data."
                : "Pace, heart rate, cadence, recovery. Answered on-device from your Health data.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Subtitle: Run Context & Privacy
                HStack(spacing: 6) {
                    Text(headerSubtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.6))

                // Messages ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if engine.messages.isEmpty && !engine.isResponding {
                                emptyState
                            }

                            ForEach(engine.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if engine.isResponding {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.purple)
                                    Text("Looking over your run...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .id("loading_bubble")
                            }

                            Color.clear
                                .frame(height: 28)
                                .id("bottom_anchor")
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        dismissKeyboard()
                    }
                    .onChange(of: engine.messages.count) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                proxy.scrollTo("bottom_anchor", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isInputFocused) { _, focused in
                        if focused {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                proxy.scrollTo("bottom_anchor", anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Bottom Thumb-Zone: Quick Chips + Text Input Bar
                VStack(spacing: 8) {
                    if !engine.isResponding && !isInputFocused && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if engine.messages.isEmpty {
                            quickPromptChips
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else if engine.messages.last?.sender == .analyst {
                            followUpPromptChips
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }

                    // Text Input Bar
                    HStack(spacing: 10) {
                        TextField("Ask about pace, heart rate, cadence...", text: $inputText)
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                            .focused($isInputFocused)
                            .onSubmit {
                                submitQuestion()
                            }

                        if isInputFocused {
                            Button {
                                dismissKeyboard()
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Dismiss keyboard")
                            .transition(.scale.combined(with: .opacity))
                        }

                        Button {
                            submitQuestion()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color(UIColor.tertiaryLabel) : .purple)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || engine.isResponding)
                        .accessibilityLabel("Send message to coach")
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isInputFocused)
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissKeyboard()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $activeSheet) { destination in
                switch destination {
                case .readout(let item):
                    DrillInterstitialReadoutView(
                        readout: item.readout,
                        workoutPlan: item.plan,
                        prescriptionDTO: item.dto,
                        onCommitToWatch: { _, dto in
                            self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                            self.lastExportedDrillId = dto.preRunDrillId ?? ""
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)

                case .drillsLibrary:
                    NavigationStack {
                        DrillsLibraryView()
                    }

                case .explainer(let info):
                    GlassBoxExplainerSheet(info: info)
                }
            }
            .task {
                engine.setModelContextIfNeeded(modelContext)
                if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_ACTIVE" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("How was my cadence and rhythm during this run?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isInputFocused = true
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_READ" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("Did my heart rate stay steady, or did I start tiring out?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_EFFORT" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("How was my effort?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_IMPROVE" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("What can I improve?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_MULTI" {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await engine.sendMessage("How was my effort?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await engine.sendMessage("Which part of my form should I focus on improving in my next run?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_ARM_DRIVE" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("How does arm drive help?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_DEGRADATION" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("Did you notice any degradation in my performance towards the end of my run?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_WEAKNESS" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("What's my weak point?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_SPLIT_GRADE" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("Grade my performance in each split of this run")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                } else if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "ANALYST_MACRO" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await engine.sendMessage("When should I run next, and what kind of session should I focus on?")
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    dismissKeyboard()
                }
            }
        }
    }

    private func messageBubble(_ message: AnalystChatMessage) -> some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.purple.opacity(0.25), radius: 4, x: 0, y: 2)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            } else {
                if case .failed(let retryPrompt) = message.status {
                    failedMessageCard(message: message, retryPrompt: retryPrompt)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(TelemetryHighlighter.highlight(message.text))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 1)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = message.text
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }

                        if let session = message.attachedSession {
                            let isSessionToday: Bool = {
                                if let label = session.dayLabel {
                                    return label.caseInsensitiveCompare("Today") == .orderedSame
                                }
                                return session.isToday || !isRunToday
                            }()
                            PrescribedSessionCardView(
                                session: session,
                                isToday: isSessionToday,
                                dayLabel: session.dayLabel,
                                preferredWorkoutIsIndoor: $preferredWorkoutIsIndoor,
                                onPreviewPrimer: {
                                    openPrimerReadout(for: session)
                                },
                                onPreviewMainRun: {
                                    openMainRunReadout(for: session)
                                }
                            )
                        }
                        if let schedule = message.attachedSchedule {
                            UpcomingScheduleCardView(microcycle: schedule)
                        }
                        if let drillId = message.attachedDrillId {
                            InlineChatDrillCard(
                                drillId: drillId,
                                runRecord: runRecord,
                                onOpenReadout: {
                                    openDrillReadout(drillId: drillId)
                                }
                            )
                        }
                        if let explainerKey = message.attachedExplainerKey {
                            InlineChatExplainerCard(
                                explainerKey: explainerKey,
                                runRecord: runRecord,
                                onOpenExplainer: { info in
                                    activeSheet = .explainer(info)
                                }
                            )
                        }
                    }
                }
                Spacer(minLength: 28)
            }
        }
        .padding(.horizontal)
    }

    private func failedMessageCard(message: AnalystChatMessage, retryPrompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.subheadline)
                Text("Analysis Interrupted")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            }

            Text(message.text)
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await engine.retryMessage(failedMessageId: message.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.purple)
                .clipShape(Capsule())
            }
            .padding(.top, 2)
            .accessibilityLabel("Retry analysis for \(retryPrompt)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 1)
    }

    private var quickPromptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let cal = Calendar.current
                let isRunToday = runRecords.first.map { cal.isDateInToday($0.date) } ?? false

                if mode == .macroCoach {
                    chipButton("When Should I Run Next?", icon: "figure.run", iconColor: Color(red: 0.0, green: 0.55, blue: 1.0)) {
                        inputText = "When should I run next, and what kind of session should I focus on?"
                        submitQuestion()
                    }
                    chipButton("Readiness & Recovery", icon: "heart.text.square.fill", iconColor: Color(red: 1.0, green: 0.18, blue: 0.55)) {
                        inputText = isRunToday
                            ? "How is my recovery looking after today's run?"
                            : "Am I recovered to run today, or should I take a rest day?"
                        submitQuestion()
                    }
                    if let latest = runRecords.first {
                        chipButton("Review Last Run", icon: "clock.arrow.circlepath", iconColor: Color(red: 0.18, green: 0.82, blue: 0.35)) {
                            let df = DateFormatter()
                            df.locale = Locale(identifier: "en_US_POSIX")
                            df.dateFormat = "EEEE"
                            let weekday = df.string(from: latest.date)
                            inputText = "How was my effort and pacing during \(weekday)'s \(latest.detectedTypeRaw)?"
                            submitQuestion()
                        }
                    }
                    chipButton("Weekly Training Status", icon: "calendar", iconColor: .purple) {
                        inputText = "How is my weekly mileage and overall training balance?"
                        submitQuestion()
                    }
                } else if let runRecord {
                    chipButton("When Should I Run Next?", icon: "calendar", iconColor: .purple) {
                        inputText = "When should I run next, and what kind of session should I focus on?"
                        submitQuestion()
                    }
                    chipButton("Stride Rhythm", icon: "waveform.path", iconColor: Color(red: 0.18, green: 0.82, blue: 0.35)) {
                        inputText = "How was my cadence and rhythm during this run?"
                        submitQuestion()
                    }
                    chipButton("Heart Rate Drift", icon: "heart.fill", iconColor: Color(red: 1.0, green: 0.18, blue: 0.55)) {
                        inputText = "Did my heart rate stay steady, or did I start tiring out?"
                        submitQuestion()
                    }
                    chipButton("Pacing Consistency", icon: "speedometer", iconColor: Color(red: 0.0, green: 0.55, blue: 1.0)) {
                        inputText = "What does pacing consistency mean, and how was my pacing?"
                        submitQuestion()
                    }
                    if runRecord.evaluationModality == .intervals {
                        let intervalTitle = runRecord.detectedTypeRaw == "Fartlek" ? "Surge Analysis" : "Break Down Intervals"
                        chipButton(intervalTitle, icon: "repeat", iconColor: Color(red: 0.0, green: 0.55, blue: 1.0)) {
                            inputText = "Grade my performance in each interval of this run"
                            submitQuestion()
                        }
                    }
                    if runRecord.isIndoor == true {
                        chipButton("Treadmill Form", icon: "figure.run", iconColor: Color(red: 0.18, green: 0.82, blue: 0.35)) {
                            inputText = "Did I overstride or reach too far on the treadmill?"
                            submitQuestion()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var followUpPromptChips: some View {
        let askedText = engine.messages
            .filter { $0.sender == .user }
            .map { $0.text.lowercased() }
            .joined(separator: " ")

        let isInterval = runRecord?.evaluationModality == .intervals
        let splitChipTitle = isInterval ? ((runRecord?.detectedTypeRaw == "Fartlek") ? "Surge Analysis" : "Break Down Intervals") : "Break Down Splits"
        let splitChipPrompt = isInterval ? "Grade my performance in each interval of this run" : "Grade my performance in each split of this run"
        let splitChipIcon = isInterval ? "waveform.path.ecg" : "chart.bar.xaxis"

        let isMacro = (mode == .macroCoach) || (runRecord == nil)

        let candidates: [(title: String, prompt: String, icon: String, color: Color)]
        if isMacro {
            candidates = [
                ("Weekly Schedule", "What does my training schedule look like for the rest of the week?", "calendar", .purple),
                ("Tomorrow's Plan", "Should I run tomorrow, and what kind of session should I focus on?", "calendar.badge.clock", .purple),
                ("Training Readiness", "How is my recovery status and overall training load looking?", "heart.text.square.fill", Color(red: 1.0, green: 0.18, blue: 0.55)),
                ("Recommended Drill", "Which drill would help improve my running form and cadence?", "figure.run", Color(red: 0.18, green: 0.82, blue: 0.35)),
                ("What to Improve", "What is the key area I should focus on improving right now?", "arrow.up.forward.circle", .orange),
                ("Training Balance", "How is my weekly mileage and overall training balance?", "chart.bar.fill", Color(red: 0.0, green: 0.55, blue: 1.0))
            ].filter { item in
                let titleLower = item.title.lowercased()
                let promptLower = item.prompt.lowercased()
                if titleLower.contains("tomorrow") && (askedText.contains("tomorrow") || askedText.contains("next run") || askedText.contains("run next") || askedText.contains("when should i run")) {
                    return false
                }
                if titleLower.contains("schedule") && (askedText.contains("schedule") || askedText.contains("calendar")) {
                    return false
                }
                return !askedText.contains(titleLower) && !askedText.contains(promptLower)
            }
        } else {
            candidates = [
                ("Tomorrow's Plan", "Should I run tomorrow, and what kind of session should I focus on?", "calendar", .purple),
                (splitChipTitle, splitChipPrompt, splitChipIcon, Color(red: 0.0, green: 0.55, blue: 1.0)),
                ("Recommended Drill", "Which drill would help improve my running form and cadence?", "figure.run", Color(red: 0.18, green: 0.82, blue: 0.35)),
                ("What to Improve", "What is the key area I should focus on improving?", "arrow.up.forward.circle", .orange),
                ("Running Economy", "How was my running economy and stride efficiency during this run?", "bolt.heart", Color(red: 1.0, green: 0.18, blue: 0.55)),
                ("Arm Drive", "How does arm drive help with rhythm and form?", "figure.walk", Color(red: 0.18, green: 0.82, blue: 0.35))
            ].filter { item in
                !askedText.contains(item.title.lowercased()) && !askedText.contains(item.prompt.lowercased())
            }
        }

        return Group {
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested follow-ups")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(candidates.prefix(4), id: \.title) { item in
                                chipButton(item.title, icon: item.icon, iconColor: item.color) {
                                    inputText = item.prompt
                                    submitQuestion()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private func chipButton(_ title: String, icon: String = "sparkle", iconColor: Color = .purple, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissKeyboard()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(iconColor.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
            .contentShape(Rectangle())
        }
    }

    private func submitQuestion() {
        let question = inputText.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        inputText = ""
        dismissKeyboard()
        Task {
            await engine.sendMessage(question)
        }
    }

    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openDrillReadout(drillId: PreRunDrillId) {
        let matchingRec = runRecord?.insight?.drillRecommendations?.first { rec in
            rec.preRunDrillId == drillId.rawValue ||
            rec.drillTitle.localizedCaseInsensitiveContains(drillId.title)
        }
        let template = DrillTemplate.template(for: drillId)
        let fallbackCadence = runRecords.first.map { Int($0.workingAvgCadence) } ?? 155
        let baseline = matchingRec?.previousCadence ?? ((runRecord.map { Int($0.workingAvgCadence) } ?? fallbackCadence) > 0 ? (runRecord.map { Int($0.workingAvgCadence) } ?? fallbackCadence) : 155)
        let target = matchingRec?.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? template.calculateTargetCadence(baseline)
        let cue = matchingRec?.drillCues ?? template.generateInstructionalCue(target)

        let resolvedTitle = drillId == .aerobicFlush ? "Zone 1 Recovery Flush" : (matchingRec?.formattedTitle ?? drillId.title)

        let dto = DrillPrescriptionDTO(
            title: resolvedTitle,
            preRunDrillId: drillId.rawValue,
            purpose: matchingRec?.drillPurpose ?? template.defaultPurpose,
            targetCadence: target,
            previousCadence: baseline > 0 ? baseline : nil,
            durationMinutes: drillId.defaultDuration.rawValue
        )
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeSheet = .readout(ActiveDrillReadoutItem.adaptive(
            dto: dto,
            readiness: readiness,
            customCoachingTip: cue.isEmpty ? nil : cue
        ))
    }

    private var isRunToday: Bool {
        guard let latest = runRecords.first else { return false }
        return Calendar.current.isDateInToday(latest.date)
    }

    private func openPrimerReadout(for session: PrescribedDailySession) {
        let state = session.resolvedReadinessState
        let dto = DrillPrescriptionDTO(
            title: session.primerDrillTitle,
            preRunDrillId: session.primerDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: session.primerTargetCadence,
            previousCadence: session.cadenceFloor,
            durationMinutes: session.primerDrillId.defaultDuration.rawValue,
            hapticMode: "On",
            readinessState: state == .productive ? nil : state.rawValue,
            isIndoor: preferredWorkoutIsIndoor
        )
        activeSheet = .readout(ActiveDrillReadoutItem.fromPrescription(
            dto: dto,
            customCoachingTip: session.groundedRationale
        ))
    }

    private func openMainRunReadout(for session: PrescribedDailySession) {
        let mainDrillId = session.mainSessionTemplateId
        let state = session.resolvedReadinessState
        let dto = DrillPrescriptionDTO(
            title: session.sessionTitle,
            preRunDrillId: mainDrillId.rawValue,
            purpose: session.groundedRationale,
            targetCadence: mainDrillId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            previousCadence: session.cadenceFloor,
            durationMinutes: session.mainRunDurationMinutes,
            hapticMode: "On",
            readinessState: state == .productive ? nil : state.rawValue,
            isIndoor: preferredWorkoutIsIndoor
        )
        activeSheet = .readout(ActiveDrillReadoutItem.fromPrescription(
            dto: dto,
            customCoachingTip: session.groundedRationale
        ))
    }
}

/// An inline, interactive card surfaced directly inside chat messages when a corrective drill is recommended.
struct InlineChatDrillCard: View {
    let drillId: PreRunDrillId
    let runRecord: RunRecord?
    let onOpenReadout: () -> Void

    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @AppStorage("preferredWorkoutIsIndoor") private var preferredWorkoutIsIndoor: Bool = false

    private var effectiveRun: RunRecord? {
        runRecord ?? runRecords.first
    }

    private var matchingDrillRec: DrillRecommendation? {
        effectiveRun?.insight?.drillRecommendations?.first { rec in
            rec.preRunDrillId == drillId.rawValue ||
            rec.drillTitle.localizedCaseInsensitiveContains(drillId.title)
        }
    }

    private var baselineCadence: Int {
        if let recCad = matchingDrillRec?.previousCadence, recCad > 0 {
            return recCad
        }
        if let working = effectiveRun?.workingAvgCadence, working > 0 {
            return Int(working)
        }
        return 155
    }

    private var targetCadenceDisplay: String {
        let template = DrillTemplate.template(for: drillId)
        let rawTarget = matchingDrillRec?.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? template.calculateTargetCadence(baselineCadence)
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        let adapted = ReadinessModifier.adaptTarget(rawTarget, baselineCadence: baselineCadence, drillId: drillId, state: readiness.state)
        return adapted.targetCadence ?? rawTarget
    }

    private var displayTitle: String {
        if drillId == .aerobicFlush {
            return "Zone 1 Recovery Flush"
        }
        let title = matchingDrillRec?.formattedTitle ?? ""
        return title.isEmpty ? drillId.title : title
    }

    private var currentPrescription: LockedTrainingPrescription? {
        guard drillId.isAerobicContinuous else { return nil }
        let useMetric = (UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool) ?? true
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        let timeline = RecoveryTimeline.build(
            runs: runRecords.map { ReadinessRunSnapshot(run: $0) },
            readiness: readiness,
            now: Date()
        )
        let profile = RunnerProfile.compute(from: runRecords)
        let pace = (effectiveRun?.workingAvgPace ?? 0) > 0 ? effectiveRun?.workingAvgPace : nil
        let daysDiff = effectiveRun.map { Calendar.current.dateComponents([.day], from: $0.date, to: Date()).day ?? 0 } ?? 0
        let tzInput = TrainingZoneInput(
            baselinePaceSec: pace,
            workoutPaceSec: pace,
            activeGoal: UserDefaults.standard.string(forKey: "trainingGoal") ?? "Base Building",
            experienceLevel: profile.experienceLevel,
            readyForHard: timeline.readyForHard,
            daysSinceWorkout: daysDiff,
            heightAdjustedCadenceFloor: profile.heightAdjustedCadenceFloor,
            useMetricSystem: useMetric,
            totalHistoricalRunsCount: runRecords.count
        )
        return TrainingZoneEngine.computePrescription(tzInput, runs: runRecords)
    }

    private var durationDisplay: String {
        if let rx = currentPrescription, !rx.compactDurationBand.isEmpty && rx.compactDurationBand != "Rest Day" {
            return rx.compactDurationBand
        }
        return drillId.defaultDuration.title
    }

    private var targetBadgeText: String {
        if drillId == .zone2Run {
            return "Zone 2 HR"
        } else if drillId == .aerobicFlush || drillId == .recoveryJog {
            return "Zone 1 HR"
        } else if drillId.isHeartRateTargeted {
            return drillId.targetHeartRateZoneName ?? "Target HR"
        } else {
            return targetCadenceDisplay.contains("SPM") ? targetCadenceDisplay : "\(targetCadenceDisplay) SPM"
        }
    }

    private var resolvedDrillDuration: DrillDuration {
        if let rx = currentPrescription {
            let band = rx.compactDurationBand
            let digits = band.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let firstStr = digits.first, let firstVal = Int(firstStr) {
                let secondVal = digits.count > 1 ? (Int(digits[1]) ?? firstVal) : firstVal
                let targetMins = (firstVal + secondVal) / 2
                if targetMins >= 45 {
                    return .fiftyMinutes
                } else if targetMins >= 35 {
                    return .fortyMinutes
                } else if targetMins >= 25 {
                    return .thirtyMinutes
                } else if targetMins >= 12 {
                    return .fifteenMinutes
                } else if targetMins >= 8 {
                    return .tenMinutes
                } else {
                    return .fiveMinutes
                }
            }
        }
        return drillId.defaultDuration
    }

    private var targetBadgeColor: Color {
        drillId.isHeartRateTargeted ? Color(red: 1.0, green: 0.18, blue: 0.55) : Color(red: 0.0, green: 0.8, blue: 0.65)
    }

    var body: some View {
        let drill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadenceDisplay,
            duration: resolvedDrillDuration,
            isIndoor: preferredWorkoutIsIndoor
        )
        let phases = drill.generatePhases()
        let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })

        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Icon badge + Category + Duration Capsule + Preview Button
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(drillId.iconColor.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: drillId.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(drillId.iconColor)
                    }

                    Text(drillId.isHeartRateTargeted ? "AEROBIC RUN" : "TECHNIQUE DRILL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(drillId.iconColor)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(durationDisplay.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(drillId.iconColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(drillId.iconColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenReadout()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 9, weight: .bold))
                        Text("Preview")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(UIColor.secondarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                }
            }

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Text(DrillTemplate.template(for: drillId).defaultPurpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // 2x2 Metric Grid (matching Main Run Card)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                chatMetricCell(
                    icon: "stopwatch.fill",
                    title: "Duration",
                    value: durationDisplay,
                    color: .secondary
                )
                chatMetricCell(
                    icon: drillId.isHeartRateTargeted ? "heart.fill" : "metronome.fill",
                    title: drillId.isHeartRateTargeted ? "Target HR" : "Cadence",
                    value: targetBadgeText,
                    color: targetBadgeColor
                )
                chatMetricCell(
                    icon: "repeat",
                    title: "Intervals",
                    value: drill.shortWorkSummary,
                    color: Color(red: 1.0, green: 0.58, blue: 0.0)
                )
                chatMetricCell(
                    icon: "figure.walk",
                    title: "Recovery",
                    value: drill.shortRecoverySummary,
                    color: Color(red: 0.20, green: 0.72, blue: 0.92)
                )
            }

            // Sleek 4pt Phase Mini-Bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(phases) { phase in
                            let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalDuration)
                            let w = max(4, (geo.size.width - CGFloat(phases.count - 1) * 2) * ratio)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(phase.kind.color)
                                .frame(width: w, height: 4)
                        }
                    }
                }
                .frame(height: 4)

                Text(drill.structureSummary)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func chatMetricCell(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// An inline, interactive educational card surfaced directly in chat messages
/// when an explainer or physiological concept is referenced.
struct InlineChatExplainerCard: View {
    let explainerKey: String
    let runRecord: RunRecord?
    let onOpenExplainer: (MetricExplainerInfo) -> Void

    private var asset: CoachingAssetLibrary.Asset {
        CoachingAssetLibrary.resolve(key: explainerKey) ?? CoachingAssetLibrary.defaultAsset(for: explainerKey)
    }

    private var accentColor: Color {
        switch asset.domain {
        case .cardio:
            return Color(red: 1.0, green: 0.18, blue: 0.55) // Neon Pink
        case .pacing:
            return Color(red: 0.0, green: 0.55, blue: 1.0)  // Electric Blue
        case .biomechanics:
            return Color(red: 0.18, green: 0.82, blue: 0.35) // Vibrant Green
        case .physiology:
            return .purple
        case .drills:
            return Color(red: 0.0, green: 0.8, blue: 0.65) // Drill Teal/Green
        case .physics, .system:
            return .orange
        }
    }

    private var iconName: String {
        switch asset.key {
        case "cadence", "cadence_floor", "target_cadence":
            return "waveform.path"
        case "vertical_oscillation", "vertical_ratio", "overstriding":
            return "arrow.up.and.down"
        case "ground_contact_time":
            return "stopwatch.fill"
        case "stride_length":
            return "ruler.fill"
        case "heart_rate", "zone_1_hr", "zone_2_hr":
            return "heart.fill"
        case "cardiac_drift":
            return "chart.line.uptrend.xyaxis"
        case "efficiency_factor":
            return "bolt.heart.fill"
        case "pace", "pacing_consistency":
            return "speedometer"
        case "recovery_timeline":
            return "bed.double.fill"
        case "training_load":
            return "chart.bar.fill"
        case "treadmill_physics":
            return "figure.run"
        case "vo2_max":
            return "lungs.fill"
        case "pre_run_primer", "cadence_pyramids", "rhythm_intervals", "tempo_surges", "strides":
            return "figure.run.square.stack.fill"
        default:
            return "info.circle.fill"
        }
    }

    private var liveMetricDisplay: String? {
        guard let run = runRecord else { return nil }
        switch asset.key {
        case "cadence_floor":
            let floor = RunnerProfile.compute(from: [run], now: run.date).heightAdjustedCadenceFloor
            return "\(floor) SPM Floor"
        case "cadence":
            let cad = Int(run.workingAvgCadence.rounded())
            return cad > 0 ? "\(cad) SPM" : nil
        case "pace":
            return run.workingAvgPace > 0 ? PaceFormatter.formatPace(secondsPerKilometer: run.workingAvgPace) : nil
        case "heart_rate":
            let hr = Int(run.workingAvgHeartRate.rounded())
            return hr > 0 ? "\(hr) BPM" : nil
        case "efficiency_factor":
            if let ef = run.efficiencyFactor {
                return String(format: "%.2f m/beat", ef)
            }
            return nil
        case "vertical_oscillation":
            if let vo = run.workingAvgVerticalOscillation ?? run.rawAvgVerticalOscillation {
                return String(format: "%.1f cm", vo)
            }
            return nil
        case "stride_length":
            if let sl = run.workingAvgStrideLength ?? run.rawAvgStrideLength {
                return String(format: "%.2f m", sl)
            }
            return nil
        case "bounce_ratio", "vertical_ratio":
            if let vr = run.verticalRatio {
                return String(format: "%.1f%%", vr * 100.0)
            }
            return nil
        case "pacing_consistency", "pace_cv":
            return String(format: "%.2f CV", run.paceCV)
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Icon + Title + Domain & Live Badge
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(asset.domain.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let live = liveMetricDisplay {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.caption2.bold())
                        Text(live)
                            .font(.caption2.bold().monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.15))
                    .foregroundColor(accentColor)
                    .clipShape(Capsule())
                }
            }

            // Compact Definition Box
            Text(asset.compactSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Primary Action Button (Sweaty Hands minimum 44pt height target)
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let info = CoachingAssetLibrary.explainerInfo(for: asset.key, userMetricDisplay: liveMetricDisplay) ?? MetricExplainerInfo(
                    title: asset.title,
                    mode: "Working Stats",
                    overview: asset.overview,
                    modeContext: asset.modeContext,
                    whyItMatters: asset.whyItMatters,
                    targetRange: asset.targetRange,
                    userMetricDisplay: liveMetricDisplay
                )
                onOpenExplainer(info)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.subheadline.weight(.semibold))
                    Text("Read Full Explainer & Guide")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color(UIColor.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}
