import SwiftUI

/// Interactive chat view allowing athletes to converse with the AI Biomechanics Analyst.
struct AnalystChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: AnalystChatEngine
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    let runRecord: RunRecord

    init(runRecord: RunRecord) {
        self.runRecord = runRecord
        _engine = StateObject(wrappedValue: AnalystChatEngine(runRecord: runRecord))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Disclaimer Banner
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2.bold())
                        .foregroundColor(.purple)
                    Text("AI Coach • Personal Workout Insights")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.06))

                // Messages ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(engine.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            // Starter chips shown inside the stream only during greeting phase
                            if engine.messages.count <= 1 {
                                quickPromptChips
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            } else if !engine.isResponding && engine.messages.last?.sender == .analyst {
                                followUpPromptChips
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                                .frame(height: 12)
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

                // Text Input Bar
                HStack(spacing: 10) {
                    TextField("Ask about pace, heart rate, cadence, or form...", text: $inputText)
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
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button {
                        submitQuestion()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color(UIColor.tertiaryLabel) : .purple)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || engine.isResponding)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isInputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
            .task {
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
                }
            }
        }
    }

    private func messageBubble(_ message: AnalystChatMessage) -> some View {
        HStack {
            if message.sender == .user {
                Spacer()
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
                    .frame(maxWidth: 290, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2.bold())
                            .foregroundColor(.purple)
                        Text("AI Coach")
                            .font(.caption2.bold())
                            .foregroundColor(.purple)
                    }

                    Text(TelemetryHighlighter.highlight(message.text))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
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
                .frame(maxWidth: 320, alignment: .leading)
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    private var quickPromptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("Why It Felt Challenging") {
                    inputText = "Why did this run feel challenging, and did my mechanics break down?"
                    submitQuestion()
                }
                chipButton("Running Economy") {
                    inputText = "How was my running economy and stride efficiency during this run?"
                    submitQuestion()
                }
                chipButton("Should I Run Tomorrow?") {
                    inputText = "Should I run tomorrow, and what kind of session should I focus on?"
                    submitQuestion()
                }
                chipButton("Goal Progress") {
                    inputText = "How does this workout build toward my current training goal?"
                    submitQuestion()
                }
                if runRecord.evaluationModality == .intervals {
                    chipButton("Break Down Intervals") {
                        inputText = "Grade my performance in each interval of this run"
                        submitQuestion()
                    }
                }
                if runRecord.isIndoor == true {
                    chipButton("Treadmill Form") {
                        inputText = "Did I overstride or reach too far on the treadmill?"
                        submitQuestion()
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

        let isInterval = runRecord.evaluationModality == .intervals
        let splitChipTitle = isInterval ? "Break Down Intervals" : "Break Down Splits"
        let splitChipPrompt = isInterval ? "Grade my performance in each interval of this run" : "Grade my performance in each split of this run"
        let splitChipIcon = isInterval ? "waveform.path.ecg" : "chart.bar.xaxis"

        let candidates: [(title: String, prompt: String, icon: String)] = [
            ("Tomorrow's Plan", "Should I run tomorrow, and what kind of session should I focus on?", "calendar"),
            (splitChipTitle, splitChipPrompt, splitChipIcon),
            ("Recommended Drill", "Which drill would help improve my running form and cadence?", "figure.run"),
            ("What to Improve", "What is the key area I should focus on improving?", "arrow.up.forward.circle"),
            ("Running Economy", "How was my running economy and stride efficiency during this run?", "bolt.heart"),
            ("Arm Drive", "How does arm drive help with rhythm and form?", "figure.walk")
        ].filter { item in
            !askedText.contains(item.title.lowercased()) && !askedText.contains(item.prompt.lowercased())
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
                                chipButton(item.title, icon: item.icon) {
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

    private func chipButton(_ title: String, icon: String = "sparkle", action: @escaping () -> Void) -> some View {
        Button {
            dismissKeyboard()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.purple)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.purple.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
        }
    }

    private func submitQuestion() {
        let question = inputText.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
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
}
