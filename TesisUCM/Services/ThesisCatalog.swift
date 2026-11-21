import Foundation
import CryptoKit

struct ThesisCatalog {
    let manifest: ThesisManifest
    let theses: [Thesis]

    static func loadLocal(bundled: URL?, cache: URL) async -> Self? {
        let bundledManifest = bundled.flatMap { readManifest(in: $0, name: "catalog.json") }
        let cachedManifest = readManifest(in: cache, name: "manifest.json")
        let bundledChunks = bundled?.appendingPathComponent("chunks")

        if let bundledManifest, let bundledChunks,
           bundledManifest.version >= (cachedManifest?.version ?? 0),
           let catalog = try? load(bundledManifest, chunks: bundledChunks) {
            return catalog
        }
        if let cachedManifest {
            let versioned = versionDirectory(in: cache, version: cachedManifest.version)
            let chunks = FileManager.default.fileExists(atPath: versioned.path) ? versioned : cache
            if let catalog = try? load(cachedManifest, chunks: chunks) {
                return catalog
            }
        }
        guard let bundledManifest, let bundledChunks else { return nil }
        return try? load(bundledManifest, chunks: bundledChunks)
    }

    static func downloadUpdate(from remote: URL, bundled: URL?, cache: URL, after version: Int?) async throws -> Self? {
        let manifestURL = remote.appendingPathComponent("catalog.json")
        let manifestData = try await download(manifestURL)
        let manifest = try decodeManifest(manifestData)
        guard manifest.version > (version ?? 0) else { return nil }

        let files = FileManager.default
        let staging = cache.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }

        let remoteChunks = remote.appendingPathComponent("chunks", isDirectory: true)
        let previousManifest = readManifest(in: cache, name: "manifest.json")
        let cachedChunks = previousManifest.map { versionDirectory(in: cache, version: $0.version) }
        let bundledChunks = bundled?.appendingPathComponent("chunks", isDirectory: true)
        let reusableDirectories = [cachedChunks, bundledChunks].compactMap { $0 }
        var chunks = Array(repeating: [Thesis](), count: manifest.chunks)
        try await withThrowingTaskGroup(of: (Int, [Thesis]).self) { group in
            for index in 0..<manifest.chunks {
                if index >= 5, let (finished, records) = try await group.next() {
                    chunks[finished] = records
                }
                group.addTask {
                    let name = chunkName(index)
                    let hash = manifest.chunkSHA256?[name]
                    let data = try await loadChunk(name, hash: hash, local: reusableDirectories, remote: remoteChunks)
                    let records = try JSONDecoder().decode([Thesis].self, from: data)
                    try data.write(to: staging.appendingPathComponent(name), options: .atomic)
                    return (index, records)
                }
            }
            for try await (index, records) in group {
                chunks[index] = records
            }
        }

        let catalog = try validated(manifest, records: chunks.flatMap { $0 })
        let verifiedManifest = try await download(manifestURL)
        guard verifiedManifest == manifestData else {
            throw CatalogError.changedDuringDownload
        }
        try Task.checkCancellation()

        let destination = versionDirectory(in: cache, version: manifest.version)
        if files.fileExists(atPath: destination.path) {
            try files.removeItem(at: destination)
        }
        try files.moveItem(at: staging, to: destination)
        try manifestData.write(to: cache.appendingPathComponent("manifest.json"), options: .atomic)
        if let previousManifest, previousManifest.version != manifest.version {
            try? files.removeItem(at: versionDirectory(in: cache, version: previousManifest.version))
        }
        return catalog
    }

    private static func load(_ manifest: ThesisManifest, chunks: URL) throws -> Self {
        let decoder = JSONDecoder()
        var theses: [Thesis] = []
        for index in 0..<manifest.chunks {
            let data = try Data(contentsOf: chunks.appendingPathComponent(chunkName(index)))
            theses.append(contentsOf: try decoder.decode([Thesis].self, from: data))
        }
        return try validated(manifest, records: theses)
    }

    private static func validated(_ manifest: ThesisManifest, records: [Thesis]) throws -> Self {
        guard records.count == manifest.total, Set(records.map(\.id)).count == manifest.total else {
            throw CatalogError.invalidRecords
        }
        let ordered = records.map { (thesis: $0, year: $0.year ?? 0) }.sorted {
            if $0.year != $1.year {
                return $0.year > $1.year
            }
            return $0.thesis.title.localizedCaseInsensitiveCompare($1.thesis.title) == .orderedAscending
        }
        return Self(manifest: manifest, theses: ordered.map(\.thesis))
    }

    private static func readManifest(in directory: URL, name: String) -> ThesisManifest? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
            return nil
        }
        return try? decodeManifest(data)
    }

    private static func decodeManifest(_ data: Data) throws -> ThesisManifest {
        let manifest = try JSONDecoder().decode(ThesisManifest.self, from: data)
        guard manifest.version > 0, manifest.total > 0, manifest.chunkSize > 0,
              manifest.chunks == (manifest.total - 1) / manifest.chunkSize + 1 else {
            throw CatalogError.invalidManifest
        }
        return manifest
    }

    private static func versionDirectory(in cache: URL, version: Int) -> URL {
        cache.appendingPathComponent("v\(version)", isDirectory: true)
    }

    private static func chunkName(_ index: Int) -> String {
        String(format: "chunk_%04d.json", index)
    }

    private static func loadChunk(_ name: String, hash: String?, local: [URL], remote: URL) async throws -> Data {
        if let hash {
            for directory in local {
                if let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                   sha256(data) == hash {
                    return data
                }
            }
        }
        let data = try await download(remote.appendingPathComponent(name))
        if let hash, sha256(data) != hash { throw CatalogError.invalidChunk }
        return data
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func download(_ url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private enum CatalogError: LocalizedError {
    case invalidManifest
    case invalidRecords
    case invalidChunk
    case changedDuringDownload

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "El manifiesto del catálogo no es válido."
        case .invalidRecords:
            return "El catálogo está incompleto o contiene identificadores duplicados."
        case .invalidChunk:
            return "No se ha podido verificar un fragmento del catálogo."
        case .changedDuringDownload:
            return "Se publicó otra versión durante la descarga. Vuelve a intentarlo."
        }
    }
}
