# watch-environment-preference-sync Specification

## Purpose
TBD - created by archiving change watch-pace-drift-alerts. Update Purpose after archive.
## Requirements
### Requirement: Cross-Platform Environment Preference Sync
The iOS `WatchConnectivityManager` SHALL synchronize the user's persisted `preferredWorkoutIsIndoor` preference to watchOS via `WCSession` application context.

#### Scenario: iOS updates watch application context with indoor preference
- **WHEN** the iOS app pushes `WatchPacingContext` across `WCSession`
- **THEN** the payload SHALL contain `isIndoorPreferred: Bool` reflecting `@AppStorage("preferredWorkoutIsIndoor")`.

#### Scenario: Watch context store receives environment preference
- **WHEN** the watch receives an application context payload containing `isIndoorPreferred`
- **THEN** `WatchContextStore` SHALL update its stored `preferredLocation` to `.indoor` if `true`, or `.outdoor` if `false`.

### Requirement: StartRunView Environment Initialization
`StartRunView` on watchOS SHALL initialize its environment picker selection with the synchronized `preferredLocation` from `WatchContextStore`.

#### Scenario: Runner with indoor preference opens watch app
- **WHEN** `StartRunView` appears on watchOS
- **AND** `WatchContextStore.shared.preferredLocation` is `.indoor`
- **THEN** `selectedLocation` SHALL be initialized to `.indoor`.

#### Scenario: Runner with outdoor preference opens watch app
- **WHEN** `StartRunView` appears on watchOS
- **AND** `WatchContextStore.shared.preferredLocation` is `.outdoor`
- **THEN** `selectedLocation` SHALL be initialized to `.outdoor`.

