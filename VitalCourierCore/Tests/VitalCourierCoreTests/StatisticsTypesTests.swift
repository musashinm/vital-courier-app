import Testing
@testable import VitalCourierCore

@Suite struct StatisticsTypesTests {
    @Test func statisticsAggregationClassifiesEveryType() {
        #expect(HealthType.steps.statisticsAggregation == .sum)
        #expect(HealthType.exerciseMinutes.statisticsAggregation == .sum)
        #expect(HealthType.restingHeartRate.statisticsAggregation == .average)
        #expect(HealthType.walkingHeartRateAverage.statisticsAggregation == .average)
        #expect(HealthType.respiratoryRate.statisticsAggregation == .averageMinMax)
        #expect(HealthType.bloodGlucose.statisticsAggregation == .averageMinMax)
        #expect(HealthType.sleep.statisticsAggregation == nil)
        #expect(HealthType.weight.statisticsAggregation == nil)
        #expect(HealthType.menstrualFlow.statisticsAggregation == nil)
        #expect(HealthType.spotting.statisticsAggregation == nil)
    }

    @Test func walkingHeartRateAverageIsStoredPerSecond() {
        #expect(HealthType.walkingHeartRateAverage.folderName == "walking-heart-rate-average")
        #expect(HealthType.walkingHeartRateAverage.siUnit == "count/s")
    }

    @Test func exactlyTheSixStatisticsTypesUseTheStatisticsQuery() {
        #expect(HealthType.allCases.filter(\.usesStatisticsQuery) == [.steps, .exerciseMinutes, .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate, .bloodGlucose])
    }

    @Test func exerciseMinutesIsStoredInSeconds() {
        #expect(HealthType.exerciseMinutes.folderName == "exercise-minutes")
        #expect(HealthType.exerciseMinutes.siUnit == "s")
    }

    @Test func respiratoryRateIsStoredPerSecond() {
        #expect(HealthType.respiratoryRate.folderName == "respiratory-rate")
        #expect(HealthType.respiratoryRate.siUnit == "count/s")
    }

    @Test func bloodGlucoseIsStoredInGramsPerLiter() {
        #expect(HealthType.bloodGlucose.folderName == "blood-glucose")
        #expect(HealthType.bloodGlucose.siUnit == "g/L")
    }
}
