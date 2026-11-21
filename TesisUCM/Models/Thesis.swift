import Foundation

struct ThesisCatalog: Decodable {
    let updatedAt: String?
    let theses: [Thesis]

    enum CodingKeys: String, CodingKey {
        case updatedAt
        case theses
    }
}

struct Thesis: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let authors: [String]
    let directors: [String]
    let year: Int?
    let faculty: String?
    let subjects: [String]
    let language: String?
    let abstract: String?
    let pdfURL: URL?
    let landingURL: URL?
    let isPDFAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case authors
        case directors
        case year
        case faculty
        case subjects
        case language
        case abstract
        case pdfURL
        case landingURL
        case isPDFAvailable
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        authors = (try? values.decode([String].self, forKey: .authors)) ?? []
        directors = (try? values.decode([String].self, forKey: .directors)) ?? []
        year = try? values.decodeIfPresent(Int.self, forKey: .year)
        faculty = try? values.decodeIfPresent(String.self, forKey: .faculty)
        subjects = (try? values.decode([String].self, forKey: .subjects)) ?? []
        language = try? values.decodeIfPresent(String.self, forKey: .language)
        abstract = try? values.decodeIfPresent(String.self, forKey: .abstract)
        pdfURL = try? values.decodeIfPresent(URL.self, forKey: .pdfURL)
        landingURL = try? values.decodeIfPresent(URL.self, forKey: .landingURL)
        isPDFAvailable = try? values.decodeIfPresent(Bool.self, forKey: .isPDFAvailable)
    }

    var authorsText: String {
        authors.isEmpty ? "Autoría no indicada" : authors.joined(separator: ", ")
    }

    var directorsText: String {
        directors.isEmpty ? "Dirección no indicada" : directors.joined(separator: ", ")
    }

    var hasPDF: Bool {
        pdfURL != nil && (isPDFAvailable ?? true)
    }
}

struct ReadingProgress: Codable, Equatable {
    var page: Int
    var pageCount: Int
    var updatedAt: Date

    var percentage: Int {
        guard pageCount > 0 else { return 0 }
        return min(100, max(0, Int((Double(page) / Double(pageCount)) * 100)))
    }
}

struct LocalLibraryData: Codable {
    var savedIDs: Set<String> = []
    var notes: [String: String] = [:]
    var progress: [String: ReadingProgress] = [:]
    var bookmarks: [String: Set<Int>] = [:]
    var downloadedIDs: Set<String> = []
}
