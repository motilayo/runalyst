import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.runalyzer.Runalyzer", category: "SwiftData")

@main
struct RunalystApp: App {

    init() {
        _ = WatchCalibrationBridge.shared
    }

    let container: ModelContainer = {
        logger.info("Starting ModelContainer initialization with RunalystMigrationPlan")
        let schema = Schema(versionedSchema: RunalystSchemaV1.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: RunalystMigrationPlan.self,
                configurations: [modelConfiguration]
            )
            logger.info("Created container successfully with migration plan")
            return modelContainer
        } catch {
            logger.error("Failed to load persistent ModelContainer with migration plan: \(error.localizedDescription)")
            logger.warning("Attempting recovery by recreating store...")
            let storeURL = modelConfiguration.url
            let storePath = storeURL.path
            let shmPath = storePath + "-shm"
            let walPath = storePath + "-wal"

            try? FileManager.default.removeItem(atPath: storePath)
            try? FileManager.default.removeItem(atPath: shmPath)
            try? FileManager.default.removeItem(atPath: walPath)

            if let fallbackContainer = try? ModelContainer(
                for: schema,
                migrationPlan: RunalystMigrationPlan.self,
                configurations: [modelConfiguration]
            ) {
                logger.info("Re-created container successfully after recovery")
                return fallbackContainer
            }

            logger.error("Falling back to in-memory ModelContainer to prevent user data crash")
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let inMemoryContainer = try? ModelContainer(for: schema, configurations: [inMemoryConfig]) {
                return inMemoryContainer
            }

            fatalError("Unrecoverable SwiftData initialization failure: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
