import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct AppSettingsTests {
    @Test func valuesRoundTripAndNilClears() {
        let storage = InMemoryStorage()
        let settings = AppSettings(storage: storage)
        #expect(settings.folderBookmark == nil)
        #expect(settings.awaitingRereadAfterClear == false)
        #expect(settings.setupCompletedAt == nil)

        settings.folderBookmark = Data([1, 2])
        settings.folderDisplayPath = "iCloud Drive/Health"
        settings.folderLostError = "gone"
        settings.setupCompletedAt = date("2026-10-03T11:16:00Z")
        settings.awaitingRereadAfterClear = true

        let reread = AppSettings(storage: storage)
        #expect(reread.folderBookmark == Data([1, 2]))
        #expect(reread.folderDisplayPath == "iCloud Drive/Health")
        #expect(reread.folderLostError == "gone")
        #expect(reread.setupCompletedAt == date("2026-10-03T11:16:00Z"))
        #expect(reread.awaitingRereadAfterClear == true)

        reread.folderLostError = nil
        reread.awaitingRereadAfterClear = false
        #expect(settings.folderLostError == nil)
        #expect(settings.awaitingRereadAfterClear == false)
    }
}
