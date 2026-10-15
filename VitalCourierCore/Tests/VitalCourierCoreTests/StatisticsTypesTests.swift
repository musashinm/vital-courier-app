import Testing
@testable import VitalCourierCore

@Suite struct StatisticsTypesTests {
    @Test func statisticsAggregationClassifiesEveryType() {
        #expect(HealthType.steps.statisticsAggregation == .sum)
        #expect(HealthType.exerciseMinutes.statisticsAggregation == .sum)
        #expect(HealthType.restingHeartRate.statisticsAggregation == .average)
        #expect(HealthType.sleep.statisticsAggregation == nil)
        #expect(HealthType.weight.statisticsAggregation == nil)
        #expect(HealthType.menstrualFlow.statisticsAggregation == nil)
        #expect(HealthType.spotting.statisticsAggregation == nil)
    }

    @Test func exactlyTheThreeStatisticsTypesUseTheStatisticsQuery() {
        #expect(HealthType.allCases.filter(\.usesStatisticsQuery) == [.steps, .exerciseMinutes, .restingHeartRate])
    }

    @Test func exerciseMinutesIsStoredInSeconds() {
        #expect(HealthType.exerciseMinutes.folderName == "exercise-minutes")
        #expect(HealthType.exerciseMinutes.siUnit == "s")
    }
}
