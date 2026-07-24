import Foundation
import SwiftData

/// A score whose PDF has been downloaded into the app's own sandbox.
/// `fileName` is relative to `FileManager.scoresDirectory` — never an
/// absolute path, since the app's container path can change between runs.
@Model
final class SavedScore {
    var title: String
    var composer: String?
    var sourceURL: URL
    var fileName: String
    var savedAt: Date

    init(title: String, composer: String?, sourceURL: URL, fileName: String, savedAt: Date = .now) {
        self.title = title
        self.composer = composer
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.savedAt = savedAt
    }

    var fileURL: URL {
        FileManager.scoresDirectory.appendingPathComponent(fileName)
    }
}

extension FileManager {
    /// Local, on-device home for downloaded PDFs — created lazily, never synced.
    static var scoresDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scores", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
