import Foundation
import Combine
import PDFKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var theses: [Thesis] = []
    @Published private(set) var catalogManifest: ThesisManifest?
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?

    @Published private(set) var savedIDs: Set<String> = []
    @Published private(set) var notes: [String: String] = [:]
    @Published private(set) var progress: [String: ReadingProgress] = [:]
    @Published private(set) var bookmarks: [String: Set<Int>] = [:]
    @Published private(set) var downloadedIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private let storageKey = "tesisUCM.localLibrary.v1"
    private let remoteResourcesURL = URL(
        string: "https://raw.githubusercontent.com/airsoto/tesis_ucm/main/TesisUCM/Resources"
    )!

    init() {
        loadLocalState()
    }

    var savedTheses: [Thesis] {
        theses
            .filter { savedIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var downloadedTheses: [Thesis] {
        theses.filter { downloadedIDs.contains($0.id) && isDownloaded($0) }
    }

    func refreshCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let bundledCatalog = Bundle.main.resourceURL?
            .appendingPathComponent("Catalog", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)

        do {
            if catalogManifest == nil,
               let local = await ThesisCatalog.loadLocal(
                   bundled: bundledCatalog,
                   cache: catalogCacheDirectory
               ) {
                useCatalog(local)
            }

            if let updated = try await ThesisCatalog.downloadUpdate(
                from: remoteResourcesURL,
                bundled: bundledCatalog,
                cache: catalogCacheDirectory,
                after: catalogManifest?.version
            ) {
                useCatalog(updated)
            }
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            lastError = "No se ha podido actualizar el catálogo: \(error.localizedDescription)"
        }
    }

    private func useCatalog(_ catalog: ThesisCatalog) {
        theses = catalog.theses
        catalogManifest = catalog.manifest
    }

    func toggleSaved(_ thesis: Thesis) {
        if savedIDs.contains(thesis.id) {
            savedIDs.remove(thesis.id)
        } else {
            savedIDs.insert(thesis.id)
        }
        persistLocalState()
    }

    func isSaved(_ thesis: Thesis) -> Bool {
        savedIDs.contains(thesis.id)
    }

    func saveNote(_ note: String, for thesis: Thesis) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeValue(forKey: thesis.id)
        } else {
            notes[thesis.id] = trimmed
        }
        persistLocalState()
    }

    func updateProgress(for thesisID: String, page: Int, pageCount: Int, fragment: Int? = nil, mode: String? = nil) {
        guard pageCount > 0 else { return }
        let safePage = min(max(page, 1), pageCount)
        let previous = progress[thesisID]
        let savedFragment = fragment ?? (previous?.page == safePage ? previous?.fragment : nil)
        let savedMode = mode ?? previous?.mode
        if previous?.page == safePage, previous?.pageCount == pageCount, previous?.fragment == savedFragment, previous?.mode == savedMode {
            return
        }

        progress[thesisID] = ReadingProgress(
            page: safePage,
            pageCount: pageCount,
            updatedAt: Date(),
            fragment: savedFragment,
            mode: savedMode
        )
        persistLocalState()
    }

    func toggleBookmark(page: Int, for thesisID: String) {
        var pages = bookmarks[thesisID, default: []]
        if pages.contains(page) {
            pages.remove(page)
        } else {
            pages.insert(page)
        }
        bookmarks[thesisID] = pages
        persistLocalState()
    }

    func isBookmarked(page: Int, for thesisID: String) -> Bool {
        bookmarks[thesisID, default: []].contains(page)
    }

    func bookmarkPages(for thesisID: String) -> [Int] {
        bookmarks[thesisID, default: []].sorted()
    }

    func localPDFURL(for thesis: Thesis) -> URL? {
        let url = pdfDirectory.appendingPathComponent(safeFileName(for: thesis)).appendingPathExtension("pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ thesis: Thesis) -> Bool {
        localPDFURL(for: thesis) != nil
    }

    func downloadPDF(for thesis: Thesis) async throws -> URL {
        if let existing = localPDFURL(for: thesis) {
            downloadedIDs.insert(thesis.id)
            persistLocalState()
            return existing
        }

        guard let remoteURL = thesis.pdfURL else {
            throw URLError(.badURL)
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }

        try FileManager.default.createDirectory(
            at: pdfDirectory,
            withIntermediateDirectories: true
        )

        let destinationURL = pdfDirectory
            .appendingPathComponent(safeFileName(for: thesis))
            .appendingPathExtension("pdf")

        // Another reader may have completed the same download while this task was waiting.
        if FileManager.default.fileExists(atPath: destinationURL.path) { return destinationURL }
        let readable = await Task.detached(priority: .utility) {
            guard let pdf = PDFDocument(url: temporaryURL) else { return false }
            return !pdf.isLocked && pdf.pageCount > 0
        }.value
        try Task.checkCancellation()
        guard readable else { throw URLError(.cannotDecodeContentData) }
        if FileManager.default.fileExists(atPath: destinationURL.path) { return destinationURL }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

        downloadedIDs.insert(thesis.id)
        persistLocalState()
        return destinationURL
    }

    func removeDownloadedPDF(for thesis: Thesis) {
        guard let url = localPDFURL(for: thesis) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            downloadedIDs.remove(thesis.id)
            persistLocalState()
        } catch {
            lastError = "No se ha podido eliminar la descarga: \(error.localizedDescription)"
        }
    }

    private var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TesisUCM", isDirectory: true)
    }

    private var catalogCacheDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Catalog", isDirectory: true)
    }

    private var pdfDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("PDFs", isDirectory: true)
    }

    private func safeFileName(for thesis: Thesis) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(thesis.id.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        })
    }

    private func loadLocalState() {
        guard let data = defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(LocalLibraryData.self, from: data) else {
            return
        }

        savedIDs = state.savedIDs
        notes = state.notes
        progress = state.progress
        bookmarks = state.bookmarks
        downloadedIDs = state.downloadedIDs
    }

    private func persistLocalState() {
        let state = LocalLibraryData(
            savedIDs: savedIDs,
            notes: notes,
            progress: progress,
            bookmarks: bookmarks,
            downloadedIDs: downloadedIDs
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
