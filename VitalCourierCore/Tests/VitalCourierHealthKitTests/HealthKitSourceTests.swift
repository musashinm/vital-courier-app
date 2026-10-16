import Foundation
import HealthKit
import Testing
import VitalCourierCore
@testable import VitalCourierHealthKit

@Suite struct HealthKitSourceTests {
    @Test func aLockedDatabaseIsARefusedRead() {
        let mapped = HealthKitSource.mapped(HKError(.errorDatabaseInaccessible))

        #expect(mapped as? HealthSourceError == .readRefused)
    }

    @Test func otherErrorsPassThroughUnchanged() {
        let mapped = HealthKitSource.mapped(HKError(.errorAuthorizationDenied))

        #expect((mapped as? HKError)?.code == .errorAuthorizationDenied)
    }

    @Test func aFullBatchMeansThereMayBeMore() {
        #expect(HealthKitSource.hasMore(addedCount: 2_000, deletedCount: 0))
        #expect(HealthKitSource.hasMore(addedCount: 1_500, deletedCount: 500))
        #expect(!HealthKitSource.hasMore(addedCount: 1_999, deletedCount: 0))
        #expect(!HealthKitSource.hasMore(addedCount: 0, deletedCount: 0))
    }

    @Test func aSumAggregationAsksForACumulativeSumAndAnAverageForADiscreteAverage() {
        #expect(HealthKitSource.statisticsOptions(for: .sum) == .cumulativeSum)
        #expect(HealthKitSource.statisticsOptions(for: .average) == .discreteAverage)
    }

    @Test func theAggregationPicksWhichQuantityIsRead() {
        let sum = HKQuantity(unit: .minute(), doubleValue: 34)
        let average = HKQuantity(unit: .minute(), doubleValue: 1)
        #expect(HealthKitSource.chosenQuantity(for: HealthType.exerciseMinutes.statisticsAggregation!, sum: sum, average: average) == sum)
        #expect(HealthKitSource.chosenQuantity(for: HealthType.steps.statisticsAggregation!, sum: sum, average: average) == sum)
        #expect(HealthKitSource.chosenQuantity(for: HealthType.restingHeartRate.statisticsAggregation!, sum: sum, average: average) == average)
        #expect(HealthKitSource.chosenQuantity(for: .sum, sum: nil, average: average) == nil)
        #expect(HealthKitSource.chosenQuantity(for: HealthType.respiratoryRate.statisticsAggregation!, sum: sum, average: average) == average)
    }

    @Test func anAverageMinMaxAggregationAsksForAllThreeDiscreteOptions() {
        #expect(HealthKitSource.statisticsOptions(for: .averageMinMax) == [.discreteAverage, .discreteMin, .discreteMax])
    }
}
