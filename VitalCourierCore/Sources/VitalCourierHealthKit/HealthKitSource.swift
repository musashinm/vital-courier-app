import Foundation
import HealthKit
import VitalCourierCore

/// `HealthSource` over HealthKit (spec, Units: HealthReader), on the async query descriptors (iOS 15.4+). A read denial looks like no data; HealthKit doesn't reveal it.
public final class HealthKitSource: HealthSource {
    /// Samples per anchored batch: one batch and one `LocalStore` transaction stay small on a first import of years of steps.
    public static let batchLimit = 2_000

    public let healthStore: HKHealthStore
    private let protectedDataAvailable: @Sendable () async -> Bool

    /// `protectedDataAvailable` is `UIApplication.isProtectedDataAvailable` in the app; injected because that is UIKit and main-actor.
    public init(healthStore: HKHealthStore = HKHealthStore(), protectedDataAvailable: @escaping @Sendable () async -> Bool) {
        self.healthStore = healthStore
        self.protectedDataAvailable = protectedDataAvailable
    }

    public func requestReadAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: [], read: HealthKitMapping.readTypes)
    }

    /// Asks to read `types`. iOS lists only the types not asked about before.
    public func requestReadAuthorization(for types: [HealthType]) async throws {
        try await healthStore.requestAuthorization(toShare: [], read: HealthKitMapping.readTypes(for: types))
    }

    /// Whether asking to read `types` would show the Health sheet. `.unnecessary` only means every type was asked about before, never that reading was allowed (HealthKit hides read denial).
    public func readAuthorizationRequestStatus(for types: [HealthType]) async throws -> HKAuthorizationRequestStatus {
        try await healthStore.statusForAuthorizationRequest(toShare: [], read: HealthKitMapping.readTypes(for: types))
    }

    public func isReadable() async -> Bool {
        await protectedDataAvailable()
    }

    public func changes(for type: HealthType, since anchor: Data?) async throws -> HealthChanges {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [Self.predicate(for: type, matching: nil)],
            anchor: try anchor.map { try HealthKitMapping.queryAnchor(from: $0) },
            limit: Self.batchLimit
        )
        let result: HKAnchoredObjectQueryDescriptor<HKSample>.Result
        do {
            result = try await descriptor.result(for: healthStore)
        } catch {
            throw Self.mapped(error)
        }
        return HealthChanges(
            added: try result.addedSamples.map { try Self.healthSample(from: $0, type: type) },
            deletedUUIDs: result.deletedObjects.map(\.uuid),
            newAnchor: try HealthKitMapping.anchorData(result.newAnchor),
            hasMore: Self.hasMore(addedCount: result.addedSamples.count, deletedCount: result.deletedObjects.count)
        )
    }

    public func samples(for type: HealthType, in interval: DateInterval) async throws -> [HealthSample] {
        let window = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [Self.predicate(for: type, matching: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples: [HKSample]
        do {
            samples = try await descriptor.result(for: healthStore)
        } catch {
            throw Self.mapped(error)
        }
        return try samples.map { try Self.healthSample(from: $0, type: type) }
    }

    public func earliestSampleDate(types: [HealthType]) async throws -> Date? {
        var earliest: Date?
        for type in types {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [Self.predicate(for: type, matching: nil)],
                sortDescriptors: [SortDescriptor(\.startDate)],
                limit: 1
            )
            let first: [HKSample]
            do {
                first = try await descriptor.result(for: healthStore)
            } catch {
                throw Self.mapped(error)
            }
            if let start = first.first?.startDate {
                earliest = min(earliest ?? start, start)
            }
        }
        return earliest
    }

    /// Sum types (steps, exercise minutes) use `cumulativeSum`; resting heart rate uses `discreteAverage` in beats per minute; respiratory rate uses `discreteAverage`, `discreteMin` and `discreteMax` in breaths per minute, from one query. One day-long bucket anchored at the day's local midnight. Other types return nil.
    public func dailyStatistic(for type: HealthType, day: DayKey, timeZone: TimeZone) async throws -> DailyStatistic? {
        guard let aggregation = type.statisticsAggregation,
              let unit = HealthKitMapping.statisticUnit(for: type),
              let quantityType = HealthKitMapping.sampleType(for: type) as? HKQuantityType else { return nil }
        let interval = day.interval(in: timeZone)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: quantityType, predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)),
            options: Self.statisticsOptions(for: aggregation),
            anchorDate: interval.start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection: HKStatisticsCollection
        do {
            collection = try await descriptor.result(for: healthStore)
        } catch {
            throw Self.mapped(error)
        }
        guard let statistics = collection.statistics(for: interval.start) else { return nil }
        let chosen = Self.chosenQuantities(
            for: aggregation,
            sum: statistics.sumQuantity(),
            average: statistics.averageQuantity(),
            minimum: statistics.minimumQuantity(),
            maximum: statistics.maximumQuantity()
        )
        guard let value = chosen.value else { return nil }
        return DailyStatistic(value: value.doubleValue(for: unit), minimum: chosen.minimum?.doubleValue(for: unit), maximum: chosen.maximum?.doubleValue(for: unit))
    }

    static func statisticsOptions(for aggregation: StatisticsAggregation) -> HKStatisticsOptions {
        switch aggregation {
        case .sum: .cumulativeSum
        case .average: .discreteAverage
        // Apple allows any number of discrete options together, so one query returns all three.
        case .averageMinMax: [.discreteAverage, .discreteMin, .discreteMax]
        }
    }

    /// The quantities one statistics bucket yields for an aggregation. `minimum` and `maximum` stay nil unless it asked for them.
    struct ChosenQuantities {
        var value: HKQuantity?
        var minimum: HKQuantity? = nil
        var maximum: HKQuantity? = nil
    }

    /// Pure, so the choice is tested on the Mac: `HKStatistics` can't be built in a test.
    static func chosenQuantities(for aggregation: StatisticsAggregation, sum: HKQuantity?, average: HKQuantity?, minimum: HKQuantity?, maximum: HKQuantity?) -> ChosenQuantities {
        switch aggregation {
        case .sum: ChosenQuantities(value: sum)
        case .average: ChosenQuantities(value: average)
        case .averageMinMax: ChosenQuantities(value: average, minimum: minimum, maximum: maximum)
        }
    }

    /// A locked phone's Health database is inaccessible: that is a refused read, retried on the next trigger (spec, Error handling).
    public static func mapped(_ error: any Error) -> any Error {
        if let healthError = error as? HKError, healthError.code == .errorDatabaseInaccessible {
            return HealthSourceError.readRefused
        }
        return error
    }

    /// Apple documents `limit` as a maximum number of samples, not a combined samples-plus-deletions limit. Counting deletions too is conservative: a batch under the limit in samples but over it with deletions costs at most one extra, empty read, never lost data.
    public static func hasMore(addedCount: Int, deletedCount: Int) -> Bool {
        addedCount + deletedCount >= batchLimit
    }

    static func predicate(for type: HealthType, matching predicate: NSPredicate?) -> HKSamplePredicate<HKSample> {
        .sample(type: HealthKitMapping.sampleType(for: type), predicate: predicate)
    }

    static func healthSample(from sample: HKSample, type: HealthType) throws -> HealthSample {
        let value: SampleValue
        switch sample {
        case let quantitySample as HKQuantitySample:
            value = .quantity(try HealthKitMapping.storedValue(quantitySample.quantity, for: type))
        case let categorySample as HKCategorySample:
            value = .category(HealthKitMapping.categoryValueName(rawValue: categorySample.value, for: type))
        default:
            throw HealthKitMappingError.unexpectedSampleClass(String(describing: Swift.type(of: sample)))
        }
        return HealthKitMapping.makeSample(
            uuid: sample.uuid,
            type: type,
            start: sample.startDate,
            end: sample.endDate,
            value: value,
            sourceName: sample.sourceRevision.source.name,
            deviceName: sample.device?.name,
            metadata: sample.metadata
        )
    }
}
