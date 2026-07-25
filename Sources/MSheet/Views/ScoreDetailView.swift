import SwiftUI
import Foundation

struct ScoreDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let result: SearchResult

    private enum DownloadState: Equatable {
        case idle
        case resolving
        case downloading
        case saved(fileName: String)
        case needsManualDownload
        case failed(String)
    }

    @State private var downloadState: DownloadState = .idle
    @State private var showSafari = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                    if let composer = result.composer {
                        Text(composer)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                statusArea

                actionButtons
            }
            .padding()
        }
        .background(Color("AppBackground"))
        // Dark by design, not just a fallback: musicians often read scores
        // from dim stages and pits, and the original mockup deliberately
        // put this screen in ink-dark rather than paper-light.
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSafari) {
            SafariView(url: result.pageURL)
        }
    }

    @ViewBuilder
    private var statusArea: some View {
        switch downloadState {
        case .idle:
            EmptyView()
        case .resolving:
            Label("Looking for a downloadable file…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .downloading:
            Label("Downloading…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved to your Library", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color("PDGreen"))
        case .needsManualDownload:
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't download this automatically", systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))
                Text("Either this edition needs a one-time per-country copyright notice accepted first, or \(result.source.rawValue) didn't hand back a plain PDF. Open it on \(result.source.rawValue) and download it there instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch downloadState {
        case .saved(let fileName):
            NavigationLink {
                PDFPreviewView(url: FileManager.scoresDirectory.appendingPathComponent(fileName))
            } label: {
                Label("Open Downloaded PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .needsManualDownload:
            Button {
                showSafari = true
            } label: {
                Label("Open on \(result.source.rawValue) to Download", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .resolving, .downloading:
            Button {} label: {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)

        case .idle, .failed:
            Button {
                Task { await download() }
            } label: {
                Label("Download PDF", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("DownloadBrown"))
        }
    }

    private func download() async {
        downloadState = .resolving
        do {
            let pdfURL: URL
            if let direct = result.directDownloadURL {
                // Mutopia already hands back the exact file link in search
                // results — no page-scraping step needed.
                pdfURL = direct
            } else if let resolved = try await IMSLPService.resolveDownloadURL(fromWorkPage: result.pageURL) {
                pdfURL = resolved
            } else {
                downloadState = .needsManualDownload
                return
            }

            downloadState = .downloading
            let (data, _) = try await URLSession.shared.data(from: pdfURL)

            // The resolved link isn't always the raw file — IMSLP in
            // particular can land on an interstitial/mirror-choice page
            // instead. Writing that to disk with a ".pdf" name would make
            // PDFKit silently show a blank page later, so bail out here
            // instead and send the person to the source's own page.
            guard looksLikePDF(data) else {
                downloadState = .needsManualDownload
                return
            }

            let fileName = sanitizedFileName()
            let destination = FileManager.scoresDirectory.appendingPathComponent(fileName)
            try data.write(to: destination, options: .atomic)

            let saved = SavedScore(
                title: result.title,
                composer: result.composer,
                sourceURL: result.pageURL,
                fileName: fileName
            )
            modelContext.insert(saved)
            downloadState = .saved(fileName: fileName)
        } catch {
            downloadState = .failed(error.localizedDescription)
        }
    }

    private func looksLikePDF(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D] // "%PDF-"
        guard data.count >= signature.count else { return false }
        return data.prefix(signature.count).elementsEqual(signature)
    }

    /// Keeps the saved filename filesystem-safe and traceable back to the
    /// work, since a source's own filenames (SIBLEY1802..., PMLP2397-...)
    /// don't read as anything to a person browsing their Library.
    private func sanitizedFileName() -> String {
        let byline = result.composer.map { " \($0)" } ?? ""
        let base = "\(result.title)\(byline)"
            .replacingOccurrences(of: #"[^a-zA-Z0-9 \-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "Score.pdf" : "\(base).pdf"
    }
}

#Preview {
    NavigationStack {
        ScoreDetailView(result: SearchResult(
            title: "Clair de Lune",
            composer: "Claude Debussy",
            pageURL: URL(string: "https://imslp.org/wiki/Clair_de_Lune_(Debussy,_Claude)")!,
            directDownloadURL: nil,
            source: .imslp
        ))
    }
    .modelContainer(for: SavedScore.self, inMemory: true)
}
