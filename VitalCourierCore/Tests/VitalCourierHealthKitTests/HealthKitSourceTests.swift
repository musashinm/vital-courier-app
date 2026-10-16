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

    @Test func theAggregationPicksWhichQuantitiesAreRead() {
        let sum = HKQuantity(unit: .minute(), doubleValue: 34)
        let average = HKQuantity(unit: .minute(), doubleValue: 1)
        let minimum = HKQuantity(unit: .minute(), doubleValue: 0.5)
        let maximum = HKQuantity(unit: .minute(), doubleValue: 2)

        let exercise = HealthKitSource.chosenQuantities(for: HealthType.exerciseMinutes.statisticsAggregation!, sum: sum, average: average, minimum: minimum, maximum: maximum)
        #expect(exercise.value == sum)
        #expect(exercise.minimum == nil)
        #expect(exercise.maximum == nil)

        #expect(HealthKitSource.chosenQuantities(for: HealthType.steps.statisticsAggregation!, sum: sum, average: average, minimum: minimum, maximum: maximum).value == sum)

        let restingHeartRate = HealthKitSource.chosenQuantities(for: HealthType.restingHeartRate.statisticsAggregation!, sum: sum, average: average, minimum: minimum, maximum: maximum)
        #expect(restingHeartRate.value == average)
        #expect(restingHeartRate.minimum == nil)
        #expect(restingHeartRate.maximum == nil)

        let respiratory = HealthKitSource.chosenQuantities(for: HealthType.respiratoryRate.statisticsAggregation!, sum: sum, average: average, minimum: minimum, maximum: maximum)
        #expect(respiratory.value == average)
        #expect(respiratory.minimum == minimum)
        #expect(respiratory.maximum == maximum)

        let glucose = HealthKitSource.chosenQuantities(for: HealthType.bloodGlucose.statisticsAggregation!, sum: sum, average: average, minimum: minimum, maximum: maximum)
        #expect(glucose.value == average)
        #expect(glucose.minimum == minimum)
        #expect(glucose.maximum == maximum)

        let empty = HealthKitSource.chosenQuantities(for: .averageMinMax, sum: nil, average: nil, minimum: nil, maximum: nil)
        #expect(empty.value == nil)
        #expect(empty.minimum == nil)
        #expect(empty.maximum == nil)
    }

    @Test func anAverageMinMaxAggregationAsksForAllThreeDiscreteOptions() {
        #expect(HealthKitSource.statisticsOptions(for: .averageMinMax) == [.discreteAverage, .discreteMin, .discreteMax])
    }
}
