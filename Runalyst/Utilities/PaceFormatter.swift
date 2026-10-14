import Foundation

/// Global utility for type-safe pace formatting
enum PaceFormatter {
    /// Formats decimal seconds per kilometer into a standard mm:ss string
    /// Automatically applies metric/imperial conversions based on user preferences.
    static func formatPace(secondsPerKilometer totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && totalSeconds > 0 else { return "--:--" }

        let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? (Locale.current.measurementSystem == .metric)

        var adjustedSeconds = totalSeconds
        var unitString = "/km"

        if !useMetricSystem {
            // Convert sec/km to sec/mi
            adjustedSeconds = totalSeconds * 1.609344
            unitString = "/mi"
        }

        let totalSecs = Int(adjustedSeconds.rounded())
        let minutes = totalSecs / 60
        let seconds = totalSecs % 60

        return String(format: "%d:%02d%@", minutes, seconds, unitString)
    }
}
