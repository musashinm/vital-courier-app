import Foundation
import VitalCourierCore

/// The folder path from `FolderDisplayPath`, with its root ("On My iPhone") in the person's language. The folder names after it are their own and stay as written.
enum FolderPathText {
    static func localized(_ displayPath: String, in localization: AppLocalization = .system) -> String {
        let segments = displayPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.first == FolderDisplayPath.onMyIPhone else { return displayPath }
        return ([localization.string("On My iPhone")] + segments.dropFirst()).joined(separator: "/")
    }
}
