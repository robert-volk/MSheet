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

/// Talks to IMSLP's public MediaWiki `opensearch` endpoint — no API key,
/// no account, no rate-limit key required. It only returns matching page
/// titles and links (not composer/instrumentation as structured data), so
/// `resolveDownloadURL` separately loads a work's real page to find its
/// files, exactly as a person browsing imslp.org would see them.
enum IMSLPService {
    private static let session = URLSession.shared

    static func search(_ query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: "https://imslp.org/api.php") else {
            throw IMSLPServiceError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: trimmed),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw IMSLPServiceError.badURL }

        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(OpenSearchResponse.self, from: data)

        return zip(decoded.titles, decoded.urls).compactMap { title, urlString in
            guard let pageURL = URL(string: urlString) else { return nil }
            return SearchResult(rawTitle: title, pageURL: pageURL)
        }
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

/// `opensearch` responds with a fixed-shape, unkeyed array:
/// `[query, [titles], [descriptions], [urls]]`. Decoding it positionally
/// avoids writing a full model for what MediaWiki treats as a tuple.
private struct OpenSearchResponse: Decodable {
    let titles: [String]
    let urls: [String]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try container.decode(String.self)              // echoed query
        titles = try container.decode([String].self)
        _ = try container.decode([String].self)             // descriptions (unused)
        urls = try container.decode([String].self)
    }
}
