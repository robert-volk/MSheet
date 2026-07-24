import Foundation

/// One work-page match from IMSLP's search, plus the composer/title split
/// out of IMSLP's page-title convention: `"Work Title (Last, First)"`.
struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let rawTitle: String
    let pageURL: URL

    var workTitle: String { Self.parse(rawTitle).workTitle }
    var composer: String? { Self.parse(rawTitle).composer }

    private static func parse(_ raw: String) -> (workTitle: String, composer: String?) {
        guard let openParen = raw.lastIndex(of: "("), raw.hasSuffix(")") else {
            return (raw, nil)
        }
        let title = raw[..<openParen].trimmingCharacters(in: .whitespaces)
        let insideStart = raw.index(after: openParen)
        let insideEnd = raw.index(before: raw.endIndex)
        guard insideStart < insideEnd else { return (title, nil) }
        let inside = raw[insideStart..<insideEnd]

        // IMSLP names composers "Last, First" inside the parens; flip it to
        // "First Last" for display, same as a normal byline reads.
        let parts = inside.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count == 2 {
            return (title, "\(parts[1]) \(parts[0])")
        }
        return (title, String(inside))
    }
}
