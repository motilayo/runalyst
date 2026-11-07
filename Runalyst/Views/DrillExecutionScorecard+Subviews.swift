import SwiftUI
import RunalystCore

extension DrillExecutionScorecard {
    // MARK: - Rep Row with Progressive Disclosure (Unified Layout)

    @ViewBuilder
    func drillRepRow(_ rep: DrillDisplayRep, targetRange: ClosedRange<Int>?) -> some View {
        let isRepExpanded = expandedRepIndices.contains(rep.repIndex)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    if isRepExpanded {
                        expandedRepIndices.remove(rep.repIndex)
                    } else {
                        expandedRepIndices.insert(rep.repIndex)
                    }
                }
            } label: {
                VStack(spacing: 6) {
                    // Line 1: Identity & Duration & Pace & Adherence Badge & Chevron
                    HStack(alignment: .center, spacing: 5) {
                        Text("Rep \(rep.repIndex)")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let dur = rep.durationSeconds, dur > 0 {
                            let durMin = Int(dur) / 60
                            let durSec = Int(dur) % 60
                            Text(durMin > 0 ? "\(durMin)m \(durSec)s" : "\(durSec)s")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Capsule())
                        }

                        if rep.isFastest {
                            HStack(spacing: 2) {
                                Image(systemName: "hare.fill")
                                    .font(.system(size: 7))
                                Text("Fastest")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Spacer(minLength: 4)

                        if let pace = rep.workPaceFormatted {
                            Text(pace)
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }

                        HStack(spacing: 2.5) {
                            Image(systemName: rep.isMet ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8, weight: .bold))
                            Text(rep.isMet ? "On Target" : "Developing")
                                .font(.system(size: 9.5, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundColor(rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : Color.orange).opacity(0.12))
                        .clipShape(Capsule())

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .rotationEffect(.degrees(isRepExpanded ? 90 : 0))
                    }

                    // Line 2: Biometrics & Recovery Summary
                    HStack(alignment: .center, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("\(rep.workCadence) SPM")
                                .font(.caption)
                                .foregroundColor(rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange)
                                .lineLimit(1)

                            if rep.workHeartRate > 0 {
                                Text("·")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary.opacity(0.4))

                                Text("\(rep.workHeartRate) BPM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            if let recPace = rep.recoveryPaceFormatted {
                                Text("Rec \(recPace)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if rep.recoveryCadence > 0 {
                                Text("Rec: \(rep.recoveryCadence) SPM")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if let drop = rep.recoveryHeartRateDrop {
                                recoveryHeartRateBadge(drop: drop)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Deep-Dive (Progressive Disclosure)
            if isRepExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.vertical, 4)

                    // Telemetry Breakdown Badges
                    HStack(spacing: 8) {
                        if let range = targetRange {
                            let delta = rep.workCadence - range.lowerBound
                            telemetryPill(
                                label: "Target Band",
                                value: "\(range.lowerBound)–\(range.upperBound) SPM (\(delta >= 0 ? "+\(delta)" : "\(delta)"))",
                                color: rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange
                            )
                        } else {
                            telemetryPill(
                                label: "Cadence",
                                value: "\(rep.workCadence) SPM",
                                color: rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange
                            )
                        }

                        if let delta = rep.paceDeltaVsAverageWorkSec {
                            telemetryPill(
                                label: "Pacing",
                                value: paceDeltaString(delta),
                                color: abs(delta) <= 5 ? .blue : .orange
                            )
                        }

                        if let drop = rep.recoveryHeartRateDrop {
                            let hrValue: String = drop > 0 ? "↓ \(drop) BPM" : (drop == 0 ? "0 BPM" : "↑ \(abs(drop)) BPM")
                            let hrColor: Color = drop >= 10 ? Color(red: 1.0, green: 0.22, blue: 0.55) : (drop < 0 ? .orange : .secondary)
                            telemetryPill(
                                label: "HR Drop",
                                value: hrValue,
                                color: hrColor
                            )
                        }
                    }

                    // Coach's Observation
                    let observationText: String = {
                        if let obs = rep.observation, !obs.isEmpty {
                            return obs
                        }
                        return rep.isMet
                            ? "Turnover met the target cadence requirement for this interval."
                            : "Turnover fell short of the prescribed cadence band."
                    }()

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(drillId.iconColor)
                            .padding(.top, 1)

                        Text(observationText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
                    .cornerRadius(6)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    @ViewBuilder
    func recoveryHeartRateBadge(drop: Int?) -> some View {
        if let drop = drop {
            if drop > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(drop) BPM")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color(red: 0.0, green: 0.75, blue: 0.65).opacity(0.12))
                .clipShape(Capsule())
            } else if drop == 0 {
                Text("0 BPM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(drop)) BPM")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    func telemetryPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(6)
    }

    func paceDeltaString(_ delta: Int) -> String {
        if delta == 0 {
            return "Even pace"
        } else if delta > 0 {
            return "+\(delta)s vs avg"
        } else {
            return "\(delta)s vs avg"
        }
    }
}
