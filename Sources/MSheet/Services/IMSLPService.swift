import Foundation

enum IMSLPServiceError: LocalizedError {
    case badURL
    case noResponse

    var errorDescription: String? {
        switch self {
        case .badURL: return "Couldn't build a search request."
        case .noResponse: return "IMSLP didn't respond. Check your connection and try again."
        }
    }
}

/// Talks to IMSLP's public MediaWiki search API — no API key, no account,
/// no rate-limit key required. Uses full-text search (`list=search`) rather
/// than `opensearch`, because `opensearch` only prefix-matches the start of
/// a page title, and IMSLP titles are formatted `"Work Title (Last, First)"`
/// — composer at the end — so a perfectly normal query like "debussy clair
/// de lune" would never match anything under prefix search. Full-text
/// search also degrades gracefully to zero hits instead of a short/omitted
/// JSON shape, which `opensearch` does on no-match queries and which a
/// naive positional decoder chokes on.
///
/// It only returns matching page titles (not composer/instrumentation as
/// structured data), so `resolveDownloadURL` separately loads a work's real
/// page to find its files, exactly as a person browsing imslp.org would see
/// them.
enum IMSLPService {
    private static let session = URLSession.shared

    static func search(_ query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: "https://imslp.org/api.php") else {
            throw IMSLPServiceError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: trimmed),
            URLQueryItem(name: "srnamespace", value: "0"),
            URLQueryItem(name: "srlimit", value: "30"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw IMSLPServiceError.badURL }

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
                source: .imslp
            )
        }
    }

    /// IMSLP names composers "Last, First" inside a trailing `(...)` on the
    /// page title; flip it to "First Last" for display, same as a normal
    /// byline reads.
    private static func parseTitle(_ raw: String) -> (title: String, composer: String?) {
        guard let openParen = raw.lastIndex(of: "("), raw.hasSuffix(")") else {
            return (raw, nil)
        }
        let title = raw[..<openParen].trimmingCharacters(in: .whitespaces)
        let insideStart = raw.index(after: openParen)
        let insideEnd = raw.index(before: raw.endIndex)
        guard insideStart < insideEnd else { return (title, nil) }
        let inside = raw[insideStart..<insideEnd]

        let parts = inside.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count == 2 {
            return (title, "\(parts[1]) \(parts[0])")
        }
        return (title, String(inside))
    }

    /// IMSLP page URLs are the title with spaces turned into underscores,
    /// percent-encoded into a `/wiki/` path — the same convention every
    /// MediaWiki site uses.
    private static func pageURL(forTitle title: String) -> URL? {
        let underscored = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = underscored.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://imslp.org/wiki/\(encoded)")
    }

    /// Looks for a direct, page-relative PDF link on a work's IMSLP page
    /// (`/images/.../Something.pdf`). IMSLP serves files this way once a
    /// score is unrestricted; works still under copyright in some countries
    /// instead show a link through `Special:IMSLPDisclaimerAccept`, which
    /// requires the person to read and accept a per-country notice — this
    /// deliberately does NOT try to script past that gate, so it returns
    /// `nil` and the caller should send the user to the real page instead.
    static func resolveDownloadURL(fromWorkPage pageURL: URL) async throws -> URL? {
        let (data, _) = try await session.data(from: pageURL)
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        guard let range = html.range(
            of: #"href="(/images/[^"?]+\.pdf)""#,
            options: .regularExpression
        ) else {
            return nil
        }

        var match = String(html[range])
        match.removeFirst("href=\"".count)
        match.removeLast()

        return URL(string: match, relativeTo: URL(string: "https://imslp.org"))?.absoluteURL
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
