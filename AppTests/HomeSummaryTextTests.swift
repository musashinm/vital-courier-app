import Foundation
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite struct HomeSummaryTextTests {
    let now = date("2026-10-03T11:16:00Z")
    let english = StatusDateFormatter(localization: .english, timeZone: saoPaulo)

    func run(_ start: String, written: Int = 0, failed: Int = 0, errors: [String] = [], trigger: Trigger = .appOpen) -> RunRecord {
        RunRecord(startedAt: date(start), trigger: trigger.rawValue, readOutcome: ReadOutcome.read.rawValue, daysWritten: written, daysFailed: failed, daysPending: 0, errors: errors, id: 7)
    }

    @Test func summaryCopyMatchesTheDesign() {
        let wrote = run("2026-10-03T11:16:00Z", written: 3, trigger: .observerWake)
        let checked = run("2026-10-03T11:16:00Z")
        let failing = run("2026-10-03T11:16:00Z", failed: 2, errors: ["json steps 2026-10: x", "note 2026-10-01: y"])

        #expect(HomeSummary.daysUpdated(run: wrote).text(formatter: english, now: now) == HomeSummaryText(symbolName: "checkmark.circle.fill", title: "3 days updated", detail: "Today at 8:16 AM · Observer wake", errorText: nil, showsMoreErrorsNote: false, action: .runDetails))
        #expect(HomeSummary.daysUpdated(run: run("2026-10-03T11:16:00Z", written: 1)).text(formatter: english, now: now).title == "1 day updated")
        #expect(HomeSummary.upToDate(run: checked).text(formatter: english, now: now).detail == "Checked today at 8:16 AM · App open")
        #expect(HomeSummary.running(lastCompleted: date("2026-10-03T00:42:00Z")).text(formatter: english, now: now).detail == "Last completed yesterday at 9:42 PM.")
        #expect(HomeSummary.running(lastCompleted: nil).text(formatter: english, now: now).detail == nil)
        #expect(HomeSummary.writeFailure(run: failing).text(formatter: english, now: now) == HomeSummaryText(symbolName: "xmark.octagon.fill", title: "2 days failed", detail: nil, errorText: "json steps 2026-10: x", showsMoreErrorsNote: true, action: .runDetails))
        #expect(HomeSummary.writeFailure(run: run("2026-10-03T11:16:00Z", failed: 1)).text(formatter: english, now: now).title == "1 day failed")
        #expect(HomeSummary.folderLost(errorText: "gone").text(formatter: english, now: now) == HomeSummaryText(symbolName: "folder.badge.minus", title: "Folder lost, pick it again", detail: nil, errorText: "gone", showsMoreErrorsNote: false, action: .pickFolderAgain))
        #expect(HomeSummary.noFolder.text(formatter: english, now: now) == HomeSummaryText(symbolName: "folder.badge.questionmark", title: "Pick a folder", detail: "Health data can be read locally, but files need a destination.", errorText: nil, showsMoreErrorsNote: false, action: .pickFolder))
        #expect(HomeSummary.readOverdue.text(formatter: english, now: now) == HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Health data hasn’t been read in 24 hours", detail: "Unlock this iPhone and open Vital Courier. Saved files remain in place.", errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns))
        #expect(HomeSummary.dailyValuesOverdue.text(formatter: english, now: now) == HomeSummaryText(symbolName: "exclamationmark.arrow.triangle.2.circlepath", title: "Daily summaries haven’t refreshed in 24 hours", detail: "Unlock this iPhone and open Vital Courier to try again.", errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns))
        #expect(HomeSummary.awaitingReread.text(formatter: english, now: now) == HomeSummaryText(symbolName: "arrow.clockwise.circle", title: "Waiting to reread health data", detail: "Keep this iPhone unlocked and open Vital Courier. Your exported files remain in place.", errorText: nil, showsMoreErrorsNote: false, action: .none))
        #expect(HomeSummary.waitingForFirstExport.text(formatter: english, now: now) == HomeSummaryText(symbolName: "clock.badge.questionmark", title: "Waiting for the first export", detail: "Keep your iPhone unlocked while Vital Courier reads the four data types.", errorText: nil, showsMoreErrorsNote: false, action: .none))
        #expect(HomeSummary.running(lastCompleted: nil).text(formatter: english, now: now).title == "Checking for updates…")
    }

    @Test func protectionFailuresShowTheSavedError() {
        let failing = run("2026-10-03T10:00:00Z", failed: 1, errors: ["note 2026-10-01: x", "file protection: ProtectionFailed()"])
        #expect(HomeSummary.protectionFailure(run: failing).text(formatter: english, now: now) == HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Local data protection failed", detail: nil, errorText: "file protection: ProtectionFailed()", showsMoreErrorsNote: true, action: .runDetails))
        #expect(HomeSummary.protectionFailurePending(errorText: "ProtectionFailed()").text(formatter: english, now: now) == HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Local data protection failed", detail: "Saving it to History failed. It is saved the next time the app can write.", errorText: "file protection: ProtectionFailed()", showsMoreErrorsNote: false, action: .none))
    }

    @Test func recencyCopyMatchesTheDesign() {
        let today = day("2026-10-03")
        #expect(TypeRecency.updated(today).valueText(formatter: english, today: today, source: nil) == "Updated today")
        #expect(TypeRecency.updated(today).valueText(formatter: english, today: today, source: "Apple Watch") == "Updated today · Apple Watch")
        #expect(TypeRecency.updated(day("2026-09-24")).valueText(formatter: english, today: today, source: nil) == "Updated Sep 24")
        #expect(TypeRecency.silentForAWeek.valueText(formatter: english, today: today, source: "Apple Watch") == "No data received in 7 days")
        #expect(TypeRecency.noDataYet.valueText(formatter: english, today: today, source: nil) == "No data yet")
    }
}
