import Foundation
import Testing

@testable import VitalCourier

@Suite struct FolderPathTextTests {
  @Test func theRootIsShownInThePersonsLanguage() {
    #expect(FolderPathText.localized("On My iPhone", in: .portuguese) == "No Meu iPhone")
    #expect(FolderPathText.localized("On My iPhone/Health/Daily", in: .portuguese) == "No Meu iPhone/Health/Daily")
    #expect(FolderPathText.localized("On My iPhone/Exports", in: .english) == "On My iPhone/Exports")
  }

  @Test func otherPathsStayAsWritten() {
    #expect(FolderPathText.localized("iCloud Drive/Notes", in: .portuguese) == "iCloud Drive/Notes")
    #expect(FolderPathText.localized("", in: .portuguese) == "")
  }

  @Test func onlyTheFirstSegmentIsARoot() {
    #expect(FolderPathText.localized("Obsidian/On My iPhone", in: .portuguese) == "Obsidian/On My iPhone")
  }
}
