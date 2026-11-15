import RunalystCore
import SwiftUI

// MARK: - Start Run View

/// Hollow configuration view for starting a watch workout session.
/// Binds exclusively to `WatchRunIntent` and `WatchResolvedSessionConfig`. Zero inline domain math.
public struct StartRunView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    @State private var selectedLocation: PacingLocation = WatchContextStore.shared.preferredLocation
    @State private var hasUserManuallySelectedLocation = false
    @State private var selectedIntentOverride: WatchRunIntent?

    public init() {}

    private var baseConfig: WatchResolvedSessionConfig {
        WatchContextStore.shared.resolveSession(
            runIntent: nil
        )
    }

    private var resolvedConfig: WatchResolvedSessionConfig {
        WatchContextStore.shared.resolveSession(
            runIntent: selectedIntentOverride,
            isExplicitOverride: selectedIntentOverride != nil
        )
    }

    private var heroAccentColor: Color {
        resolvedConfig.hasPrescribedDrill ? WatchColor.cadence : WatchColor.companionAccent
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if let startError = workoutManager.lastStartError {
                            Text(startError)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        heroCard
                            .id("heroCard")
                            .containerRelativeFrame(.vertical, alignment: .center)

                        runIntentSelector(scrollProxy: proxy)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .onChange(of: WatchContextStore.shared.cachedContext) { _, _ in
                    selectedIntentOverride = nil
                    hasUserManuallySelectedLocation = false
                    selectedLocation = WatchContextStore.shared.preferredLocation
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        proxy.scrollTo("heroCard", anchor: .top)
                    }
                }
            }
        }
        .onAppear {
            if workoutManager.sessionState == .running || workoutManager.sessionState == .paused {
                workoutManager.isNavigatingToGauge = true
            }
            if !hasUserManuallySelectedLocation { selectedLocation = WatchContextStore.shared.preferredLocation }
            if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == "START_CUSTOM_OVERRIDE",
               selectedIntentOverride == nil {
                selectedIntentOverride = .pushPerformance
            }
            if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == nil {
                WatchContextStore.shared.requestLatestContextIfNeeded()
            }
        }
        .onChange(of: WatchContextStore.shared.preferredLocation) { _, newLoc in
            if !hasUserManuallySelectedLocation { selectedLocation = newLoc }
        }
        .task {
            if ProcessInfo.processInfo.environment["RUNALYST_PREVIEW_SCREEN"] == nil {
                _ = await workoutManager.requestAuthorizationIfNeeded()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { workoutManager.isNavigatingToGauge },
            set: { workoutManager.isNavigatingToGauge = $0 }
        )) {
            PacingGaugeView()
        }
    }

    // MARK: - Subviews

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(heroAccentColor.opacity(0.15)).frame(width: 20, height: 20)
                    Image(systemName: resolvedConfig.hasPrescribedDrill ? WatchIcon.drill : WatchIcon.companion)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(heroAccentColor)
                }

                Text(resolvedConfig.sessionHeaderBadgeText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(heroAccentColor)

                Spacer()

                if let duration = resolvedConfig.durationFormatted {
                    Text(duration.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedConfig.sessionTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(resolvedConfig.sessionSubtitle)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 4)

                startWorkoutPlayButton
            }

            Spacer(minLength: 2)

            HStack(spacing: 0) {
                heroStatColumn(
                    icon: WatchIcon.pace,
                    label: "PACE",
                    value: resolvedConfig.targetPaceFormatted(useMetric: useMetricSystem),
                    iconColor: WatchColor.pace
                )
                Divider().frame(height: 20).opacity(0.25)
                heroStatColumn(
                    icon: WatchIcon.cadence,
                    label: "CADENCE",
                    value: resolvedConfig.targetCadencePillText,
                    iconColor: WatchColor.cadence
                )
                Divider().frame(height: 20).opacity(0.25)
                heroStatColumn(
                    icon: WatchIcon.heartRate,
                    label: "MAX HR",
                    value: resolvedConfig.aerobicCeilingPillText,
                    iconColor: WatchColor.heartRate
                )
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.5))

            Spacer(minLength: 2)

            locationSelector
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .watchLiquidGlass(accent: heroAccentColor, cornerRadius: 14, isProminent: true)
    }

    private var startWorkoutPlayButton: some View {
        Button {
            Task {
                await workoutManager.startWorkout(
                    location: selectedLocation,
                    intent: selectedIntentOverride,
                    targetPaceSecondsPerKm: resolvedConfig.intent.targetPaceSecondsPerKm,
                    viewModel: pacingViewModel
                )
                workoutManager.isNavigatingToGauge = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(WatchColor.cadence)
                    .frame(width: 38, height: 38)
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: 1)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(resolvedConfig.primaryCtaTitle)
    }

    private func heroStatColumn(icon: String, label: String, value: String, iconColor: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 7.5, weight: .bold)).foregroundStyle(iconColor)
                Text(label).font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var locationSelector: some View {
        HStack(spacing: 6) {
            locationButton(title: "Outdoor", icon: WatchIcon.outdoor, location: .outdoor)
            locationButton(title: "Indoor", icon: WatchIcon.indoor, location: .indoor)
        }
    }

    private func locationButton(title: String, icon: String, location: PacingLocation) -> some View {
        let isSelected = selectedLocation == location
        return Button {
            selectedLocation = location
            hasUserManuallySelectedLocation = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(isSelected ? WatchColor.pace : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .neutralWatchSurface(isSelected: isSelected, cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }

    private func runIntentSelector(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RUN INTENT")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 5) {
                if baseConfig.isPhoneSessionSynced && baseConfig.defaultRunIntentSelection == nil {
                    intentOptionRow(
                        title: baseConfig.sessionTitle,
                        subtitle: "Scheduled for today",
                        isSelected: selectedIntentOverride == nil
                    ) {
                        selectedIntentOverride = nil
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            scrollProxy.scrollTo("heroCard", anchor: .top)
                        }
                    }
                }

                ForEach(WatchRunIntent.allCases) { intent in
                    let isSelected = (selectedIntentOverride ?? baseConfig.defaultRunIntentSelection) == intent
                    intentOptionRow(
                        title: intent.title,
                        subtitle: intent.subtitle,
                        isSelected: isSelected
                    ) {
                        selectedIntentOverride = (baseConfig.isPhoneSessionSynced && !baseConfig.hasPrescribedDrill && baseConfig.defaultRunIntentSelection == intent) ? nil : intent
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            scrollProxy.scrollTo("heroCard", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func intentOptionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.subheadline, design: .rounded)).fontWeight(.semibold).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchColor.cadence).font(.body)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .neutralWatchSurface(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Extension

private extension View {
    func neutralWatchSurface(isSelected: Bool, cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.white.opacity(isSelected ? 0.14 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.35 : 0.08), lineWidth: 0.75)
            )
    }
}
