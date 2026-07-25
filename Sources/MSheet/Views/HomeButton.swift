import SwiftUI

/// A fixed control for screens pushed deep into a tab's navigation stack —
/// pops straight back to that stack's root instead of requiring repeated
/// taps on the system back button. Each caller (Search's stack, Library's
/// stack) owns its own `NavigationPath`, so "home" always means that tab's
/// own root, not a cross-tab jump.
struct HomeButton: View {
    @Binding var path: NavigationPath

    var body: some View {
        Button {
            path = NavigationPath()
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                // Color("AccentColor") is an explicit named-asset lookup,
                // not Color.accentColor — it stays red even inside a
                // NavigationStack that sets an ambient gold .tint() for
                // its back button and toolbar chrome.
                .background(Color("AccentColor"))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .accessibilityLabel("Back to the main screen")
    }
}
