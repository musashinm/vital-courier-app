/// A kind of file the app can write.
public enum ExportFormat: String, CaseIterable, Sendable {
  case json
  case markdown
  case csv

  /// What new and existing installs export (Format setting, spec).
  public static let defaultSelection: Set<ExportFormat> = [.json, .markdown]

  /// The formats a run has a writer for. A stored format outside this set writes nothing.
  static let writable: Set<ExportFormat> = [.json, .markdown, .csv]
}
