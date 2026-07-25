import SwiftUI
import SwiftData
import UIKit

@main
struct MSheetApp: App {
    // Local-only store: no CloudKit database configured, so nothing about
    // your library ever leaves the phone. Only Search and Download talk to
    // the network at all, and only to Mutopia and CPDL.
    let container: ModelContainer = {
        let schema = Schema([SavedScore.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    init() {
        // SwiftUI's AccentColor asset drives Color.accentColor and custom
        // controls (the mic buttons, etc.), but UIKit-hosted navigation bar
        // chrome — the back button, default-styled toolbar items — doesn't
        // reliably pick that up and was falling back to system blue. This
        // sets it explicitly, without touching Color.accentColor anywhere
        // else (so the red mic buttons and brown Download button, which set
        // their own colors directly, are unaffected).
        UINavigationBar.appearance().tintColor = UIColor(named: "NavigationGold")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
