import SwiftData
import SwiftUI

/// Reusable pill control for linking, changing, or unlinking pre-run drills on a run record.
struct DrillLinkControlView: View {
    var runRecord: RunRecord
    var prescribedDrillName: String?
    var baselineCadence: Double?

    @Environment(\.modelContext) private var modelContext
    @State private var showingDrillExplainer = false

    var body: some View {
        Group {
            if let drillName = prescribedDrillName {
                Menu {
                    Menu {
                        ForEach(PreRunDrillId.techniqueDrills, id: \.self) { drill in
                            Button {
                                WorkoutBridge.linkDrill(to: runRecord, drillId: drill, baselineCadence: baselineCadence)
                                try? modelContext.save()
                            } label: {
                                if drill.title == drillName {
                                    Label(drill.title, systemImage: "checkmark")
                                } else {
                                    Label(drill.title, systemImage: drill.iconName)
                                }
                            }
                        }
                    } label: {
                        Label("Change Drill", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Divider()

                    Button {
                        showingDrillExplainer = true
                    } label: {
                        Label("About Drill Tracking...", systemImage: "info.circle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        WorkoutBridge.unlinkDrill(from: runRecord)
                        try? modelContext.save()
                    } label: {
                        Label("Unlink Drill", systemImage: "xmark.circle")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2.bold())
                        Text(drillName)
                            .font(.caption.bold())
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                            .opacity(0.8)
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
                }
            } else {
                Menu {
                    ForEach(PreRunDrillId.techniqueDrills, id: \.self) { drill in
                        Button {
                            WorkoutBridge.linkDrill(to: runRecord, drillId: drill, baselineCadence: baselineCadence)
                            try? modelContext.save()
                        } label: {
                            Label(drill.title, systemImage: drill.iconName)
                        }
                    }

                    Divider()

                    Button {
                        showingDrillExplainer = true
                    } label: {
                        Label("About Drill Tracking...", systemImage: "info.circle")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.caption2.bold())
                        Text("Add Drill")
                            .font(.caption.bold())
                        Image(systemName: "chevron.down")
                            .font(.caption2.bold())
                            .opacity(0.7)
                    }
                    .foregroundColor(Color(red: 0.05, green: 0.45, blue: 0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.05, green: 0.45, blue: 0.5).opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 0.05, green: 0.45, blue: 0.5).opacity(0.25), lineWidth: 1)
                    )
                }
            }
        }
        .alert("Drill Tracking", isPresented: $showingDrillExplainer) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Link this workout to a drill (like Cadence Pyramids, Strides, or Zone 2 Run) to track your form adherence against coaching targets in Drill Performance.")
        }
    }
}
