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
        metadata: [:],
        timeZoneIdentifier: zone
    )
}
