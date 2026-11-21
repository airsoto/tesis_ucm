import PDFKit
import SwiftUI

struct ReaderChapter: Identifiable {
    let id: Int
    let title: String
    let page: Int
    let depth: Int

    static func table(in document: PDFDocument) -> [Self] {
        guard let root = document.outlineRoot else { return [] }
        var chapters: [Self] = []
        var queue: [(PDFOutline, Int)] = [(root, -1)]

        while let (node, depth) = queue.popLast() {
            if depth >= 0,
               let title = node.label?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty,
               let page = (node.destination ?? (node.action as? PDFActionGoTo)?.destination)?.page {
                let index = document.index(for: page)
                if (0..<document.pageCount).contains(index) {
                    chapters.append(Self(id: chapters.count, title: title, page: index + 1, depth: depth))
                }
            }
            for index in (0..<node.numberOfChildren).reversed() {
                if let child = node.child(at: index) { queue.append((child, depth + 1)) }
            }
        }
        return chapters
    }
}

struct ReaderContentsView: View {
    let chapters: [ReaderChapter]
    let marks: [Int]
    let pageCount: Int
    let onSelect: (Int) -> Void
    @State private var pageInput = ""

    var body: some View {
        List {
            Section("Ir a página") {
                TextField("Página entre 1 y \(pageCount)", text: $pageInput)
                    .keyboardType(.numberPad)
                Button("Ir a la página") {
                    if let number = Int(pageInput), (1...pageCount).contains(number) { onSelect(number) }
                }
                .disabled(!(1...pageCount).contains(Int(pageInput) ?? 0))
            }

            Section("Índice del PDF") {
                if chapters.isEmpty {
                    Text("El documento no incluye un índice navegable.")
                        .foregroundStyle(AppTheme.muted)
                }
                ForEach(chapters) { chapter in
                    Button {
                        onSelect(chapter.page)
                    } label: {
                        LabeledContent(chapter.title, value: "\(chapter.page)")
                            .padding(.leading, CGFloat(min(chapter.depth, 3) * 12))
                    }
                }
            }

            if !marks.isEmpty {
                Section("Marcadores") {
                    ForEach(marks.filter { (1...pageCount).contains($0) }, id: \.self) { page in
                        Button("Página \(page)", systemImage: "bookmark.fill") { onSelect(page) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.cream)
    }
}

struct ReaderSearchView: View {
    let source: PDFReadingText
    let onSelect: (Int, String) -> Void
    @State private var query = ""
    @State private var submitted = ""
    @State private var results: [PDFSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        List {
            Section {
                TextField("Palabra o frase", text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(search)
                Button("Buscar", systemImage: "magnifyingglass", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if isSearching {
                ProgressView("Buscando en el PDF…")
            } else if !submitted.isEmpty, results.isEmpty {
                Text("No se encontraron coincidencias en el texto del PDF.")
                    .foregroundStyle(AppTheme.muted)
            } else if !results.isEmpty {
                Section("\(results.count) páginas con coincidencias") {
                    ForEach(results) { result in
                        Button {
                            onSelect(result.page, submitted)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Página \(result.page)")
                                    .font(.headline)
                                Text(result.excerpt)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.cream)
        .task(id: submitted) {
            guard !submitted.isEmpty else { return }
            let term = submitted
            isSearching = true
            do {
                let matches = try await source.search(term)
                guard !Task.isCancelled, term == submitted else { return }
                results = matches
                isSearching = false
            } catch {
                if !Task.isCancelled, term == submitted { isSearching = false }
            }
        }
    }

    private func search() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, submitted != value else { return }
        results = []
        isSearching = true
        submitted = value
    }
}
