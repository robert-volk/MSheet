import SwiftUI
import PDFKit
import UIKit

struct PDFPreviewView: View {
    let url: URL
    @Binding var path: NavigationPath

    var body: some View {
        let document = PDFDocument(url: url)

        Group {
            if let document {
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
        .toolbar {
            if document != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        printPDF()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                HomeButton(path: $path)
                Spacer()
            }
            .padding(.bottom, 8)
        }
    }

    private func printPDF() {
        guard UIPrintInteractionController.canPrint(url) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.deletingPathExtension().lastPathComponent
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true, completionHandler: nil)
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
