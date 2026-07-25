import Foundation

enum CPDLServiceError: LocalizedError {
    case badURL

    var errorDescription: String? { "Couldn't build a CPDL search request." }
}

/// Talks to CPDL's (ChoralWiki's) public MediaWiki search API — same
/// software family as IMSLP, so the same full-text `list=search` approach
/// applies, but CPDL's own conventions differ in two ways verified against
/// the live site before writing this:
///
/// - Page titles are `"Work Title (First Last)"` — composer already in
///   reading order, unlike IMSLP's `"(Last, First)"`, so no comma-flip.
/// - Page URLs are `/wiki/index.php?title=...` (query string), not
///   IMSLP's `/wiki/<Title>` path form.
///
/// CPDL is a 501(c)(3) nonprofit choral/vocal library — no account, no
/// watermark, no wait timer. Ungated works expose a direct
/// `/wiki/images/.../Something.pdf` link (confirmed by downloading one:
/// real `%PDF-` bytes, no redirect); this doesn't special-case a
/// disclaimer/gate path the way IMSLPService does because none was found
/// in testing, but `resolveDownloadURL` still only returns `nil` rather
/// than guessing if no direct link is present, so a gated work (if one
/// exists) falls back to "open on CPDL" like everywhere else in the app.
enum CPDLService {
    private static let session = URLSession.shared

    static func search(_ query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: "https://cpdl.org/wiki/api.php") else {
            throw CPDLServiceError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: trimmed),
            URLQueryItem(name: "srnamespace", value: "0"),
            URLQueryItem(name: "srlimit", value: "30"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw CPDLServiceError.badURL }

        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(QuerySearchResponse.self, from: data)

        return decoded.query.search.compactMap { hit in
            guard let pageURL = pageURL(forTitle: hit.title) else { return nil }
            let parsed = parseTitle(hit.title)
            return SearchResult(
                title: parsed.title,
                composer: parsed.composer,
                pageURL: pageURL,
                directDownloadURL: nil,
                source: .cpdl
            )
        }
    }

    /// CPDL's trailing `(...)` on a page title is already "First Last" —
    /// no reordering needed, unlike IMSLP's "Last, First" convention.
    private static func parseTitle(_ raw: String) -> (title: String, composer: String?) {
        guard let openParen = raw.lastIndex(of: "("), raw.hasSuffix(")") else {
            return (raw, nil)
        }
        let title = raw[..<openParen].trimmingCharacters(in: .whitespaces)
        let insideStart = raw.index(after: openParen)
        let insideEnd = raw.index(before: raw.endIndex)
        guard insideStart < insideEnd else { return (title, nil) }
        let composer = raw[insideStart..<insideEnd].trimmingCharacters(in: .whitespaces)
        return (title, composer.isEmpty ? nil : composer)
    }

    private static func pageURL(forTitle title: String) -> URL? {
        let underscored = title.replacingOccurrences(of: " ", with: "_")
        guard var components = URLComponents(string: "https://cpdl.org/wiki/index.php") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "title", value: underscored)]
        return components.url
    }

    static func resolveDownloadURL(fromWorkPage pageURL: URL) async throws -> URL? {
        let (data, _) = try await session.data(from: pageURL)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        guard let range = html.range(
            of: #"href="(/wiki/images/[^"?]+\.pdf)""#,
            options: .regularExpression
        ) else {
            return nil
        }

        var match = String(html[range])
        match.removeFirst("href=\"".count)
        match.removeLast()

        return URL(string: match, relativeTo: URL(string: "https://cpdl.org"))?.absoluteURL
    }
}

private struct QuerySearchResponse: Decodable {
    struct Body: Decodable {
        let search: [Hit]
    }
    struct Hit: Decodable {
        let title: String
    }
    let query: Body
}
