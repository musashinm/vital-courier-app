import Foundation

@testable import VitalCourierCore

let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
let lisbon = TimeZone(identifier: "Europe/Lisbon")!
let utc = TimeZone(identifier: "UTC")!

func date(_ iso: String) -> Date {
  try! Date(iso, strategy: .iso8601)
}

func day(_ text: String) -> DayKey {
  DayKey(text)!
}

func makeSample(
  type: HealthType = .steps,
  start: String,
  end: String? = nil,
  value: SampleValue = .quantity(10),
  source: String = "iPhone",
  device: String? = "iPhone",
  zone: String? = nil,
  metadata: [String: String] = [:],
  uuid: UUID = UUID()
) -> HealthSample {
  HealthSample(
    uuid: uuid,
    type: type,
    start: date(start),
    end: date(end ?? start),
    value: value,
    source: source,
    device: device,
    metadata: metadata,
    timeZoneIdentifier: zone
  )
}

/// Holds async work until the test releases it.
actor Latch {
  private var isOpen = false
  private var waiter: CheckedContinuation<Void, Never>?

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiter = $0 }
  }

  func open() {
    isOpen = true
    waiter?.resume()
    waiter = nil
  }
}

/// Parks any number of callers and resumes all of them in one synchronous actor call, so contenders released together start together.
actor ReleaseBarrier {
  private var isReleased = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  var parkedCount: Int { waiters.count }

  func waitForRelease() async {
    if isReleased { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func releaseAll() {
    isReleased = true
    let parked = waiters
    waiters = []
    for waiter in parked { waiter.resume() }
  }
}
