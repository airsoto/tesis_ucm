import Foundation

struct ThesisManifest: Decodable {
    let version: Int
    let total: Int
    let authors: Int
    let directors: Int
    let subjects: Int
    let minDefense: Int?
    let maxDefense: Int?
    let chunkSize: Int
    let chunks: Int
    let topSubjects: [ThesisSubjectCount]
    let sourceRepository: String?
    let sourcePath: String?
    let dataFormat: String?
    let summaryIndexShards: Int?
}

struct ThesisSubjectCount: Decodable, Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct Thesis: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let authors: [String]
    let directors: [String]
    let summary: String?
    let pubDate: String?
    let defenseDate: String?
    let subjectsUCM: [String]
    let subjectsUNESCO: [String]
    let pdf: URL?
    let link: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case legacyID = "_id"
        case title
        case authors
        case directors
        case summary
        case pubDate = "pub_date"
        case defenseDate = "defense_date"
        case subjectsUCM = "subjects_ucm"
        case subjectsUNESCO = "subjects_unesco"
        case pdf
        case link
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        title = try values.decode(String.self, forKey: .title)
        authors = (try? values.decode([String].self, forKey: .authors)) ?? []
        directors = (try? values.decode([String].self, forKey: .directors)) ?? []
        summary = try? values.decodeIfPresent(String.self, forKey: .summary)
        pubDate = Self.decodeFlexibleString(values, key: .pubDate)
        defenseDate = Self.decodeFlexibleString(values, key: .defenseDate)
        subjectsUCM = (try? values.decode([String].self, forKey: .subjectsUCM)) ?? []
        subjectsUNESCO = (try? values.decode([String].self, forKey: .subjectsUNESCO)) ?? []
        pdf = Self.decodeURL(values, key: .pdf)
        link = Self.decodeURL(values, key: .link)

        if let stringID = try? values.decode(String.self, forKey: .id) {
            id = stringID
        } else if let numericID = try? values.decode(Int.self, forKey: .legacyID) {
            id = String(numericID)
        } else if let stringLegacyID = try? values.decode(String.self, forKey: .legacyID) {
            id = stringLegacyID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.legacyID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "El registro no contiene _id.")
            )
        }
    }

    private static func decodeFlexibleString(
        _ values: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let string = try? values.decode(String.self, forKey: key) {
            return string
        }
        if let number = try? values.decode(Int.self, forKey: key) {
            return String(number)
        }
        return nil
    }

    private static func decodeURL(
        _ values: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> URL? {
        guard let raw = try? values.decode(String.self, forKey: key) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    var year: Int? {
        if let defenseDate, let year = Self.yearFromDate(defenseDate) {
            return year
        }
        if let pubDate {
            return Self.yearFromDate(pubDate)
        }
        return nil
    }

    private static func yearFromDate(_ value: String) -> Int? {
        let components = value.split(whereSeparator: { !$0.isNumber })
        guard let candidate = components.first(where: { $0.count == 4 }) else { return nil }
        return Int(candidate)
    }

    var authorsText: String {
        authors.isEmpty ? "Autoría no indicada" : authors.joined(separator: ", ")
    }

    var directorsText: String {
        directors.isEmpty ? "Dirección no indicada" : directors.joined(separator: ", ")
    }

    var abstract: String? { summary }
    var subjects: [String] { subjectsUCM }
    var pdfURL: URL? { pdf }
    var landingURL: URL? { link }
    var faculty: String? { nil }
    var language: String? { nil }
    var isPDFAvailable: Bool { pdf != nil }
    var hasPDF: Bool { pdf != nil }
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
