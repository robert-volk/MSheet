import SwiftUI
import UIKit

struct SearchView: View {
    @StateObject private var dictation = DictationController()

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            resultsArea
                .navigationTitle("Search")
                .navigationDestination(for: SearchResult.self) { result in
                    ScoreDetailView(result: result)
                }
                .safeAreaInset(edge: .top) { searchField }
        }
        .task(id: query) {
            await runSearch()
        }
        .onAppear {
            dictation.onPartialResult = { partial in query = partial }
        }
        .onDisappear { dictation.stop() }
        .alert("Microphone & Speech Access Needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow microphone and speech recognition access in Settings to search by voice.")
        }
        .onChange(of: dictation.permissionState) { _, newValue in
            if newValue == .denied { showPermissionAlert = true }
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView(
                "Search for sheet music",
                systemImage: "music.note",
                description: Text("Type or tap the mic — try a composer, a title, or both.")
            )
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "Search failed",
                systemImage: "wifi.slash",
                description: Text(errorMessage)
            )
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List(results) { result in
                NavigationLink(value: result) {
                    SearchResultRow(result: result)
                }
            }
            .listStyle(.plain)
        }
    }

    private var searchField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Composer, title, or both", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                micButton
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if let message = dictation.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var micButton: some View {
        Button {
            dictation.toggle()
        } label: {
            Image(systemName: dictation.isRecording ? "waveform" : "mic.fill")
                .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
                .foregroundStyle(dictation.isRecording ? Color.red : Color.accentColor)
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }
        // Debounce: .task(id: query) cancels this automatically on every
        // keystroke, so only the search after 400ms of quiet actually runs.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        errorMessage = nil
        do {
            results = try await IMSLPService.search(trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.workTitle)
                .font(.system(.body, design: .serif))
                .fontWeight(.medium)
            if let composer = result.composer {
                Text(composer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SearchView()
}
