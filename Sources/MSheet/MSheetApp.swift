import SwiftUI
import SwiftData

@main
struct MSheetApp: App {
    // Local-only store: no CloudKit database configured, so nothing about
    // your library ever leaves the phone. Only Search and Download talk to
    // the network at all, and only to Mutopia.
    let container: ModelContainer = {
        let schema = Schema([SavedScore.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
