import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: SavedScore.self, inMemory: true)
}
