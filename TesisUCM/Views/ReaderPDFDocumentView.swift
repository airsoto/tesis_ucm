import PDFKit
import SwiftUI
import UIKit

struct PDFReaderDestination: Equatable {
    let id = UUID()
    let page: Int
    let query: String?
}

struct ReaderPDFDocumentView: UIViewRepresentable {
    let document: PDFDocument
    let initialPage: Int
    let destination: PDFReaderDestination?
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(AppTheme.cream)
        view.document = document
        let request = destination?.page == initialPage ? destination : nil
        context.coordinator.destination = destination
        // PDFKit can reset currentPage while its view is being attached.
        // Defer the initial jump until the PDFView has entered the view hierarchy.
        let startingPage = initialPage
        let startingQuery = request?.query
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            move(view, to: startingPage, query: startingQuery)
            coordinator.isReady = true
        }

        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: view,
            queue: .main
        ) { [weak coordinator = context.coordinator, weak view] _ in
            DispatchQueue.main.async {
                guard let coordinator, coordinator.isReady,
                      let view, let page = view.currentPage,
                      let document = view.document else { return }
                coordinator.onPageChanged(document.index(for: page) + 1)
            }
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        if view.document !== document {
            context.coordinator.isReady = false
            view.document = document
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                move(view, to: initialPage, query: nil)
                context.coordinator.isReady = true
            }
        }
        if context.coordinator.destination != destination, let destination {
            context.coordinator.destination = destination
            context.coordinator.isReady = false
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                move(view, to: destination.page, query: destination.query)
                context.coordinator.isReady = true
            }
        }
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.onPageChanged = { _ in }
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func move(_ view: PDFView, to number: Int, query: String?) {
        guard let page = document.page(at: number - 1) else { return }
        view.clearSelection()
        view.go(to: page)
        guard let query, let text = page.string,
              let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return
        }
        let range = NSRange(match, in: text)
        guard range.length > 0, NSMaxRange(range) <= page.numberOfCharacters,
              let selection = page.selection(for: range) else { return }
        view.setCurrentSelection(selection, animate: false)
        view.go(to: selection)
    }

    final class Coordinator {
        var onPageChanged: (Int) -> Void
        var destination: PDFReaderDestination?
        var isReady = false
        var observer: NSObjectProtocol?

        init(onPageChanged: @escaping (Int) -> Void) {
            self.onPageChanged = onPageChanged
        }
    }
}
