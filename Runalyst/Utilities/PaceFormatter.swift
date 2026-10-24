import Foundation

/// Global utility for type-safe pace formatting
enum PaceFormatter {
    /// Formats decimal seconds per kilometer into a mm:ss string without the unit suffix (e.g. "5:15")
    /// Automatically applies metric/imperial conversions based on user preferences.
    static func formatPaceValue(secondsPerKilometer totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && totalSeconds > 0 else { return "--:--" }

        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)

        var adjustedSeconds = totalSeconds
        if !useMetricSystem {
            // Convert sec/km to sec/mi
            adjustedSeconds = totalSeconds * 1.609344
        }

        let totalSecs = Int(adjustedSeconds.rounded())
        let minutes = totalSecs / 60
        let seconds = totalSecs % 60

        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formats decimal seconds per kilometer into a standard mm:ss string with unit suffix (e.g. "5:15/km" or "8:03/mi")
    /// Automatically applies metric/imperial conversions based on user preferences.
    static func formatPace(secondsPerKilometer totalSeconds: Double) -> String {
        let value = formatPaceValue(secondsPerKilometer: totalSeconds)
        guard value != "--:--" else { return "--:--" }
        return "\(value)\(paceUnit())"
    }

    /// Returns the localized pace unit ("/km" or "/mi") based on user preferences
    static func paceUnit() -> String {
        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)
        return useMetricSystem ? "/km" : "/mi"
    }
}
