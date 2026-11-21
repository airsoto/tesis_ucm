import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var theses: [Thesis] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastCatalogUpdate: String?
    @Published var lastError: String?

    @Published private(set) var savedIDs: Set<String> = []
    @Published private(set) var notes: [String: String] = [:]
    @Published private(set) var progress: [String: ReadingProgress] = [:]
    @Published private(set) var bookmarks: [String: Set<Int>] = [:]
    @Published private(set) var downloadedIDs: Set<String> = []

    private let defaults = UserDefaults.standard
    private let storageKey = "tesisUCM.localLibrary.v1"

    private let remoteCatalogURL = URL(
        string: "https://raw.githubusercontent.com/airsoto/tesis_ucm/main/TesisUCM/Resources/catalog.json"
    )!

    init() {
        loadLocalState()
        loadBundledCatalog()
    }

    var savedTheses: [Thesis] {
        theses
            .filter { savedIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func refreshCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteCatalogURL)
            if let response = response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }

            let catalog = try JSONDecoder().decode(ThesisCatalog.self, from: data)
            theses = catalog.theses
            lastCatalogUpdate = catalog.updatedAt
            lastError = nil
        } catch {
            lastError = "No se ha podido actualizar el catálogo. Se conserva la última versión disponible."
        }
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

    func updateProgress(for thesisID: String, page: Int, pageCount: Int) {
        guard pageCount > 0 else { return }
        let safePage = min(max(page, 1), pageCount)
        if progress[thesisID]?.page == safePage,
           progress[thesisID]?.pageCount == pageCount {
            return
        }

        progress[thesisID] = ReadingProgress(
            page: safePage,
            pageCount: pageCount,
            updatedAt: Date()
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

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)

        downloadedIDs.insert(thesis.id)
        persistLocalState()
        return destinationURL
    }

    func removeDownloadedPDF(for thesis: Thesis) {
        guard let url = localPDFURL(for: thesis) else { return }
        try? FileManager.default.removeItem(at: url)
        downloadedIDs.remove(thesis.id)
        persistLocalState()
    }

    private var pdfDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TesisUCM/PDFs", isDirectory: true)
    }

    private func safeFileName(for thesis: Thesis) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(thesis.id.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        })
    }

    private func loadBundledCatalog() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ThesisCatalog.self, from: data) else {
            return
        }
        theses = catalog.theses
        lastCatalogUpdate = catalog.updatedAt
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
