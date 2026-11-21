import PDFKit
import SwiftUI

struct PDFReaderView: View {
    let thesis: Thesis

    @EnvironmentObject private var library: LibraryStore
    @State private var mode: ReaderMode = .adaptive
    @AppStorage("reader.typeface") private var typeface: ReaderTypeface = .georgia
    @AppStorage("reader.size") private var textSize = 19.0
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
    @State private var scrubPage: Double?

    private enum Sheet: String, Identifiable {
        case contents, search, text, appearance
        var id: Self { self }

        var title: String {
            switch self {
            case .contents: "Índice y marcadores"
            case .search: "Buscar en la tesis"
            case .text: "Texto y tipografía"
            case .appearance: "Apariencia"
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
                        library.removeDownloadedPDF(for: thesis)
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
                Text("Lectura adaptable").tag(ReaderMode.adaptive)
                Text("PDF original").tag(ReaderMode.pdf)
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

                let marked = library.isBookmarked(page: currentPage, for: thesis.id)
                Button(marked ? "Quitar marcador" : "Marcar página",
                       systemImage: marked ? "bookmark.fill" : "bookmark") {
                    library.toggleBookmark(page: currentPage, for: thesis.id)
                }
                .labelStyle(.iconOnly)
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
            library.updateProgress(for: thesis.id, page: currentPage, pageCount: document.pageCount, mode: mode.rawValue)
        }
        .toolbar(.hidden, for: .tabBar)
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
                        chapter: contents.last { $0.page == page && $0.depth == 0 }?.title,
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
        let readablePage = textPage.flatMap { $0.number == currentPage && !$0.paragraphs.isEmpty ? $0 : nil }
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button("Página anterior", systemImage: "chevron.left") {
                    navigate(to: currentPage - 1, count: count)
                }
                .labelStyle(.iconOnly)
                .disabled(currentPage <= 1)

                if count > 1 {
                    Slider(value: Binding(
                        get: { scrubPage ?? Double(currentPage) },
                        set: { scrubPage = $0 }
                    ), in: 1...Double(count), step: 1) { editing in
                        if !editing, let page = scrubPage {
                            scrubPage = nil
                            navigate(to: Int(page), count: count)
                        }
                    }
                    .accessibilityLabel("Página del documento")
                }
                Button {
                    sheet = .contents
                } label: {
                    Text("\(Int(scrubPage ?? Double(currentPage))) de \(count)")
                        .font(.caption.monospacedDigit())
                }
                .accessibilityLabel("Ir a una página. Página \(currentPage) de \(count).")

                Button("Página siguiente", systemImage: "chevron.right") {
                    navigate(to: currentPage + 1, count: count)
                }
                .labelStyle(.iconOnly)
                .disabled(currentPage >= count)
            }
            .buttonStyle(ReaderControlStyle())

            HStack(spacing: 7) {
                if mode == .adaptive {
                    panelButton("Texto", icon: "textformat.size") { sheet = .text }
                    panelButton("Apariencia", icon: "sun.max") { sheet = .appearance }
                    panelButton(speech.isPaused ? "Reanudar" : (speech.isSpeaking ? "Pausar" : "Escuchar"),
                                icon: speech.isSpeaking && !speech.isPaused ? "pause.fill" : "headphones") {
                        if let readablePage {
                            speech.toggle(text: readablePage.paragraphs.joined(separator: "\n\n"), rate: speechRate)
                        }
                    }
                    .disabled(readablePage == nil)
                    .contextMenu {
                        if speech.isSpeaking { Button("Detener lectura") { speech.stop() } }
                    }
                }
                panelButton("Índice", icon: "list.bullet") { sheet = .contents }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .foregroundStyle(AppTheme.burgundy)
        .background(AppTheme.paper)
    }

    private func panelButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3).accessibilityHidden(true)
                Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.borderless)
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
        case .text, .appearance:
            ReaderAppearanceView(
                typeface: $typeface,
                size: $textSize,
                spacing: $lineSpacing,
                margins: $margins,
                palette: $palette,
                speechRate: $speechRate,
                appearanceOnly: active == .appearance
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
        library.updateProgress(for: thesis.id, page: page, pageCount: count, mode: mode.rawValue)
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

            let progress = library.progress[thesis.id]
            let savedPage = progress?.page ?? 1
            let legacyMode = UserDefaults.standard.string(forKey: "reader.mode").flatMap(ReaderMode.init(rawValue:))
            mode = progress?.mode.flatMap(ReaderMode.init(rawValue:)) ?? legacyMode ?? .adaptive
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
    let chapter: String?
    let typeface: ReaderTypeface
    let size: Double
    let lineSpacing: Double
    let margins: Double
    let palette: ReaderPalette
    let onPositionChanged: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var baseSize = 20.0
    @State private var position: Int?

    init(page: PDFReadingPage, initialFragment: Int?, chapter: String?, typeface: ReaderTypeface,
         size: Double, lineSpacing: Double, margins: Double, palette: ReaderPalette,
         onPositionChanged: @escaping (Int) -> Void) {
        self.page = page
        self.chapter = chapter
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
                if let chapter {
                    Text(chapter)
                        .font(typeface.font(size: baseSize * size / 20 + 10).bold())
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(page.paragraphs.indices, id: \.self) { index in
                    Text(page.paragraphs[index])
                        .font(typeface.font(size: baseSize * size / 20))
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
