import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        // Same story as the NavigationStacks: the selected tab icon/label
        // was reading system blue instead of the AccentColor asset, so it
        // needs the same explicit .tint().
        .tint(Color("NavigationGold"))
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: SavedScore.self, inMemory: true)
}
