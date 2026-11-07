import Testing

@testable import VitalCourierCore

@Suite struct ExportSchemaTests {
  @Test func exportSchemaVersionIsOne() {
    #expect(ExportSchema.version == 1)
  }
}
