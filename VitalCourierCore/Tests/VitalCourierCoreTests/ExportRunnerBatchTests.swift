import Foundation
import Testing

@testable import VitalCourierCore

@Suite struct ExportRunnerBatchTests {
  let now = date("2026-09-30T15:00:00Z")

  func makeRunner(store: LocalStore, health: FakeHealthSource) -> ExportRunner {
    let fixedNow = now
    return ExportRunner(store: store, health: health, destination: { nil }, now: { fixedNow }, timeZone: { saoPaulo })
  }

  func batch(_ start: String, anchor: UInt8, hasMore: Bool) -> HealthChanges {
    HealthChanges(added: [makeSample(start: start)], newAnchor: Data([anchor]), hasMore: hasMore)
  }

  @Test func batchesAreReadUntilHasMoreIsFalse() async throws {
    let store = try LocalStore.inMemory()
    let health = FakeHealthSource()
    await health.queue(batch("2026-09-25T12:00:00Z", anchor: 1, hasMore: true), for: .steps)
    await health.queue(batch("2026-09-26T12:00:00Z", anchor: 2, hasMore: true), for: .steps)
    await health.queue(batch("2026-09-27T12:00:00Z", anchor: 3, hasMore: false), for: .steps)

    let outcome = await makeRunner(store: store, health: health).run(
      trigger: .observerWake, options: .forTrigger(.observerWake)
    ) {}

    #expect(outcome.readOutcome == .read)
    #expect(try store.samples(type: .steps, month: "2026-09").count == 3)
    #expect(try store.anchor(for: .steps) == Data([3]))
    #expect(await health.receivedAnchors[.steps] == [nil, Data([1]), Data([2])])
  }

  @Test func aCancelBetweenBatchesKeepsTheCommittedBatch() async throws {
    let store = try LocalStore.inMemory()
    let health = FakeHealthSource()
    await health.queue(batch("2026-09-25T12:00:00Z", anchor: 1, hasMore: true), for: .steps)
    await health.queue(batch("2026-09-26T12:00:00Z", anchor: 2, hasMore: false), for: .steps)
    await health.cancelCurrentTaskOnNextChanges()
    let runner = makeRunner(store: store, health: health)

    _ = await Task { await runner.run(trigger: .backgroundRefresh, options: .forTrigger(.backgroundRefresh)) {} }.value

    #expect(try store.samples(type: .steps, month: "2026-09").count == 1)
    #expect(try store.anchor(for: .steps) == Data([1]))
    #expect(await health.receivedAnchors[.steps] == [nil])
  }

  @Test func anAnchorThatDoesNotAdvanceStopsTheLoopAsAFailedRead() async throws {
    let store = try LocalStore.inMemory()
    let health = FakeHealthSource()
    await health.queue(
      HealthChanges(added: [makeSample(start: "2026-09-25T12:00:00Z")], newAnchor: nil, hasMore: true), for: .steps)

    let outcome = await makeRunner(store: store, health: health).run(
      trigger: .observerWake, options: .forTrigger(.observerWake)
    ) {}

    #expect(outcome.readOutcome == .failed)
    #expect(outcome.errors.contains("read: anchorDidNotAdvance(VitalCourierCore.HealthType.steps)"))
    #expect(try store.samples(type: .steps, month: "2026-09").isEmpty)
    #expect(await health.receivedAnchors[.steps] == [nil])
  }
}
