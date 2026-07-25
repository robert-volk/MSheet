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
    /// Owned here so HomeButton, on screens pushed from this stack, can pop
    /// straight back to this root instead of just one level.
    @State private var path = NavigationPath()

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
        NavigationStack(path: $path) {
            resultsArea
                .background(Color("AppBackground"))
                .navigationTitle("Music Search")
                .navigationDestination(for: SearchResult.self) { result in
                    ScoreDetailView(result: result, path: $path)
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
            centeredMicPrompt
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

    /// The main voice-search CTA, centered in the screen before any query
    /// exists — bigger and more prominent than the small mic that stays in
    /// the search field once results are showing.
    private var centeredMicPrompt: some View {
        VStack(spacing: 18) {
            Spacer()

            Button {
                dictation.toggle()
            } label: {
                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                    .symbolEffect(.variableColor.iterative, isActive: dictation.isRecording)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .accessibilityLabel(dictation.isRecording ? "Stop listening" : "Search by voice")

            Text(dictation.isRecording ? "Listening…" : "Tap the mic, or type above, for a composer or title")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let message = dictation.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PianoKeyBackground())
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
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(Color("AppBackground"))
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

        // IMSLP results are intentionally excluded — see IMSLPService.swift,
        // still there in case this changes later. Only Mutopia, whose files
        // are always a frictionless direct download, is searched.
        do {
            results = try await MutopiaService.search(trimmed)
        } catch {
            errorMessage = "Couldn't reach Mutopia. Check your connection and try again."
        }
        isSearching = false
    }
}

/// A tiled piano-key texture — one real octave (7 white keys, black keys
/// skipping the E-F and B-C gaps) repeated across both width AND height
/// using a fixed tile size, so keys read as short repeating tiles rather
/// than one giant key stretched to the full screen height. Drawn
/// procedurally with Canvas rather than an image asset, so it scales to any
/// screen size without needing a pre-rendered tile.
private struct PianoKeyBackground: View {
    private let whiteKeyWidth: CGFloat = 20
    private let blackKeyWidth: CGFloat = 12
    private let tileHeight: CGFloat = 90
    private let blackKeyHeightRatio: CGFloat = 0.6
    private let blackKeyOffsets = [1, 2, 4, 5, 6] // after C, D, F, G, A — skipping E and B

    var body: some View {
        Canvas { context, size in
            let lineColor = Color.primary.opacity(0.22)
            let keyColor = Color.primary.opacity(0.22)
            let octaveWidth = whiteKeyWidth * 7
            let blackKeyHeight = tileHeight * blackKeyHeightRatio

            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    for i in 1..<7 {
                        let lineX = x + CGFloat(i) * whiteKeyWidth
                        var path = Path()
                        path.move(to: CGPoint(x: lineX, y: y))
                        path.addLine(to: CGPoint(x: lineX, y: y + tileHeight))
                        context.stroke(path, with: .color(lineColor), lineWidth: 1.5)
                    }
                    for offset in blackKeyOffsets {
                        let centerX = x + CGFloat(offset) * whiteKeyWidth
                        let rect = CGRect(x: centerX - blackKeyWidth / 2, y: y, width: blackKeyWidth, height: blackKeyHeight)
                        context.fill(Path(rect), with: .color(keyColor))
                    }
                    x += octaveWidth
                }
                y += tileHeight
            }
        }
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
