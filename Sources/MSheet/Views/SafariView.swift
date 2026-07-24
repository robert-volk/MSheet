import SwiftUI
import SafariServices

/// Opens IMSLP's real page in-app — used both for "View on IMSLP" and for
/// scores that need their per-country copyright notice accepted before
/// IMSLP will hand over the file directly.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
