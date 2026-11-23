import PDFKit
import SwiftUI
import UIKit

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
    @State private var paginatedTurn = PaginatedTurnCommand()

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
        if showAdaptiveControls { return adaptiveLayout == .paginated ? 64 : 112 }
        return adaptiveLayout == .paginated ? 104 : 132
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
                library.updateProgress(
                    for: thesis.id,
                    page: currentPage,
                    pageCount: document.pageCount,
                    mode: mode.rawValue,
                    adaptiveLayout: adaptiveLayout.rawValue
                )
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
            library.updateProgress(
                for: thesis.id,
                page: currentPage,
                pageCount: document.pageCount,
                mode: mode.rawValue,
                adaptiveLayout: adaptiveLayout.rawValue
            )
        }
        .onChange(of: adaptiveLayout) { _, layout in
            library.updateProgress(
                for: thesis.id,
                page: currentPage,
                pageCount: document.pageCount,
                mode: mode.rawValue,
                adaptiveLayout: layout.rawValue
            )
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
                initialFragment: library.progress[thesis.id]?.fragment,
                chapters: contents,
                typeface: typeface,
                size: textSize,
                lineSpacing: lineSpacing,
                margins: margins,
                palette: palette,
                bottomClearance: adaptiveBottomClearance,
                onPositionChanged: { page, fragment in
                    library.updateProgress(
                        for: thesis.id,
                        page: page,
                        pageCount: count,
                        fragment: fragment,
                        mode: ReaderMode.adaptive.rawValue,
                        adaptiveLayout: AdaptiveReadingLayout.continuous.rawValue
                    )
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
                        turnCommand: paginatedTurn,
                        onPreviousPage: { navigate(to: page - 1, count: count, fragment: Int.max) },
                        onNextPage: { navigate(to: page + 1, count: count, fragment: 0) },
                        onPositionChanged: { fragment in
                            guard currentPage == page else { return }
                            library.updateProgress(
                                for: thesis.id,
                                page: page,
                                pageCount: count,
                                fragment: fragment,
                                mode: ReaderMode.adaptive.rawValue,
                                adaptiveLayout: AdaptiveReadingLayout.paginated.rawValue
                            )
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
                    if mode == .adaptive && adaptiveLayout == .paginated {
                        paginatedTurn = PaginatedTurnCommand(id: paginatedTurn.id + 1, direction: -1)
                    } else {
                        navigate(to: currentPage - 1, count: count)
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(mode == .adaptive && adaptiveLayout == .paginated ? false : currentPage <= 1)

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
                    if mode == .adaptive && adaptiveLayout == .paginated {
                        paginatedTurn = PaginatedTurnCommand(id: paginatedTurn.id + 1, direction: 1)
                    } else {
                        navigate(to: currentPage + 1, count: count)
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(mode == .adaptive && adaptiveLayout == .paginated ? false : currentPage >= count)
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

    private func navigate(to page: Int, count: Int, query: String? = nil, fragment: Int? = nil) {
        guard (1...count).contains(page) else { return }
        updatePage(page, count: count)
        if let fragment {
            library.updateProgress(
                for: thesis.id,
                page: page,
                pageCount: count,
                fragment: fragment,
                mode: mode.rawValue,
                adaptiveLayout: adaptiveLayout.rawValue
            )
        }
        destination = PDFReaderDestination(page: page, query: query)
    }

    private func updatePage(_ page: Int, count: Int) {
        if page != currentPage { speech.stop() }
        currentPage = page
        library.updateProgress(
            for: thesis.id,
            page: page,
            pageCount: count,
            mode: mode.rawValue,
            adaptiveLayout: adaptiveLayout.rawValue
        )
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
            if let savedLayout = progress?.adaptiveLayout.flatMap(AdaptiveReadingLayout.init(rawValue:)) {
                adaptiveLayout = savedLayout
            }
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

private struct PaginatedTurnCommand: Equatable {
    var id = 0
    var direction = 0
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
private struct ReaderTextPosition: Hashable {
    let page: Int
    let fragment: Int
}

private struct AdaptiveContinuousReader: View {
    let source: PDFReadingText
    let count: Int
    @Binding var currentPage: Int
    let initialFragment: Int?
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
    @State private var lastReportedPosition: ReaderTextPosition?

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
                            palette: palette
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
            .onPreferenceChange(ReaderFragmentTopPreference.self) { positions in
                guard hasScrolledToInitialPage, !positions.isEmpty else { return }
                let above = positions.filter { $0.value <= 96 }
                let active = above.max(by: { $0.value < $1.value })
                    ?? positions.min(by: { $0.value < $1.value })
                guard let position = active?.key, position != lastReportedPosition else { return }
                lastReportedPosition = position
                scrollDrivenPage = position.page
                currentPage = position.page
                onPositionChanged(position.page, position.fragment)
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
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                if let initialFragment, initialFragment > 0 {
                    proxy.scrollTo(
                        ReaderTextPosition(page: currentPage, fragment: initialFragment),
                        anchor: .top
                    )
                    try? await Task.sleep(for: .milliseconds(180))
                }
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
                            .id(ReaderTextPosition(page: pageNumber, fragment: index))
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ReaderFragmentTopPreference.self,
                                        value: [
                                            ReaderTextPosition(page: pageNumber, fragment: index):
                                                geometry.frame(in: .named("thesisReaderViewport")).minY
                                        ]
                                    )
                                }
                            }
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
    let turnCommand: PaginatedTurnCommand
    let onPreviousPage: () -> Void
    let onNextPage: () -> Void
    let onPositionChanged: (Int) -> Void

    @ScaledMetric(relativeTo: .body) private var baseSize = 20.0
    @State private var fragments: [NSAttributedString] = []
    @State private var fragmentIndex: Int

    init(page: PDFReadingPage, initialFragment: Int?, chapter: String?, typeface: ReaderTypeface,
         size: Double, lineSpacing: Double, margins: Double, palette: ReaderPalette,
         bottomClearance: CGFloat, turnCommand: PaginatedTurnCommand,
         onPreviousPage: @escaping () -> Void,
         onNextPage: @escaping () -> Void, onPositionChanged: @escaping (Int) -> Void) {
        self.page = page
        self.chapter = chapter
        self.typeface = typeface
        self.size = size
        self.lineSpacing = lineSpacing
        self.margins = margins
        self.palette = palette
        self.bottomClearance = bottomClearance
        self.turnCommand = turnCommand
        self.onPreviousPage = onPreviousPage
        self.onNextPage = onNextPage
        self.onPositionChanged = onPositionChanged
        _fragmentIndex = State(initialValue: max(0, initialFragment ?? 0))
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset = CGFloat(margins)
            let topInset: CGFloat = 36
            let bottomInset = max(bottomClearance, 72)
            let textSize = CGSize(
                width: max(1, geometry.size.width - horizontalInset * 2),
                height: max(1, geometry.size.height - topInset - bottomInset - 12)
            )
            let key = PaginationKey(
                width: Int(textSize.width.rounded()),
                height: Int(textSize.height.rounded()),
                fontSize: Int((CGFloat(baseSize) * CGFloat(size) / 20 * 10).rounded()),
                lineSpacing: Int((lineSpacing * 10).rounded()),
                typeface: typeface.rawValue,
                palette: palette.rawValue
            )

            ZStack {
                palette.background

                if fragments.isEmpty {
                    ProgressView("Preparando página…")
                } else {
                    PaginatedTextView(
                        text: fragments[min(fragmentIndex, fragments.count - 1)],
                        foreground: UIColor(palette.foreground),
                        background: UIColor(palette.background)
                    )
                    .frame(width: textSize.width, height: textSize.height, alignment: .topLeading)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .accessibilityLabel("Fragmento \(fragmentIndex + 1) de \(fragments.count), página \(page.number)")
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture().onEnded { touch in
                    if touch.location.x >= geometry.size.width / 2 {
                        advance()
                    } else {
                        goBack()
                    }
                }
            )
            .task(id: key) {
                let attributedText = makeAttributedText()
                fragments = TextPaginator.pages(from: attributedText, fitting: textSize)
                fragmentIndex = min(fragmentIndex, max(0, fragments.count - 1))
                onPositionChanged(fragmentIndex)
            }
            .onChange(of: turnCommand.id) { _, _ in
                if turnCommand.direction > 0 {
                    advance()
                } else if turnCommand.direction < 0 {
                    goBack()
                }
            }
        }
        .foregroundStyle(palette.foreground)
        .background(palette.background)
    }

    private func advance() {
        guard !fragments.isEmpty else { return }
        if fragmentIndex < fragments.count - 1 {
            fragmentIndex += 1
            onPositionChanged(fragmentIndex)
        } else {
            onNextPage()
        }
    }

    private func goBack() {
        if fragmentIndex > 0 {
            fragmentIndex -= 1
            onPositionChanged(fragmentIndex)
        } else {
            onPreviousPage()
        }
    }

    private func makeAttributedText() -> NSAttributedString {
        let bodySize = CGFloat(baseSize) * CGFloat(size) / 20
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        paragraphStyle.paragraphSpacing = 12

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: typeface.uiFont(size: bodySize),
            .foregroundColor: UIColor(palette.foreground),
            .paragraphStyle: paragraphStyle
        ]
        let result = NSMutableAttributedString(string: "")
        if let chapter {
            let headingStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            headingStyle.paragraphSpacing = 18
            result.append(NSAttributedString(
                string: chapter + "\n",
                attributes: [
                    .font: typeface.uiFont(size: bodySize + 10).withTraits(.traitBold),
                    .foregroundColor: UIColor(palette.foreground),
                    .paragraphStyle: headingStyle
                ]
            ))
        }
        result.append(NSAttributedString(
            string: page.paragraphs.joined(separator: "\n\n"),
            attributes: bodyAttributes
        ))
        return result
    }
}

private struct PaginationKey: Equatable {
    let width: Int
    let height: Int
    let fontSize: Int
    let lineSpacing: Int
    let typeface: String
    let palette: String
}

private enum TextPaginator {
    static func pages(from text: NSAttributedString, fitting size: CGSize) -> [NSAttributedString] {
        guard text.length > 0, size.width > 0, size.height > 0 else { return [] }
        var pages: [NSAttributedString] = []
        var location = 0

        while location < text.length {
            let remaining = text.attributedSubstring(from: NSRange(location: location, length: text.length - location))
            let storage = NSTextStorage(attributedString: remaining)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            container.lineBreakMode = .byWordWrapping
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)

            let glyphRange = layout.glyphRange(for: container)
            var characterRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if characterRange.length == 0 {
                characterRange = NSRange(location: 0, length: min(1, remaining.length))
            }
            pages.append(remaining.attributedSubstring(from: characterRange))
            location += characterRange.length
        }
        return pages
    }
}

private struct PaginatedTextView: UIViewRepresentable {
    let text: NSAttributedString
    let foreground: UIColor
    let background: UIColor

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = background
        view.contentInset = .zero
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.heightTracksTextView = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = text
        view.textColor = foreground
        view.backgroundColor = background
        view.textContainer.widthTracksTextView = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

private extension ReaderTypeface {
    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .georgia:
            return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case .newYork:
            let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return descriptor.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        case .sanFrancisco:
            return .systemFont(ofSize: size)
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private struct ReaderPageTopPreference: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ReaderFragmentTopPreference: PreferenceKey {
    static var defaultValue: [ReaderTextPosition: CGFloat] = [:]

    static func reduce(value: inout [ReaderTextPosition: CGFloat], nextValue: () -> [ReaderTextPosition: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
