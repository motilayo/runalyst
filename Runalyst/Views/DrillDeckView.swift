import SwiftData
import SwiftUI
import WorkoutKit

struct DrillRow: View {
    var icon: String
    var text: String
    var body: some View {
        if !text.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .top)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct DrillDeckView: View {
    var drills: [DrillRecommendation]
    @State private var activeCardIndex: Int = 0
    @State private var offset: CGSize = .zero

    private func updateDragOffset(_ translation: CGSize, isActive: Bool) {
        guard isActive else { return }
        offset = translation
    }

    private func finishDrag(isActive: Bool, totalDrills: Int) {
        guard isActive else { return }
        if offset.width < -100 && activeCardIndex < totalDrills - 1 {
            activeCardIndex += 1
        } else if offset.width > 100 && activeCardIndex > 0 {
            activeCardIndex -= 1
        }
        offset = CGSize.zero
    }

    private func deckCard(_ drill: DrillRecommendation, index: Int, totalDrills: Int) -> some View {
        let relativeIndex = index - activeCardIndex
        return DrillCardView(
            drill: drill,
            drillIndex: index,
            totalDrills: totalDrills,
            activeCardIndex: $activeCardIndex
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(relativeIndex == 0 ? 0 : 0.3)))
        .shadow(color: Color.black.opacity(relativeIndex == 0 ? 0.15 : 0.05), radius: relativeIndex == 0 ? 12 : 8, x: 0, y: relativeIndex == 0 ? 8 : 4)
        .rotationEffect(.degrees(relativeIndex == 0 ? (Double(offset.width) / 20.0) : 0))
        .offset(x: relativeIndex == 0 ? offset.width : 0, y: relativeIndex == 0 ? offset.height : 0)
        .opacity(relativeIndex == 0 ? (2 - Double(abs(offset.width / 150))) : 1.0)
        .zIndex(Double(totalDrills - index))
        .padding(.horizontal)
        .padding(.bottom, 20)
        .gesture(
            DragGesture(minimumDistance: 15).onChanged { dragGesture in updateDragOffset(dragGesture.translation, isActive: relativeIndex == 0) }
            .onEnded { _ in finishDrag(isActive: relativeIndex == 0, totalDrills: totalDrills) }
        )
    }

    var body: some View {
        let sortedDrills = drills.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
        if sortedDrills.count == 1, let firstDrill = sortedDrills.first {
            DrillCardView(
                drill: firstDrill,
                drillIndex: 0,
                totalDrills: 1,
                activeCardIndex: $activeCardIndex
            )
            .padding(.horizontal)
            .padding(.bottom, 20)
        } else {
            ZStack(alignment: .top) {
                ForEach(Array(sortedDrills.enumerated()), id: \.element.id) { index, currentDrill in
                    let relativeIndex = index - activeCardIndex
                    if relativeIndex >= 0 && relativeIndex < 3 {
                        deckCard(currentDrill, index: index, totalDrills: sortedDrills.count)
                    }
                }
            }
            .padding(.bottom, 40)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offset)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeCardIndex)
        }
    }
}

struct DrillCardView: View {
    @Bindable var drill: DrillRecommendation
    let drillIndex: Int
    let totalDrills: Int
    @Binding var activeCardIndex: Int
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]
    @State private var activeReadoutItem: ActiveDrillReadoutItem?
    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""

    private var resolvedPreRunId: PreRunDrillId {
        if let raw = drill.preRunDrillId, let id = PreRunDrillId(rawValue: raw) {
            return id
        }
        let title = drill.drillTitle
        if let match = PreRunDrillId.allCases.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame ||
            $0.rawValue.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            return match
        }
        let normalized = title.replacingOccurrences(of: "_", with: " ")
        if let match = PreRunDrillId.allCases.first(where: {
            $0.title.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return match
        }
        return .strides
    }

    private var targetCadenceString: String {
        let template = DrillTemplate.template(for: resolvedPreRunId)
        return drill.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? template.calculateTargetCadence(drill.previousCadence ?? 155)
    }

    private var readinessAssessment: ReadinessAssessment {
        ReadinessEvaluator.assess(runRecords: runRecords)
    }

    private var effectivePreRunDrill: PreRunDrill {
        let readiness = readinessAssessment
        let adapted = ReadinessModifier.adaptTarget(
            targetCadenceString,
            baselineCadence: drill.previousCadence,
            drillId: resolvedPreRunId,
            state: readiness.state
        )
        return PreRunDrill(
            id: resolvedPreRunId,
            previousCadence: drill.previousCadence,
            targetCadence: adapted.targetCadence,
            readinessState: readiness.state
        )
    }

    var body: some View {
        let readiness = readinessAssessment
        let preRunId = resolvedPreRunId
        let template = DrillTemplate.template(for: preRunId)
        let displayTitle = drill.formattedTitle.isEmpty ? template.title : drill.formattedTitle
        let currentDrill = effectivePreRunDrill
        let isAdapted = readiness.state.applies(to: preRunId)
        let work = isAdapted ? currentDrill.defaultWorkString : ((drill.drillWork?.isEmpty == false ? drill.drillWork : nil) ?? template.defaultWork)
        let recovery = (isAdapted && readiness.state == .deload) ? currentDrill.defaultRecoveryString : ((drill.drillRecovery?.isEmpty == false ? drill.drillRecovery : nil) ?? template.defaultRecovery)
        let effort = (drill.drillEffort?.isEmpty == false ? drill.drillEffort : nil) ?? template.defaultEffort
        let purpose = (drill.drillPurpose?.isEmpty == false ? drill.drillPurpose : nil) ?? template.defaultPurpose
        let cue: String? = {
            if let cueText = drill.drillCues, !cueText.isEmpty, !cueText.localizedCaseInsensitiveContains("spm") {
                return cueText
            }
            let targetInt = currentDrill.computedCadence ?? drill.targetCadence?.replacingOccurrences(of: " SPM", with: "") ?? template.calculateTargetCadence(drill.previousCadence ?? 155)
            let generated = template.generateInstructionalCue(targetInt)
            return generated.isEmpty ? nil : generated
        }()

        VStack(alignment: .leading, spacing: 12) {
            if totalDrills > 1 {
                HStack {
                    HStack(spacing: 4) {
                        ForEach(0..<totalDrills, id: \.self) { barIndex in
                            Capsule()
                                .fill(barIndex == activeCardIndex ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: 16, height: 4)
                        }
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if activeCardIndex > 0 { activeCardIndex -= 1 }
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(activeCardIndex > 0 ? .primary : .secondary.opacity(0.3))
                        }
                        .disabled(activeCardIndex == 0)

                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if activeCardIndex < totalDrills - 1 { activeCardIndex += 1 }
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(activeCardIndex < totalDrills - 1 ? .primary : .secondary.opacity(0.3))
                        }
                        .disabled(activeCardIndex == totalDrills - 1)
                    }
                }
                .padding(.bottom, 2)
            }

            let drillIcon = PreRunDrill.iconName(for: drill.preRunDrillId, title: displayTitle)
            let drillColor = PreRunDrill.iconColor(for: drill.preRunDrillId, title: displayTitle)

            // Header Row: Icon badge + Category + Duration Capsule + Preview Button
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(drillColor.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: drillIcon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(drillColor)
                    }

                    Text(preRunId.isHeartRateTargeted ? "AEROBIC RUN" : "TECHNIQUE DRILL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(drillColor)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(currentDrill.duration.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(drillColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(drillColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    openDrillReadout(displayTitle: displayTitle, coachingCue: cue)
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

                if !purpose.isEmpty {
                    Text(purpose)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            let displayTargetClean: String = {
                if preRunId == .aerobicFlush || preRunId == .recoveryJog {
                    return "Zone 1 HR"
                }
                if preRunId == .zone2Run {
                    return "Zone 2 HR"
                }
                let targetCadenceValue = currentDrill.computedCadence ?? drill.targetCadence ?? ""
                if !targetCadenceValue.isEmpty {
                    return targetCadenceValue.contains("SPM") ? targetCadenceValue : "\(targetCadenceValue) SPM"
                }
                return "Dynamic"
            }()

            // 2x2 Metric Grid (matching Main Run Standard)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                deckMetricCell(
                    icon: "stopwatch.fill",
                    title: "Duration",
                    value: currentDrill.duration.title,
                    color: .secondary
                )
                deckMetricCell(
                    icon: preRunId.isHeartRateTargeted ? "heart.fill" : "metronome.fill",
                    title: preRunId.isHeartRateTargeted ? "Target HR" : "Cadence",
                    value: displayTargetClean,
                    color: preRunId.isHeartRateTargeted ? Color(red: 1.0, green: 0.18, blue: 0.55) : Color(red: 0.0, green: 0.8, blue: 0.65)
                )
                deckMetricCell(
                    icon: "repeat",
                    title: "Intervals",
                    value: currentDrill.shortWorkSummary,
                    color: Color(red: 1.0, green: 0.58, blue: 0.0)
                )
                deckMetricCell(
                    icon: "figure.walk",
                    title: "Recovery",
                    value: currentDrill.shortRecoverySummary,
                    color: Color(red: 0.20, green: 0.72, blue: 0.92)
                )
            }

            // Sleek 4pt Phase Mini-Bar
            let phases = currentDrill.generatePhases()
            let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })

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

                Text(currentDrill.structureSummary)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)

            // Mark Completed Button
            Button(action: {
                drill.isCompleted.toggle()
                try? drill.modelContext?.save()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: drill.isCompleted ? "checkmark.circle.fill" : "circle")
                    Text(drill.isCompleted ? "Completed ✓" : "Mark completed")
                }
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(drill.isCompleted ? Color.green.opacity(0.15) : Color(UIColor.secondarySystemFill))
                .foregroundColor(drill.isCompleted ? .green : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 1)
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .sheet(item: $activeReadoutItem) { item in
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
        }
    }

    private func openDrillReadout(displayTitle: String, coachingCue: String?) {
        let currentPreRunId = resolvedPreRunId
        let currentTargetCadence = targetCadenceString
        let currentDrill = effectivePreRunDrill
        let dto = DrillPrescriptionDTO(
            title: displayTitle,
            preRunDrillId: currentPreRunId.rawValue,
            purpose: drill.drillPurpose ?? "",
            targetCadence: currentTargetCadence,
            previousCadence: drill.previousCadence,
            durationMinutes: currentDrill.duration.rawValue
        )
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeReadoutItem = ActiveDrillReadoutItem.adaptive(
            dto: dto,
            readiness: readiness,
            customCoachingTip: coachingCue
        )
    }

    private func deckMetricCell(icon: String, title: String, value: String, color: Color) -> some View {
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
