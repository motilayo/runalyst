import SwiftUI

/// Unified canonical prescribed session card shared across WorkoutsView and AnalystChatView.
/// Renders Pre-Run Primer + Main Run, or Rest & Structural Recovery with optional override.
struct PrescribedSessionCardView: View {
    let session: PrescribedDailySession
    var isToday: Bool?
    var dayLabel: String?
    @Binding var preferredWorkoutIsIndoor: Bool
    var onPreviewPrimer: (() -> Void)?
    var onPreviewMainRun: (() -> Void)?
    var onScheduleFlushOverride: (() -> Void)?

    private var effectiveIsToday: Bool {
        if let isToday {
            return isToday
        }
        if session.isToday {
            return true
        }
        if let label = dayLabel ?? session.dayLabel {
            return label.caseInsensitiveCompare("Today") == .orderedSame
        }
        return false
    }

    private var headerDayText: String {
        if effectiveIsToday {
            return "Today"
        } else if let label = dayLabel ?? session.dayLabel, !label.isEmpty {
            return label
        } else {
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE"
            return formatter.string(from: tomorrow)
        }
    }

    private var timingBadgeIcon: String {
        effectiveIsToday ? "sparkles" : "calendar.badge.clock"
    }

    private var timingBadgeColor: Color {
        effectiveIsToday ? Color(red: 0.0, green: 0.75, blue: 0.65) : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Header Bar: Scheduled Day/Environment on left, Target Goal on right
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: timingBadgeIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(timingBadgeColor)

                    Text(headerDayText)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)

                    // Indoor / Outdoor Quick Toggle
                    Button {
                        preferredWorkoutIsIndoor.toggle()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "sun.max.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(preferredWorkoutIsIndoor ? "Indoor" : "Outdoor")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(preferredWorkoutIsIndoor ? .purple : .blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((preferredWorkoutIsIndoor ? Color.purple : Color.blue).opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Text(session.targetGoal)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 4)
            }

            // 2. Title & Grounded Rationale
            VStack(alignment: .leading, spacing: 4) {
                Text(session.sessionTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Text(session.groundedRationale)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.isRestDay {
                restDayContent
            } else {
                activeSessionContent
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Rest Day Content

    private var restDayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("STRUCTURAL RECOVERY & ADAPTATION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.teal)

                    Text("Tendon remodeling & glycogen restoration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Optional Active Recovery Override Button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("20m Zone 1 Flush")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Optional active recovery (<135 BPM)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let onScheduleFlushOverride {
                        onScheduleFlushOverride()
                    } else {
                        onPreviewMainRun?()
                    }
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
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Active Session Content (Primer + Main Run)

    private var activeSessionContent: some View {
        let primerDrill = PreRunDrill(
            id: session.primerDrillId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.primerTargetCadence,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let primerPhases = primerDrill.generatePhases()
        let totalPrimerDuration = max(1, primerPhases.reduce(0) { $0 + $1.durationSeconds })

        let mainRunDrill = PreRunDrill(
            id: session.mainSessionTemplateId,
            previousCadence: session.cadenceFloor,
            targetCadence: session.mainSessionTemplateId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6)",
            duration: DrillDuration(rawValue: session.mainRunDurationMinutes) ?? .thirtyMinutes,
            readinessState: session.isTrimmed ? .acuteFatigue : .productive,
            isIndoor: preferredWorkoutIsIndoor
        )
        let mainPhases = mainRunDrill.generatePhases()
        let totalMainDuration = max(1, mainPhases.reduce(0) { $0 + $1.durationSeconds })

        return VStack(spacing: 10) {
            // Stage 1: Pre-Run Primer Subcard
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.8, blue: 0.65).opacity(0.14))
                                .frame(width: 24, height: 24)
                            Image(systemName: "metronome.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))
                        }

                        Text("PRE-RUN PRIMER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(cleanPrimerDuration(session: session))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.8, blue: 0.65).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let onPreviewPrimer {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onPreviewPrimer()
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
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.primerDrillTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)

                    Text("Target \(cleanPrimerTarget(session: session))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                // Integrated 4-Target Grid (matching Main Run)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    metricCell(
                        icon: "stopwatch.fill",
                        title: "Duration",
                        value: cleanPrimerDuration(session: session),
                        color: .secondary
                    )
                    metricCell(
                        icon: "metronome.fill",
                        title: "Cadence",
                        value: cleanPrimerTarget(session: session),
                        color: Color(red: 0.0, green: 0.8, blue: 0.65)
                    )
                    metricCell(
                        icon: "repeat",
                        title: "Intervals",
                        value: primerDrill.shortWorkSummary,
                        color: Color(red: 1.0, green: 0.58, blue: 0.0)
                    )
                    metricCell(
                        icon: "figure.walk",
                        title: "Recovery",
                        value: primerDrill.shortRecoverySummary,
                        color: Color(red: 0.20, green: 0.72, blue: 0.92)
                    )
                }

                // Primer phase bar
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(primerPhases) { phase in
                                let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalPrimerDuration)
                                let w = max(4, (geo.size.width - CGFloat(primerPhases.count - 1) * 2) * ratio)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(phaseColor(phase.kind))
                                    .frame(width: w, height: 4)
                            }
                        }
                    }
                    .frame(height: 4)

                    Text(primerDrill.structureSummary)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 2)
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Stage 2: Main Run Subcard
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.14))
                                .frame(width: 24, height: 24)
                            Image(systemName: "figure.run")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                        }

                        Text("MAIN RUN")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(cleanMainRunDurationFormatted(session: session).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.55, blue: 1.0))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.55, blue: 1.0).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if let onPreviewMainRun {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onPreviewMainRun()
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
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)

                    Text(session.isTrimmed ? "Active Recovery Flush • Easy Aerobic Intensity" : "Aerobic Consistency • Conversational Pacing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Integrated 4-Target Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    metricCell(
                        icon: "stopwatch.fill",
                        title: "Duration",
                        value: cleanMainRunDurationFormatted(session: session),
                        color: .secondary
                    )
                    metricCell(
                        icon: preferredWorkoutIsIndoor ? "figure.run.square.stack" : "figure.run",
                        title: preferredWorkoutIsIndoor ? "Belt Pace" : "Pace",
                        value: session.paceBand,
                        color: Color(red: 0.0, green: 0.55, blue: 1.0)
                    )
                    metricCell(
                        icon: "heart.fill",
                        title: "Max HR",
                        value: session.hrCap.replacingOccurrences(of: "HR: ", with: ""),
                        color: Color(red: 1.0, green: 0.22, blue: 0.55)
                    )
                    metricCell(
                        icon: "metronome.fill",
                        title: "Cadence",
                        value: "≥ \(session.cadenceFloor) SPM",
                        color: Color(red: 0.0, green: 0.8, blue: 0.65)
                    )
                }

                if preferredWorkoutIsIndoor {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple)
                        Text(
                            session.mainSessionTemplateId == .hillBounds
                            ? "Treadmill: Set 4–6% incline on surges • Launches as Indoor Run on Watch"
                            : "Treadmill: Set 0.5–1.0% incline • Focus on HR & Cadence over wrist pace"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 1)
                }

                // Main Run phase bar
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(mainPhases) { phase in
                                let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalMainDuration)
                                let w = max(4, (geo.size.width - CGFloat(mainPhases.count - 1) * 2) * ratio)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(phaseColor(phase.kind))
                                    .frame(width: w, height: 4)
                            }
                        }
                    }
                    .frame(height: 4)

                    Text(mainRunDrill.structureSummary)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 2)
            }
            .padding(12)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Helpers

    private func metricCell(icon: String, title: String, value: String, color: Color) -> some View {
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
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func phaseColor(_ kind: WorkoutPhase.Kind) -> Color {
        kind.color
    }

    private func cleanPrimerDuration(session: PrescribedDailySession) -> String {
        session.primerPhasesDuration
            .replacingOccurrences(of: " drill", with: "")
            .replacingOccurrences(of: " (Adapted)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func cleanPrimerTarget(session: PrescribedDailySession) -> String {
        let target = session.primerTargetCadence
            .replacingOccurrences(of: " (Adapted)", with: "")
            .trimmingCharacters(in: .whitespaces)
        return target.contains("SPM") ? target : "\(target) SPM"
    }

    private func cleanMainRunDurationFormatted(session: PrescribedDailySession) -> String {
        let mins = session.mainRunDurationMinutes
        if mins >= 60 {
            let hours = mins / 60
            let remainder = mins % 60
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours) hr"
        } else {
            return "\(mins) MIN"
        }
    }
}
