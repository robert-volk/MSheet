import SwiftUI
import UIKit

/// "All / Title / Composer" — not "Instrument" too, unlike the original
/// mockup: neither IMSLP nor Mutopia expose structured instrumentation, so
/// an Instrument filter would just silently match nothing. This only
/// narrows results already returned by the network search — it doesn't
/// change the query itself.
private enum SearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case title = "Title"
    case composer = "Composer"

    var id: String { rawValue }
}

struct SearchView: View {
    @StateObject private var dictation = DictationController()

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var scope: SearchScope = .all
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false
    @FocusState private var isFieldFocused: Bool

    private var filteredResults: [SearchResult] {
        switch scope {
        case .all:
            return results
        case .title:
            return results.filter { $0.title.localizedCaseInsensitiveContains(query) }
        case .composer:
            return results.filter { ($0.composer ?? "").localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            resultsArea
                .background(Color("AppBackground"))
                .navigationTitle("Search")
                .navigationDestination(for: SearchResult.self) { result in
                    ScoreDetailView(result: result)
                }
                .safeAreaInset(edge: .top) { searchField }
                .toolbar {
                    // Covers the empty-query and no-results states, which
                    // have nothing to scroll for the interactive dismiss.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isFieldFocused = false }
                    }
                }
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
            VStack(spacing: 0) {
                scopePicker
                if filteredResults.isEmpty {
                    ContentUnavailableView(
                        "No matches in \(scope.rawValue)",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Switch back to All to search across everything.")
                    )
                } else {
                    List(filteredResults) { result in
                        NavigationLink(value: result) {
                            SearchResultRow(result: result)
                        }
                        .listRowBackground(Color("AppCard"))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // Lets a downward drag on the results list dismiss the
                    // keyboard, like Messages/Mail — the toolbar "Done"
                    // button covers the empty/no-results states, which
                    // don't scroll.
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            ForEach(SearchScope.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Composer, title, or both", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFieldFocused)
                    .submitLabel(.search)
                    .onSubmit { isFieldFocused = false }
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
        .background(Color("AppBackground"))
    }

    private var micButton: some View {
        Button {
            dictation.toggle()
        } label: {
            Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(dictation.isRecording ? Color.red : Color.accentColor)
                .clipShape(Circle())
        }
        .accessibilityLabel(dictation.isRecording ? "Stop listening" : "Search by voice")
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

        // Each source fails independently — a Mutopia outage shouldn't hide
        // working IMSLP results, and vice versa. Only surface an error if
        // both come back empty-handed.
        async let imslp = try? IMSLPService.search(trimmed)
        async let mutopia = try? MutopiaService.search(trimmed)
        let (imslpResults, mutopiaResults) = await (imslp, mutopia)

        if imslpResults == nil && mutopiaResults == nil {
            errorMessage = "Couldn't reach IMSLP or Mutopia. Check your connection and try again."
        } else {
            // Mutopia's downloads are always frictionless (no copyright
            // gate), so surface those first.
            results = (mutopiaResults ?? []) + (imslpResults ?? [])
        }
        isSearching = false
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
                .font(.system(.body, design: .serif))
                .fontWeight(.medium)
            HStack(spacing: 6) {
                if let composer = result.composer {
                    Text(composer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(result.source.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SearchView()
}
