import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var theses: [Thesis] = []
    @Published private(set) var catalogManifest: ThesisManifest?
    @Published private(set) var isRefreshing = false
    @Published private(set) var downloadedChunkCount = 0
    @Published private(set) var lastCatalogUpdate: String?
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
        loadCachedCatalog()
    }

    var savedTheses: [Thesis] {
        theses
            .filter { savedIDs.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func refreshCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        downloadedChunkCount = 0
        defer { isRefreshing = false }

        do {
            let manifestURL = remoteResourcesURL.appendingPathComponent("catalog.json")
            let manifestData = try await Self.downloadData(from: manifestURL)
            let manifest = try JSONDecoder().decode(ThesisManifest.self, from: manifestData)

            let sameVersion = catalogManifest?.version == manifest.version
            let cacheIsComplete = cachedChunkCount(for: manifest) == manifest.chunks

            if sameVersion && cacheIsComplete {
                let cached = try loadCachedChunks(for: manifest)
                guard cached.count == manifest.total else {
                    throw CatalogError.incompleteDatabase(expected: manifest.total, actual: cached.count)
                }
                theses = cached
                downloadedChunkCount = manifest.chunks
                catalogManifest = manifest
                lastCatalogUpdate = "Versión \(manifest.version)"
                lastError = nil
                return
            }

            try FileManager.default.createDirectory(
                at: catalogCacheDirectory,
                withIntermediateDirectories: true
            )

            let loadedChunks = try await downloadChunks(
                manifest: manifest,
                reuseCache: sameVersion
            )
            let records = loadedChunks.flatMap { $0 }

            guard records.count == manifest.total else {
                throw CatalogError.incompleteDatabase(expected: manifest.total, actual: records.count)
            }

            try manifestData.write(
                to: catalogCacheDirectory.appendingPathComponent("manifest.json"),
                options: .atomic
            )

            theses = records
            catalogManifest = manifest
            lastCatalogUpdate = "Versión \(manifest.version)"
            lastError = nil
        } catch {
            lastError = "No se ha podido completar la actualización de la base de datos: \(error.localizedDescription)"
            if theses.isEmpty {
                loadCachedCatalog()
            }
        }
    }

    private func downloadChunks(
        manifest: ThesisManifest,
        reuseCache: Bool
    ) async throws -> [[Thesis]] {
        let count = manifest.chunks
        guard count > 0 else { return [] }

        var orderedChunks = Array<[Thesis]?>(repeating: nil, count: count)
        let concurrency = min(5, count)
        var nextIndex = concurrency

        try await withThrowingTaskGroup(of: (Int, [Thesis]).self) { group in
            for index in 0..<concurrency {
                group.addTask {
                    let records = try await Self.loadChunk(
                        index: index,
                        resourcesURL: self.remoteResourcesURL,
                        cacheDirectory: self.catalogCacheDirectory,
                        reuseCache: reuseCache
                    )
                    return (index, records)
                }
            }

            while let result = try await group.next() {
                orderedChunks[result.0] = result.1
                downloadedChunkCount += 1

                if nextIndex < count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        let records = try await Self.loadChunk(
                            index: index,
                            resourcesURL: self.remoteResourcesURL,
                            cacheDirectory: self.catalogCacheDirectory,
                            reuseCache: reuseCache
                        )
                        return (index, records)
                    }
                }
            }
        }

        return orderedChunks.compactMap { $0 }
    }

    private nonisolated static func loadChunk(
        index: Int,
        resourcesURL: URL,
        cacheDirectory: URL,
        reuseCache: Bool
    ) async throws -> [Thesis] {
        let fileName = String(format: "chunk_%04d.json", index)
        let cacheURL = cacheDirectory.appendingPathComponent(fileName)
        let data: Data

        if reuseCache, FileManager.default.fileExists(atPath: cacheURL.path) {
            data = try Data(contentsOf: cacheURL)
        } else {
            let remoteURL = resourcesURL
                .appendingPathComponent("chunks", isDirectory: true)
                .appendingPathComponent(fileName)

            do {
                let downloaded = try await downloadData(from: remoteURL)
                try FileManager.default.createDirectory(
                    at: cacheDirectory,
                    withIntermediateDirectories: true
                )
                try downloaded.write(to: cacheURL, options: .atomic)
                data = downloaded
            } catch {
                if reuseCache, FileManager.default.fileExists(atPath: cacheURL.path) {
                    data = try Data(contentsOf: cacheURL)
                } else {
                    throw error
                }
            }
        }

        return try JSONDecoder().decode([Thesis].self, from: data)
    }

    private nonisolated static func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func cachedChunkCount(for manifest: ThesisManifest) -> Int {
        (0..<manifest.chunks).filter { index in
            let fileName = String(format: "chunk_%04d.json", index)
            return FileManager.default.fileExists(
                atPath: catalogCacheDirectory.appendingPathComponent(fileName).path
            )
        }.count
    }

    private func loadCachedChunks(for manifest: ThesisManifest) throws -> [Thesis] {
        var records: [Thesis] = []
        for index in 0..<manifest.chunks {
            let fileName = String(format: "chunk_%04d.json", index)
            let url = catalogCacheDirectory.appendingPathComponent(fileName)
            let data = try Data(contentsOf: url)
            records.append(contentsOf: try JSONDecoder().decode([Thesis].self, from: data))
        }
        return records
    }

    private func loadCachedCatalog() {
        let manifestURL = catalogCacheDirectory.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ThesisManifest.self, from: manifestData) else {
            return
        }

        do {
            let cached = try loadCachedChunks(for: manifest)
            catalogManifest = manifest
            downloadedChunkCount = manifest.chunks
            lastCatalogUpdate = "Versión \(manifest.version)"
            if cached.count == manifest.total {
                theses = cached
            } else {
                lastError = "La copia local del catálogo está incompleta."
            }
        } catch {
            lastError = "No se ha podido leer la copia local del catálogo."
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

private enum CatalogError: LocalizedError {
    case incompleteDatabase(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .incompleteDatabase(expected, actual):
            return "Se esperaban \(expected) tesis y se han recibido \(actual)."
        }
    }
}
