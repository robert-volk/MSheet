import Foundation

enum MutopiaServiceError: LocalizedError {
    case badURL

    var errorDescription: String? { "Couldn't build a Mutopia search request." }
}

/// Scrapes Mutopia Project's search-results page — Mutopia doesn't publish
/// a JSON API, only this HTML table. Verified against the live page before
/// writing this: each result sits in its own
/// `<table class="table-bordered result-table">` block with a fixed row
/// layout (title, then "by Composer (dates)", then a details row, then a
/// downloads row with direct `.pdf` links). Every Mutopia file is already
/// cleared public domain or Creative Commons and served with a direct link
/// — no per-country copyright gate like IMSLP has — so `directDownloadURL`
/// on the returned `SearchResult` always points straight at the PDF.
///
/// Parsing is done block-by-block rather than with one regex over the whole
/// page, so a markup change breaks individual results instead of the whole
/// search.
enum MutopiaService {
    private static let session = URLSession.shared
    private static let blockMarker = "<table class=\"table-bordered result-table\">"

    static func search(_ query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: "https://www.mutopiaproject.org/cgibin/make-table.cgi") else {
            throw MutopiaServiceError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "searchingfor", value: trimmed),
            URLQueryItem(name: "Text", value: "1"),
        ]
        guard let url = components.url else { throw MutopiaServiceError.badURL }

        let (data, _) = try await session.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let blocks = html.components(separatedBy: blockMarker).dropFirst()
        return blocks.compactMap(parseResult)
    }

    private static func parseResult(fromBlock rawBlock: Substring) -> SearchResult? {
        let block = rawBlock.components(separatedBy: "</table>").first ?? String(rawBlock)
        let cells = cellContents(in: block)
        guard cells.count >= 2 else { return nil }

        let title = stripTags(cells[0])
        guard !title.isEmpty else { return nil }

        let composer = stripTags(cells[1])
            .replacingOccurrences(of: #"^by\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // Prefer US Letter, since that's the common paper size for this
        // app's audience; fall back to A4 if a piece only offers that.
        guard
            let pdfHref = firstHref(matching: #"[^"]+-let\.pdf"#, in: block)
                ?? firstHref(matching: #"[^"]+-a4\.pdf"#, in: block),
            let pdfURL = URL(string: pdfHref)
        else {
            return nil
        }

        let pageURL = firstHref(matching: #"piece-info\.cgi\?id=\d+"#, in: block)
            .flatMap { URL(string: $0, relativeTo: URL(string: "https://www.mutopiaproject.org/cgibin/")) }?
            .absoluteURL ?? pdfURL

        return SearchResult(
            title: title,
            composer: composer.isEmpty ? nil : composer,
            pageURL: pageURL,
            directDownloadURL: pdfURL,
            source: .mutopia
        )
    }

    private static func cellContents(in block: String) -> [String] {
        var cells: [String] = []
        var searchRange = block.startIndex..<block.endIndex
        while let openRange = block.range(of: "<td>", range: searchRange) {
            guard let closeRange = block.range(of: "</td>", range: openRange.upperBound..<block.endIndex) else { break }
            cells.append(String(block[openRange.upperBound..<closeRange.lowerBound]))
            searchRange = closeRange.upperBound..<block.endIndex
        }
        return cells
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstHref(matching pattern: String, in block: String) -> String? {
        guard let range = block.range(of: "href=\"(\(pattern))\"", options: .regularExpression) else {
            return nil
        }
        var match = String(block[range])
        match.removeFirst("href=\"".count)
        match.removeLast()
        return match
    }
}
