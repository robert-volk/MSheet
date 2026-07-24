import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedScore.savedAt, order: .reverse) private var scores: [SavedScore]

    var body: some View {
        NavigationStack {
            Group {
                if scores.isEmpty {
                    ContentUnavailableView(
                        "No scores yet",
                        systemImage: "books.vertical",
                        description: Text("Scores you download from Search show up here, saved for offline reading.")
                    )
                } else {
                    List {
                        ForEach(scores) { score in
                            NavigationLink {
                                PDFPreviewView(url: score.fileURL)
                            } label: {
                                LibraryRow(score: score)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Library")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let score = scores[index]
            try? FileManager.default.removeItem(at: score.fileURL)
            modelContext.delete(score)
        }
    }
}

private struct LibraryRow: View {
    let score: SavedScore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(score.title)
                .font(.system(.body, design: .serif))
                .fontWeight(.medium)
            if let composer = score.composer {
                Text(composer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: SavedScore.self, inMemory: true)
}
