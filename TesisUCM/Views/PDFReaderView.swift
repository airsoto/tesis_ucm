import SwiftUI
import PDFKit
import UIKit

struct PDFReaderView: View {
    let thesis: Thesis

    @EnvironmentObject private var library: LibraryStore
    @State private var document: PDFDocument?
    @State private var currentPage = 1
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if let document {
                PDFDocumentView(
                    document: document,
                    initialPage: currentPage,
                    onPageChanged: { page, pageCount in
                        currentPage = page
                        library.updateProgress(for: thesis.id, page: page, pageCount: pageCount)
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            } else if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(AppTheme.burgundy)
                    Text("Preparando el documento…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.cream)
            } else {
                ContentUnavailableView(
                    "No se puede abrir el PDF",
                    systemImage: "doc.questionmark",
                    description: Text(loadError ?? "Comprueba la conexión o el enlace del documento.")
                )
            }
        }
        .navigationTitle(thesis.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleBookmark(page: currentPage, for: thesis.id)
                } label: {
                    Image(
                        systemName: library.isBookmarked(page: currentPage, for: thesis.id)
                        ? "bookmark.fill"
                        : "bookmark"
                    )
                }
                .accessibilityLabel("Marcar o desmarcar esta página")
            }
        }
        .task {
            await loadDocument()
        }
    }

    @MainActor
    private func loadDocument() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fileURL: URL
            if let cachedURL = library.localPDFURL(for: thesis) {
                fileURL = cachedURL
            } else {
                fileURL = try await library.downloadPDF(for: thesis)
            }

            guard let pdf = PDFDocument(url: fileURL), pdf.pageCount > 0 else {
                throw URLError(.cannotDecodeContentData)
            }

            let savedPage = library.progress[thesis.id]?.page ?? 1
            currentPage = min(max(savedPage, 1), pdf.pageCount)
            document = pdf
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let document: PDFDocument
    let initialPage: Int
    let onPageChanged: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(AppTheme.cream)
        pdfView.document = document

        context.coordinator.pdfView = pdfView
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.notifyCurrentPage()
        }

        goToInitialPage(in: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        if pdfView.document !== document {
            pdfView.document = document
            goToInitialPage(in: pdfView)
        }
    }

    private func goToInitialPage(in pdfView: PDFView) {
        let pageIndex = min(max(initialPage - 1, 0), max(document.pageCount - 1, 0))
        if let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
    }

    final class Coordinator {
        var onPageChanged: (Int, Int) -> Void
        weak var pdfView: PDFView?
        var observer: NSObjectProtocol?

        init(onPageChanged: @escaping (Int, Int) -> Void) {
            self.onPageChanged = onPageChanged
        }

        func notifyCurrentPage() {
            guard let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage else {
                return
            }
            onPageChanged(document.index(for: page) + 1, document.pageCount)
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
