import HealthKit
import Testing
@testable import VitalCourier

private struct ProbeError: Error {}

/// Records what the entry asked for, in order, and can hold the Health sheet open.
@MainActor
private final class ForegroundEntryProbe {
    var events: [String] = []
    var status: Result<HKAuthorizationRequestStatus, any Error> = .success(.unnecessary)
    var holdsSheet = false
    var recordsAskedTypes = false
    var requestFails = false
    private var sheetContinuation: CheckedContinuation<Void, Never>?

    func makeEntry() -> ForegroundEntry {
        let entry = ForegroundEntry(
            authorizationRequestStatus: { [unowned self] in
                events.append("status")
                return try status.get()
            },
            requestAuthorization: { [unowned self] in
                events.append("request")
                if holdsSheet { await withCheckedContinuation { sheetContinuation = $0 } }
                if requestFails { throw ProbeError() }
            },
            recordError: { [unowned self] in events.append("error \($0)") }
        )
        entry.requestAppOpenRun = { [unowned self] in events.append("run") }
        entry.typesWereAsked = { [unowned self] in
            if recordsAskedTypes { events.append("asked") }
        }
        return entry
    }

    func answerSheet() {
        sheetContinuation?.resume()
        sheetContinuation = nil
    }
}

@Suite @MainActor struct ForegroundEntryTests {
    @Test func theRunIsRequestedOnlyAfterTheSheetIsAnswered() async {
        let probe = ForegroundEntryProbe()
        probe.status = .success(.shouldRequest)
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: true)

        await entry.enter()

        #expect(probe.events == ["status", "request", "run"])
    }

    @Test func everyOtherOutcomeStillRequestsTheRun() async {
        let cases: [(Result<HKAuthorizationRequestStatus, any Error>, [String])] = [
            (.success(.unnecessary), ["status", "run"]),
            (.success(.unknown), ["status", "error health authorization status unknown", "run"]),
            (.failure(ProbeError()), ["status", "error health authorization: ProbeError()", "run"]),
        ]
        for (status, expected) in cases {
            let probe = ForegroundEntryProbe()
            probe.status = status
            let entry = probe.makeEntry()
            entry.sceneActivityChanged(isActive: true)
            await entry.enter()
            #expect(probe.events == expected)
        }
    }

    @Test func bootWithTheSceneActiveEntersOnceWithoutATransition() async {
        let probe = ForegroundEntryProbe()
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: true)

        await entry.bootReachedReady()

        #expect(probe.events == ["status", "run"])
    }

    @Test func bootWithTheSceneInactiveRequestsNothingUntilTheTransition() async {
        let probe = ForegroundEntryProbe()
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: false)

        await entry.bootReachedReady()
        #expect(probe.events.isEmpty)

        entry.sceneActivityChanged(isActive: true)
        await entry.sceneBecameActive()
        #expect(probe.events == ["status", "run"])
    }

    @Test func aTransitionBeforeBootIsReadyDoesNothing() async {
        let probe = ForegroundEntryProbe()
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: true)

        await entry.sceneBecameActive()

        #expect(probe.events.isEmpty)
    }

    @Test func finishingSetupLetsTheNextTransitionEnter() async {
        let probe = ForegroundEntryProbe()
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: true)
        entry.setupCompleted()
        #expect(probe.events.isEmpty)

        await entry.sceneBecameActive()

        #expect(probe.events == ["status", "run"])
    }

    @Test func bootAndATransitionLandingTogetherShowOneSheet() async {
        let probe = ForegroundEntryProbe()
        probe.status = .success(.shouldRequest)
        probe.holdsSheet = true
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: true)

        let boot = Task { await entry.bootReachedReady() }
        while !probe.events.contains("request") { await Task.yield() }
        await entry.sceneBecameActive()
        #expect(probe.events == ["status", "request"])

        probe.answerSheet()
        await boot.value

        #expect(probe.events == ["status", "request", "run"])
    }

    @Test func backgroundingWhileTheSheetIsUpDefersTheRunToTheNextForeground() async {
        let probe = ForegroundEntryProbe()
        probe.status = .success(.shouldRequest)
        probe.holdsSheet = true
        let entry = probe.makeEntry()
        entry.sceneActivityChanged(isActive: true)

        let boot = Task { await entry.bootReachedReady() }
        while !probe.events.contains("request") { await Task.yield() }
        entry.sceneActivityChanged(isActive: false)
        probe.status = .success(.unnecessary)
        probe.answerSheet()
        await boot.value
        #expect(probe.events == ["status", "request"])

        entry.sceneActivityChanged(isActive: true)
        await entry.sceneBecameActive()

        #expect(probe.events == ["status", "request", "status", "run"])
    }

    @Test func theAskedTypesAreRecordedBeforeTheRun() async {
        let cases: [(HKAuthorizationRequestStatus, [String])] = [
            (.shouldRequest, ["status", "request", "asked", "run"]),
            (.unnecessary, ["status", "asked", "run"]),
        ]
        for (status, expected) in cases {
            let probe = ForegroundEntryProbe()
            probe.recordsAskedTypes = true
            probe.status = .success(status)
            let entry = probe.makeEntry()
            entry.sceneActivityChanged(isActive: true)
            await entry.enter()
            #expect(probe.events == expected)
        }
    }

    @Test func aFailedOrUnknownCheckRecordsNothing() async {
        let unknown = ForegroundEntryProbe()
        unknown.recordsAskedTypes = true
        unknown.status = .success(.unknown)
        let unknownEntry = unknown.makeEntry()
        unknownEntry.sceneActivityChanged(isActive: true)
        await unknownEntry.enter()
        #expect(!unknown.events.contains("asked"))

        let failedRequest = ForegroundEntryProbe()
        failedRequest.recordsAskedTypes = true
        failedRequest.status = .success(.shouldRequest)
        failedRequest.requestFails = true
        let failedEntry = failedRequest.makeEntry()
        failedEntry.sceneActivityChanged(isActive: true)
        await failedEntry.enter()
        #expect(failedRequest.events == ["status", "request", "error health authorization: ProbeError()", "run"])
    }
}
