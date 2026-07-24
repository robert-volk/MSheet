import Foundation

enum ScoreSource: String, Hashable {
    case imslp = "IMSLP"
    case mutopia = "Mutopia"
}

/// One match from a search, already split into title/composer by whichever
/// service found it — IMSLP and Mutopia format that information completely
/// differently on their own pages, so each service does its own parsing
/// before handing back a `SearchResult`.
struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let composer: String?
    /// The work's normal, human-readable page — what "View on IMSLP" /
    /// "View on Mutopia" opens.
    let pageURL: URL
    /// When a service already knows the exact PDF link (Mutopia hands this
    /// out directly in its search results), download skips IMSLP's
    /// page-scraping step entirely and uses this instead.
    let directDownloadURL: URL?
    let source: ScoreSource
}
