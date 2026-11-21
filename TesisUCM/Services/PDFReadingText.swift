import Foundation
import PDFKit

struct PDFReadingPage: Sendable {
    let number: Int
    let paragraphs: [String]
}

struct PDFSearchResult: Identifiable, Sendable {
    let page: Int
    let excerpt: String
    var id: Int { page }
}

actor PDFReadingText {
    private let url: URL
    private var document: PDFDocument?
    private var recentPages: [PDFReadingPage] = []

    init(url: URL) {
        self.url = url
    }

    func page(_ number: Int) -> PDFReadingPage {
        if let index = recentPages.firstIndex(where: { $0.number == number }) {
            let cached = recentPages.remove(at: index)
            recentPages.append(cached)
            return cached
        }
        let raw = openDocument()?.page(at: number - 1)?.string ?? ""
        var paragraphs: [String] = []
        var lines: [String] = []
        var length = 0

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || length >= 650 {
                if !lines.isEmpty { paragraphs.append(lines.joined(separator: " ")) }
                lines.removeAll(keepingCapacity: true)
                length = 0
            }
            if !trimmed.isEmpty {
                lines.append(trimmed)
                length += trimmed.count
            }
        }
        if !lines.isEmpty { paragraphs.append(lines.joined(separator: " ")) }

        let page = PDFReadingPage(number: number, paragraphs: paragraphs)
        recentPages.append(page)
        if recentPages.count > 8 { recentPages.removeFirst() }
        return page
    }

    func search(_ query: String) async throws -> [PDFSearchResult] {
        let words = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty, let document = openDocument() else { return [] }
        var results: [PDFSearchResult] = []

        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            if index.isMultiple(of: 8) { await Task.yield() }
            guard let raw = document.page(at: index)?.string else { continue }
            let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard let match = text.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let start = text.index(match.lowerBound, offsetBy: -44, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(match.upperBound, offsetBy: 90, limitedBy: text.endIndex) ?? text.endIndex
            let prefix = start == text.startIndex ? "" : "…"
            let suffix = end == text.endIndex ? "" : "…"
            results.append(PDFSearchResult(page: index + 1, excerpt: prefix + String(text[start..<end]) + suffix))
        }
        return results
    }

    private func openDocument() -> PDFDocument? {
        if let document { return document }
        let opened = PDFDocument(url: url)
        document = opened
        return opened
    }
}
