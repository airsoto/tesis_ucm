import Foundation

extension Thesis {
    var citationLink: URL? { landingURL ?? pdfURL }

    var apaCitation: String {
        let names = authors.map { name in
            let components = name.split(separator: ",", maxSplits: 1)
            guard components.count == 2 else { return name }
            let initials = components[1].split(whereSeparator: \.isWhitespace).compactMap(\.first)
                .map { "\($0)." }.joined(separator: " ")
            return "\(components[0]), \(initials)"
        }
        let author: String
        if names.count > 1, let last = names.last {
            author = names.dropLast().joined(separator: ", ") + (names.count == 2 ? " & " : ", & ") + last
        } else {
            author = names.first ?? ""
        }
        let date = year.map(String.init) ?? "s. f."
        let institution = "[Tesis doctoral, Universidad Complutense de Madrid]. Docta Complutense."
        let authorPart = author.isEmpty ? title + ". " : author + (author.hasSuffix(".") ? " " : ". ")
        let titlePart = author.isEmpty ? "" : title + " "
        return "\(authorPart)(\(date)). \(titlePart)\(institution)" +
            (citationLink.map { " " + $0.absoluteString } ?? "")
    }

    var bibTeXCitation: String {
        let key = "ucm" + id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        var fields = [
            "title = {\(Self.texEscape(title))}",
            "school = {Universidad Complutense de Madrid}",
            "type = {Tesis doctoral}"
        ]
        if !authors.isEmpty {
            let names = authors.map(Self.texEscape).joined(separator: " and ")
            fields.append("author = {\(names)}")
        }
        if let year { fields.append("year = {\(year)}") }
        if let url = citationLink { fields.append("url = {\(url.absoluteString)}") }
        return "@phdthesis{\(key),\n  \(fields.joined(separator: ",\n  "))\n}"
    }

    private static func texEscape(_ string: String) -> String {
        string.map { character in
            switch character {
            case "\\": "\\textbackslash{}"
            case "{", "}", "#", "%", "&", "_", "$": "\\\(character)"
            case "~": "\\textasciitilde{}"
            case "^": "\\textasciicircum{}"
            default: String(character)
            }
        }.joined()
    }
}
