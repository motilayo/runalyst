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

    @State private var showingRationaleExplainer = false

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
            headerBar

            if session.isRestDay {
                restDayContent
            } else {
                activeSessionHeader
                activeSessionContent
            }
        }
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: .purple)
        .sheet(isPresented: $showingRationaleExplainer) {
            let parsed = parseRationale(session.groundedRationale)
            GlassBoxExplainerSheet(
                title: session.sessionTitle,
                categoryBadge: session.isRestDay ? "Rest & Recovery" : session.targetGoal,
                whatSummary: parsed.headline ?? (session.isRestDay ? "Rest & Connective Tissue Remodeling" : "Prescribed Aerobic Training"),
                whyItMatters: parsed.body,
                howItWorks: session.isRestDay
                    ? "Rest days allow deep tendon remodeling, rebuild depleted muscle glycogen stores, and restore neuromuscular readiness without joint impact."
                    : "Runalyst balances your 48-hour volume, acute-to-chronic workload ratio (ACWR), and rolling 30-day baseline to lock in your safe training envelope.",
                formula: session.isRestDay ? "Target HR: < 135 BPM (Optional Flush)" : "Cadence Floor: ≥ \(session.cadenceFloor) SPM • HR Cap: \(session.hrCap)",
                targetRange: session.isRestDay ? "Recovery: Full Rest or 20 min Zone 1" : "Duration: \(session.mainRunDurationMinutes) min • Pace: \(session.paceBand)"
            )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
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
    }

    // MARK: - Active Session Header

    private var activeSessionHeader: some View {
        let parsed = parseRationale(session.groundedRationale)
        return VStack(alignment: .leading, spacing: 6) {
            if !effectiveIsToday {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10, weight: .bold))
                    Text("UPCOMING • \(headerDayText.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.12))
                .clipShape(Capsule())
            }

            HStack(alignment: .center) {
                Text(session.sessionTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingRationaleExplainer = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Learn more about today's prescribed workout")
            }

            if let headline = parsed.headline {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)
            }
        }
    }

    // MARK: - Rest Day Content (Streamlined & Glanceable with Zero Card-in-Card Nesting)

    private var restDayContent: some View {
        let parsedRationale = parseRationale(session.groundedRationale)

        return VStack(alignment: .leading, spacing: 12) {
            // Title & Adaptation Focus with Info Icon
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.sessionTitle)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 5) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))

                        Text("Tendon Remodeling & Glycogen Restoration")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.72, blue: 0.62))
                    }
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingRationaleExplainer = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Learn more about rest day physiology")
            }

            // Glanceable Micro-Stat Grid (Transforms Text-Heavy Rationale into Quick Metrics)
            if let metrics = parsedRationale.statMetrics, !metrics.isEmpty {
                HStack(spacing: 8) {
                    ForEach(metrics, id: \.title) { metric in
                        MiniStatTile(
                            title: metric.title,
                            value: metric.value,
                            unit: nil,
                            icon: nil,
                            accentColor: metric.title.contains("Recovery") ? Color(red: 0.0, green: 0.75, blue: 0.65) : nil
                        )
                    }
                }
                .padding(.top, 2)
            } else if let headline = parsedRationale.headline {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)
            }

            // Clean Divider (Eliminates Nested Card-in-Card Container)
            Divider()
                .opacity(0.4)
                .padding(.vertical, 2)

            // Optional Active Recovery Jog Card (Unified with Drills & Runs Library)
            DrillPrimerCardView(
                drillId: .recoveryJog,
                config: DrillCardConfig(
                    customTitle: "Recovery Jog",
                    customPurpose: "Promote blood flow & tissue recovery",
                    customTarget: "Zone 1 HR",
                    categoryLabel: "OPTIONAL",
                    canChangeDuration: false,
                    lockedDuration: .fifteenMinutes,
                    customMetrics: [
                        DrillCardMetric(icon: "stopwatch.fill", title: "Duration", value: "15 min", color: .secondary),
                        DrillCardMetric(icon: "heart.fill", title: "Target HR", value: "< 135 BPM", color: Color(red: 0.0, green: 0.75, blue: 0.65)),
                        DrillCardMetric(icon: "figure.walk", title: "Effort", value: "Active Recovery", color: Color(red: 0.20, green: 0.72, blue: 0.92)),
                        DrillCardMetric(icon: "metronome.fill", title: "Cadence", value: "Relaxed", color: .secondary)
                    ]
                ),
                baselineCadence: session.cadenceFloor,
                onPreview: {
                    if let onScheduleFlushOverride {
                        onScheduleFlushOverride()
                    } else {
                        onPreviewMainRun?()
                    }
                }
            )
        }
    }

    // MARK: - Active Session Content (Primer + Main Run)

    private var activeSessionContent: some View {
        VStack(spacing: 12) {
            // Stage 1: Pre-Run Primer Card
            DrillPrimerCardView(
                drillId: session.primerDrillId,
                config: DrillCardConfig(
                    customTitle: session.primerDrillTitle,
                    customPurpose: "Target \(cleanPrimerTarget(session: session))",
                    customTarget: cleanPrimerTarget(session: session),
                    categoryLabel: effectiveIsToday ? "PRE-RUN PRIMER" : "\(headerDayText.uppercased()) PRIMER",
                    canChangeDuration: false,
                    lockedDuration: session.primerDrillId.defaultDuration
                ),
                baselineCadence: session.cadenceFloor,
                onPreview: onPreviewPrimer
            )

            // Stage 2: Main Run Card
            let mainDuration = DrillDuration.nearest(toMinutes: session.mainRunDurationMinutes)
            let paceTitle = preferredWorkoutIsIndoor ? "Belt Pace" : "Pace"
            let paceIcon = preferredWorkoutIsIndoor ? "figure.run.square.stack" : "figure.run"
            let maxHrValue = session.hrCap.replacingOccurrences(of: "HR: ", with: "")

            DrillPrimerCardView(
                drillId: session.mainSessionTemplateId,
                config: DrillCardConfig(
                    customTitle: session.sessionTitle,
                    customPurpose: session.isTrimmed ? "Low-strain movement & tissue repair" : "Aerobic consistency & conversational pacing",
                    customTarget: session.mainSessionTemplateId.isHeartRateTargeted ? nil : "\(session.cadenceFloor)-\(session.cadenceFloor + 6) SPM",
                    categoryLabel: effectiveIsToday ? "MAIN RUN" : "\(headerDayText.uppercased()) MAIN RUN",
                    canChangeDuration: false,
                    lockedDuration: mainDuration,
                    customMetrics: [
                        DrillCardMetric(icon: "stopwatch.fill", title: "Duration", value: cleanMainRunDurationFormatted(session: session), color: .secondary),
                        DrillCardMetric(icon: paceIcon, title: paceTitle, value: session.paceBand, color: Color(red: 0.0, green: 0.55, blue: 1.0)),
                        DrillCardMetric(icon: "heart.fill", title: "Max HR", value: maxHrValue, color: Color(red: 1.0, green: 0.22, blue: 0.55)),
                        DrillCardMetric(icon: "metronome.fill", title: "Cadence", value: "≥ \(session.cadenceFloor) SPM", color: Color(red: 0.0, green: 0.8, blue: 0.65))
                    ]
                ),
                baselineCadence: session.cadenceFloor,
                onPreview: onPreviewMainRun
            )
        }
    }

    // MARK: - Helpers

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

    struct ParsedRationale {
        let headline: String?
        let body: String
        let statMetrics: [(title: String, value: String)]?
    }

    private func parseRationale(_ text: String) -> ParsedRationale {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check for 48-Hour Volume Compression
        if trimmed.contains("48-Hour Volume Compression") {
            var metrics: [(title: String, value: String)] = []

            let minRegex = try? NSRegularExpression(
                pattern: #"(\d+)\s*min in the last 48 hours"#,
                options: .caseInsensitive
            )
            if let match = minRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                metrics.append((title: "48h Volume", value: "\(trimmed[range]) min"))
            }

            let pctRegex = try? NSRegularExpression(
                pattern: #"\((\d+)%\s*of"#,
                options: .caseInsensitive
            )
            if let match = pctRegex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                metrics.append((title: "Weekly Share", value: "\(trimmed[range])%"))
            }

            metrics.append((title: "Recovery", value: "Rest Day"))

            let bodyText: String
            if let dotIndex = trimmed.range(of: "). ") {
                bodyText = String(trimmed[dotIndex.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let colonIndex = trimmed.firstIndex(of: ":") {
                bodyText = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                bodyText = trimmed
            }

            let finalBody = bodyText.isEmpty
                ? "A rest day allows deep recovery, glycogen replenishment, and joint remodeling to prevent cumulative overload."
                : bodyText

            return ParsedRationale(
                headline: "48-Hour Volume Compression",
                body: finalBody,
                statMetrics: metrics.isEmpty ? nil : metrics
            )
        }

        // 2. Generic "Headline: Body" form
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let prefix = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count < 35 {
                let bodyText = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return ParsedRationale(headline: prefix, body: bodyText, statMetrics: nil)
            }
        }

        return ParsedRationale(headline: nil, body: trimmed, statMetrics: nil)
    }
}
