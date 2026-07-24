import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let url: URL

    var body: some View {
        Group {
            if let document = PDFDocument(url: url) {
                PDFKitView(document: document)
            } else {
                ContentUnavailableView(
                    "Couldn't open this PDF",
                    systemImage: "doc.questionmark",
                    description: Text("This file didn't save correctly. Remove it from your Library and download it again.")
                )
            }
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}
