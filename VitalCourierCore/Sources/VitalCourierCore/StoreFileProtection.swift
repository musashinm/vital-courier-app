import Foundation

/// File protection for the store directory and every file inside it. GRDB's `DatabaseQueue` uses a rollback journal, so a `-journal` file appears and disappears around each write and SQLite can leave temp files. A file created in the directory normally inherits its class (Task 3A, Why), but the scan below does not rely on that: it sets the class on every child that exists when it runs, which covers the files that persist and anything that did not inherit it. It cannot reach a journal that is already gone.
enum StoreFileProtection {
  /// Calls `setProtection` for `directory`, then for each file in it, sorted by name. Stops at the first error.
  static func apply(to directory: URL, fileManager: FileManager = .default, setProtection: (URL) throws -> Void) throws
  {
    try setProtection(directory)
    for name in try fileManager.contentsOfDirectory(atPath: directory.path).sorted() {
      try setProtection(directory.appendingPathComponent(name))
    }
  }

  /// `completeUntilFirstUserAuthentication`: readable after the first unlock, so runs while the phone is locked still work. A no-op on macOS, where the attribute does not exist (the package tests run there).
  static func setCompleteUntilFirstUserAuthentication(_ url: URL) throws {
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path
      )
    #endif
  }
}
