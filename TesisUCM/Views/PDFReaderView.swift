import PDFKit
import SwiftUI

struct PDFReaderView: View {
    let thesis: Thesis

    @EnvironmentObject private var library: LibraryStore
    @AppStorage("reader.mode") private var mode: ReaderMode = .pdf
    @AppStorage("reader.typeface") private var typeface: ReaderTypeface = .serif
    @AppStorage("reader.size") private var textSize = 20.0
    @AppStorage("reader.spacing") private var lineSpacing = 6.0
    @AppStorage("reader.margins") private var margins = 24.0
    @AppStorage("reader.palette") private var palette: ReaderPalette = .sepia
    @AppStorage("reader.speechRate") private var speechRate = 1.0
    @StateObject private var speech = ReaderSpeech()
    @State private var document: PDFDocument?
    @State private var source: PDFReadingText?
    @State private var contents: [ReaderChapter] = []
    @State private var currentPage = 1
    @State private var textPage: PDFReadingPage?
    @State private var destination: PDFReaderDestination?
    @State private var sheet: Sheet?
    @State private var loadError: String?
    @State private var loadAttempt = 0

    private enum Sheet: String, Identifiable {
        case contents, search, appearance
        var id: Self { self }

        var title: String {
            switch self {
            case .contents: "Índice y marcadores"
            case .search: "Buscar en la tesis"
            case .appearance: "Ajustes de lectura"
            }
        }
    }

    var body: some View {
        Group {
            if let document, let source {
                reader(document, source: source)
            } else if let loadError {
                ContentUnavailableView {
                    Label("No se puede abrir el PDF", systemImage: "doc.questionmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Reintentar") {
                        self.loadError = nil
                        loadAttempt += 1
                    }
                }
            } else {
                ProgressView("Preparando el documento…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tint(AppTheme.burgundy)
            }
        }
        .background(AppTheme.cream.ignoresSafeArea())
        .navigationTitle(thesis.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadAttempt) { await loadDocument() }
        .onDisappear { speech.stop() }
    }

    private func reader(_ document: PDFDocument, source: PDFReadingText) -> some View {
        VStack(spacing: 0) {
            Picker("Modo de lectura", selection: $mode) {
                Text("PDF original").tag(ReaderMode.pdf)
                Text("Texto adaptable").tag(ReaderMode.adaptive)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            Divider()

            Group {
                if mode == .pdf {
                    ReaderPDFDocumentView(
                        document: document,
                        initialPage: currentPage,
                        destination: destination,
                        onPageChanged: { updatePage($0, count: document.pageCount) }
                    )
                } else {
                    adaptivePage(count: document.pageCount, source: source)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            readerControls(count: document.pageCount)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    sheet = .search
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Buscar en la tesis")

                Button {
                    sheet = .appearance
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Ajustes de lectura")
            }
        }
        .sheet(item: $sheet) { active in
            NavigationStack {
                sheetContents(active, count: document.pageCount, source: source)
                    .navigationTitle(active.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Hecho") { sheet = nil }
                        }
                    }
            }
            .tint(AppTheme.burgundy)
        }
        .onChange(of: mode) { _, mode in
            if mode == .pdf { speech.stop() }
        }
    }

    private func adaptivePage(count: Int, source: PDFReadingText) -> some View {
        let page = currentPage
        return Group {
            if let textPage, textPage.number == page {
                if textPage.paragraphs.isEmpty {
                    ContentUnavailableView {
                        Label("Texto no disponible", systemImage: "doc.viewfinder")
                    } description: {
                        Text("Esta página puede ser un escaneo. Puedes consultarla en el PDF original.")
                    } actions: {
                        Button("Abrir página en PDF") { mode = .pdf }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.burgundy)
                    }
                } else {
                    AdaptiveReaderPage(
                        page: textPage,
                        initialFragment: library.progress[thesis.id]?.fragment,
                        typeface: typeface,
                        size: textSize,
                        lineSpacing: lineSpacing,
                        margins: margins,
                        palette: palette,
                        onPositionChanged: { fragment in
                            guard currentPage == page else { return }
                            library.updateProgress(for: thesis.id, page: page, pageCount: count, fragment: fragment)
                        }
                    )
                    .id(page)
                }
            } else {
                ProgressView("Preparando la página…")
            }
        }
        .foregroundStyle(palette.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .task(id: page) {
            let extracted = await source.page(page)
            guard !Task.isCancelled else { return }
            textPage = extracted
        }
    }

    private func readerControls(count: Int) -> some View {
        VStack(spacing: 0) {
            if mode == .adaptive, let textPage, textPage.number == currentPage, !textPage.paragraphs.isEmpty {
                HStack {
                    Button {
                        speech.toggle(text: textPage.paragraphs.joined(separator: "\n\n"), rate: speechRate)
                    } label: {
                        let pause = speech.isSpeaking && !speech.isPaused
                        Label(pause ? "Pausar" : (speech.isPaused ? "Reanudar" : "Escuchar página"),
                              systemImage: pause ? "pause.fill" : "speaker.wave.2")
                    }
                    Spacer()
                    if speech.isSpeaking {
                        Button("Detener", systemImage: "stop.fill") { speech.stop() }
                            .labelStyle(.iconOnly)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                Divider()
            }

            HStack(spacing: 0) {
                Button("Índice y marcadores", systemImage: "list.bullet") { sheet = .contents }
                    .labelStyle(.iconOnly)
                Spacer(minLength: 0)
                Button("Página anterior", systemImage: "chevron.left") {
                    navigate(to: currentPage - 1, count: count)
                }
                .labelStyle(.iconOnly)
                .disabled(currentPage <= 1)

                Button {
                    sheet = .contents
                } label: {
                    Text("\(currentPage) / \(count)")
                        .font(.subheadline.monospacedDigit())
                }
                .accessibilityLabel("Página \(currentPage) de \(count). Ir a una página.")

                Button("Página siguiente", systemImage: "chevron.right") {
                    navigate(to: currentPage + 1, count: count)
                }
                .labelStyle(.iconOnly)
                .disabled(currentPage >= count)
                Spacer(minLength: 0)
                let marked = library.isBookmarked(page: currentPage, for: thesis.id)
                Button(marked ? "Quitar marcador" : "Marcar página",
                       systemImage: marked ? "bookmark.fill" : "bookmark") {
                    library.toggleBookmark(page: currentPage, for: thesis.id)
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(ReaderControlStyle())
            .padding(.horizontal, 8)
        }
        .foregroundStyle(AppTheme.burgundy)
        .background(AppTheme.paper)
    }

    @ViewBuilder
    private func sheetContents(_ active: Sheet, count: Int, source: PDFReadingText) -> some View {
        switch active {
        case .contents:
            ReaderContentsView(
                chapters: contents,
                marks: library.bookmarkPages(for: thesis.id),
                pageCount: count
            ) { page in
                navigate(to: page, count: count)
                sheet = nil
            }
        case .search:
            ReaderSearchView(source: source) { page, query in
                mode = .pdf
                navigate(to: page, count: count, query: query)
                sheet = nil
            }
        case .appearance:
            ReaderAppearanceView(
                typeface: $typeface,
                size: $textSize,
                spacing: $lineSpacing,
                margins: $margins,
                palette: $palette,
                speechRate: $speechRate
            )
        }
    }

    private func navigate(to page: Int, count: Int, query: String? = nil) {
        guard (1...count).contains(page) else { return }
        updatePage(page, count: count)
        destination = PDFReaderDestination(page: page, query: query)
    }

    private func updatePage(_ page: Int, count: Int) {
        if page != currentPage { speech.stop() }
        currentPage = page
        library.updateProgress(for: thesis.id, page: page, pageCount: count)
    }

    @MainActor
    private func loadDocument() async {
        do {
            let fileURL: URL
            if let cachedURL = library.localPDFURL(for: thesis) {
                fileURL = cachedURL
            } else {
                fileURL = try await library.downloadPDF(for: thesis)
            }
            try Task.checkCancellation()
            guard let pdf = PDFDocument(url: fileURL), pdf.pageCount > 0, !pdf.isLocked else {
                throw URLError(.cannotDecodeContentData)
            }

            let savedPage = library.progress[thesis.id]?.page ?? 1
            currentPage = min(max(savedPage, 1), pdf.pageCount)
            contents = ReaderChapter.table(in: pdf)
            source = PDFReadingText(url: fileURL)
            document = pdf
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Comprueba la conexión. Si el documento está protegido o dañado, prueba a abrirlo desde su registro original."
        }
    }
}

private enum ReaderMode: String {
    case pdf, adaptive
}

private struct ReaderControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.32)
    }
}

private struct AdaptiveReaderPage: View {
    let page: PDFReadingPage
    let typeface: ReaderTypeface
    let size: Double
    let lineSpacing: Double
    let margins: Double
    let palette: ReaderPalette
    let onPositionChanged: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var baseSize = 20.0
    @State private var position: Int?

    init(page: PDFReadingPage, initialFragment: Int?, typeface: ReaderTypeface,
         size: Double, lineSpacing: Double, margins: Double, palette: ReaderPalette,
         onPositionChanged: @escaping (Int) -> Void) {
        self.page = page
        self.typeface = typeface
        self.size = size
        self.lineSpacing = lineSpacing
        self.margins = margins
        self.palette = palette
        self.onPositionChanged = onPositionChanged
        _position = State(initialValue: initialFragment.flatMap { page.paragraphs.indices.contains($0) ? $0 : nil })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(page.paragraphs.indices, id: \.self) { index in
                    Text(page.paragraphs[index])
                        .font(.system(size: baseSize * size / 20, design: typeface.design))
                        .lineSpacing(lineSpacing)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 680)
            .padding(.horizontal, margins)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $position, anchor: .top)
        .onChange(of: position) { _, position in
            if let position { onPositionChanged(position) }
        }
        .foregroundStyle(palette.foreground)
    }
}
