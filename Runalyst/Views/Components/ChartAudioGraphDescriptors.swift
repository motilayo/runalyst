import Accessibility
import Charts
import Foundation

// MARK: - Heart Rate Wave Audio Graph Descriptor

public struct HRWaveAudioGraphDescriptor: AXChartDescriptorRepresentable {
    public let points: [(minute: Double, bpm: Double)]
    public let title: String
    public let summary: String

    public init(points: [(minute: Double, bpm: Double)], title: String, summary: String) {
        self.points = points
        self.title = title
        self.summary = summary
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        let minX = points.map(\.minute).min() ?? 0.0
        let maxX = max(minX + 1.0, points.map(\.minute).max() ?? 1.0)
        let minY = points.map(\.bpm).min() ?? 40.0
        let maxY = max(minY + 10.0, points.map(\.bpm).max() ?? 200.0)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Elapsed Time (Minutes)",
            range: minX...maxX,
            gridlinePositions: []
        ) { value in
            "\(Int(round(value))) minutes"
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Heart Rate (BPM)",
            range: minY...maxY,
            gridlinePositions: []
        ) { value in
            "\(Int(round(value))) BPM"
        }

        let seriesPoints = points.map { pt in
            AXDataPoint(
                x: pt.minute,
                y: pt.bpm,
                additionalValues: [],
                label: "\(Int(round(pt.minute))) min: \(Int(round(pt.bpm))) BPM"
            )
        }

        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: seriesPoints
        )

        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Run Variance Audio Graph Descriptor

public struct RunVarianceAudioGraphDescriptor: AXChartDescriptorRepresentable {
    public let points: [(index: Double, cadence: Double, paceSeconds: Double)]
    public let title: String
    public let summary: String

    public init(
        points: [(index: Double, cadence: Double, paceSeconds: Double)],
        title: String,
        summary: String
    ) {
        self.points = points
        self.title = title
        self.summary = summary
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        let minX = points.map(\.index).min() ?? 0.0
        let maxX = max(minX + 1.0, points.map(\.index).max() ?? 1.0)
        let minY = points.map(\.cadence).min() ?? 120.0
        let maxY = max(minY + 10.0, points.map(\.cadence).max() ?? 200.0)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Elapsed Time (Minutes)",
            range: minX...maxX,
            gridlinePositions: []
        ) { value in
            "\(Int(round(value))) minutes"
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Cadence (SPM)",
            range: minY...maxY,
            gridlinePositions: []
        ) { value in
            "\(Int(round(value))) SPM"
        }

        let seriesPoints = points.map { pt in
            AXDataPoint(
                x: pt.index,
                y: pt.cadence,
                additionalValues: [],
                label: "\(Int(round(pt.index))) min: \(Int(round(pt.cadence))) SPM"
            )
        }

        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: seriesPoints
        )

        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Progression Audio Graph Descriptor

public struct ProgressionAudioGraphDescriptor: AXChartDescriptorRepresentable {
    public let points: [(index: Double, value: Double, label: String)]
    public let metricTitle: String
    public let unitLabel: String
    public let summary: String

    public init(
        points: [(index: Double, value: Double, label: String)],
        metricTitle: String,
        unitLabel: String,
        summary: String
    ) {
        self.points = points
        self.metricTitle = metricTitle
        self.unitLabel = unitLabel
        self.summary = summary
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        let minX = points.map(\.index).min() ?? 0.0
        let maxX = max(minX + 1.0, points.map(\.index).max() ?? 1.0)
        let minY = points.map(\.value).min() ?? 0.0
        let maxY = max(minY + 0.1, points.map(\.value).max() ?? 1.0)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Run Timeline",
            range: minX...maxX,
            gridlinePositions: []
        ) { value in
            let idx = Int(round(value))
            if idx >= 0 && idx < points.count {
                return points[idx].label
            }
            return "Run \(idx + 1)"
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "\(metricTitle) (\(unitLabel))",
            range: minY...maxY,
            gridlinePositions: []
        ) { value in
            String(format: "%.2f %@", value, unitLabel)
        }

        let seriesPoints = points.map { pt in
            AXDataPoint(
                x: pt.index,
                y: pt.value,
                additionalValues: [],
                label: "\(pt.label): \(String(format: "%.2f", pt.value)) \(unitLabel)"
            )
        }

        let series = AXDataSeriesDescriptor(
            name: metricTitle,
            isContinuous: true,
            dataPoints: seriesPoints
        )

        return AXChartDescriptor(
            title: metricTitle,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
