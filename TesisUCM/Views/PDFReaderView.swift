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
    @AppStorage("reader.adaptiveLayout") private var adaptiveLayout: AdaptiveReadingLayout = .continuous
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
    @State private var showAdaptiveControls = false

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

    private var adaptiveBottomClearance: CGFloat {
        if showAdaptiveControls { return adaptiveLayout == .paginated ? 110 : 52 }
        return adaptiveLayout == .paginated ? 120 : 112
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
        .onDisappear {
            speech.stop()
            if let document {
                library.updateProgress(for: thesis.id, page: currentPage, pageCount: document.pageCount, mode: mode.rawValue)
            }
        }
    }

    private func reader(_ document: PDFDocument, source: PDFReadingText) -> some View {
        VStack(spacing: 0) {
            if mode == .pdf || showAdaptiveControls {
                HStack(spacing: 10) {
                    Picker("Modo de lectura", selection: $mode) {
                        Text("Lectura adaptable").tag(ReaderMode.adaptive)
                        Text("PDF original").tag(ReaderMode.pdf)
                    }
                    .pickerStyle(.segmented)

                    if mode == .adaptive {
                        Button("Ocultar controles", systemImage: "xmark") {
                            showAdaptiveControls = false
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Ocultar controles de lectura")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                Divider()
            }

            Group {
                if mode == .pdf {
                    ReaderPDFDocumentView(
                        document: document,
                        initialPage: currentPage,
                        destination: destination,
                        onPageChanged: { updatePage($0, count: document.pageCount) }
                    )
                } else {
                    adaptiveReader(count: document.pageCount, source: source)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if mode == .pdf || showAdaptiveControls {
                Divider()
                readerControls(count: document.pageCount)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if mode == .adaptive && !showAdaptiveControls {
                Button {
                    showAdaptiveControls = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(AppTheme.line, lineWidth: 1))
                }
                .foregroundStyle(AppTheme.burgundy)
                .accessibilityLabel("Mostrar controles de lectura")
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .tint(AppTheme.burgundy)
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
            if mode == .adaptive { showAdaptiveControls = false }
            // Keep the same document page when changing between PDF and reflowed text.
            if mode == .pdf { destination = PDFReaderDestination(page: currentPage, query: nil) }
            library.updateProgress(for: thesis.id, page: currentPage, pageCount: document.pageCount, mode: mode.rawValue)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func adaptiveReader(count: Int, source: PDFReadingText) -> some View {
        if adaptiveLayout == .continuous {
            AdaptiveContinuousReader(
                source: source,
                count: count,
                currentPage: $currentPage,
                chapters: contents,
                typeface: typeface,
                size: textSize,
                lineSpacing: lineSpacing,
                margins: margins,
                palette: palette,
                bottomClearance: adaptiveBottomClearance,
                onPositionChanged: { page, fragment in
                    library.updateProgress(for: thesis.id, page: page, pageCount: count, fragment: fragment, mode: ReaderMode.adaptive.rawValue)
                }
            )
        } else {
            adaptivePage(count: count, source: source)
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
                        chapter: contents.last { $0.page == page && $0.depth == 0 }?.title,
                        typeface: typeface,
                        size: textSize,
                        lineSpacing: lineSpacing,
                        margins: margins,
                        palette: palette,
                        bottomClearance: adaptiveBottomClearance,
                        onPositionChanged: { fragment in
                            guard currentPage == page else { return }
                            library.updateProgress(for: thesis.id, page: page, pageCount: count, fragment: fragment)
                        }
                    )
                    .id(page)
                    .overlay {
                        GeometryReader { proxy in
                            Color.clear
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    SpatialTapGesture().onEnded { touch in
                                        if touch.location.x >= proxy.size.width / 2 {
                                            navigate(to: page + 1, count: count)
                                        } else {
                                            navigate(to: page - 1, count: count)
                                        }
                                    }
                                )
                            .accessibilityHidden(true)
                        }
                    }
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
                layout: $adaptiveLayout,
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
            // Restore the last reading mode as well as the page.
            mode = progress?.mode == ReaderMode.pdf.rawValue ? .pdf : .adaptive
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

/// Reflows the extracted text across the available width.  Unlike the original PDF,
/// this mode follows the reader's selected font, spacing and page margins.
private struct AdaptiveContinuousReader: View {
    let source: PDFReadingText
    let count: Int
    @Binding var currentPage: Int
    let chapters: [ReaderChapter]
    let typeface: ReaderTypeface
    let size: Double
    let lineSpacing: Double
    let margins: Double
    let palette: ReaderPalette
    let bottomClearance: CGFloat
    let onPositionChanged: (Int, Int) -> Void

    @State private var hasScrolledToInitialPage = false
    @State private var scrollDrivenPage: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(1...count, id: \.self) { pageNumber in
                        AdaptiveContinuousPage(
                            pageNumber: pageNumber,
                            source: source,
                            chapter: chapters.last { $0.page == pageNumber && $0.depth == 0 }?.title,
                            typeface: typeface,
                            size: size,
                            lineSpacing: lineSpacing,
                            margins: margins,
                            palette: palette,
                            onPageVisible: { _ in },
                            onFragmentVisible: { _, _ in }
                        )
                        .id(pageNumber)
                    }
                    .padding(.bottom, bottomClearance)
                }
            }
            .coordinateSpace(name: "thesisReaderViewport")
            // Only the page nearest the top of the visible viewport is current.
            // LazyVStack.onAppear is unreliable: prefetched pages can overwrite progress.
            .onPreferenceChange(ReaderPageTopPreference.self) { positions in
                guard hasScrolledToInitialPage, !positions.isEmpty else { return }
                let above = positions.filter { $0.value <= 80 }
                let active = above.max(by: { $0.value < $1.value })
                    ?? positions.min(by: { $0.value < $1.value })
                guard let page = active?.key, page != currentPage else { return }
                scrollDrivenPage = page
                currentPage = page
                onPositionChanged(page, 0)
            }
            // Extra scrollable content keeps the final line clear of the Home indicator.
            .contentMargins(.top, 24, for: .scrollContent)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .task {
                guard !hasScrolledToInitialPage else { return }
                // The first scroll must wait until the lazy stack has mounted.
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(currentPage, anchor: .top)
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                hasScrolledToInitialPage = true
            }
            .onChange(of: currentPage) { _, page in
                guard hasScrolledToInitialPage else { return }
                if scrollDrivenPage == page {
                    scrollDrivenPage = nil
                    return
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(page, anchor: .top)
                }
            }
        }
        .foregroundStyle(palette.foreground)
        .background(palette.background)
    }
}

private struct AdaptiveContinuousPage: View {
    let pageNumber: Int
    let source: PDFReadingText
    let chapter: String?
    let typeface: ReaderTypeface
    let size: Double
    let lineSpacing: Double
    let margins: Double
    let palette: ReaderPalette
    let onPageVisible: (Int) -> Void
    let onFragmentVisible: (Int, Int) -> Void

    @ScaledMetric(relativeTo: .body) private var baseSize = 20.0
    @State private var textPage: PDFReadingPage?

    var body: some View {
        Group {
            if let textPage {
                VStack(alignment: .leading, spacing: 16) {
                    if let chapter {
                        Text(chapter)
                            .font(typeface.font(size: baseSize * size / 20 + 10).bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(textPage.paragraphs.indices, id: \.self) { index in
                        Text(textPage.paragraphs[index])
                            .font(typeface.font(size: baseSize * size / 20))
                            .lineSpacing(lineSpacing)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Paragraph onAppear is prefetch-driven; do not corrupt saved position.
                    }
                }
                .padding(.horizontal, margins)
                .padding(.vertical, 22)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity, alignment: .center)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ReaderPageTopPreference.self,
                            value: [pageNumber: geometry.frame(in: .named("thesisReaderViewport")).minY]
                        )
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .task(id: pageNumber) { textPage = await source.page(pageNumber) }
            }
        }
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
    let bottomClearance: CGFloat
    let onPositionChanged: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var baseSize = 20.0
    @State private var position: Int?

    init(page: PDFReadingPage, initialFragment: Int?, chapter: String?, typeface: ReaderTypeface,
         size: Double, lineSpacing: Double, margins: Double, palette: ReaderPalette,
         bottomClearance: CGFloat, onPositionChanged: @escaping (Int) -> Void) {
        self.page = page
        self.chapter = chapter
        self.typeface = typeface
        self.size = size
        self.lineSpacing = lineSpacing
        self.margins = margins
        self.palette = palette
        self.bottomClearance = bottomClearance
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
            .padding(.top, 22)
            // In paginated mode this padding is part of the scrollable content,
            // so the last paragraph can move completely above the bottom controls.
            .padding(.bottom, 160 + bottomClearance)
            .frame(maxWidth: .infinity)
        }
        // Reserve real viewport space above the Home indicator and floating
        // reader controls. The final paragraph can now scroll fully into view.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 88)
        }
        .contentMargins(.top, 24, for: .scrollContent)
        .contentMargins(.bottom, 48, for: .scrollContent)
        .scrollPosition(id: $position, anchor: .top)
        .onChange(of: position) { _, position in
            if let position { onPositionChanged(position) }
        }
        .foregroundStyle(palette.foreground)
    }
}

private struct ReaderPageTopPreference: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
