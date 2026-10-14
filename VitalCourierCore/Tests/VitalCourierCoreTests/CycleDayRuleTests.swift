import Foundation
import Testing
@testable import VitalCourierCore

@Suite struct CycleDayRuleTests {
    func flow(_ value: String, cycleStart: String? = nil) -> HealthSample {
        makeSample(type: .menstrualFlow, start: "2026-10-12T12:00:00Z", value: .category(value), metadata: cycleStart.map { [CycleDayRule.menstrualCycleStartMetadataKey: $0] } ?? [:])
    }

    @Test func theHeaviestFlowOfTheDayWins() {
        #expect(CycleDayRule.flowUpdate(from: [flow("light"), flow("heavy"), flow("medium")]) == .flow("heavy", periodStart: false))
        #expect(CycleDayRule.flowUpdate(from: [flow("none"), flow("unspecified")]) == .flow("unspecified", periodStart: false))
    }

    @Test func noneAloneIsKept() {
        #expect(CycleDayRule.flowUpdate(from: [flow("none")]) == .flow("none", periodStart: false))
    }

    @Test func anUnknownFlowRanksBelowNone() {
        #expect(CycleDayRule.flowUpdate(from: [flow("unknown(9)"), flow("none")]) == .flow("none", periodStart: false))
        #expect(CycleDayRule.flowUpdate(from: [flow("unknown(9)")]) == .flow("unknown(9)", periodStart: false))
    }

    @Test func anyCycleStartFlagStartsThePeriod() {
        #expect(CycleDayRule.flowUpdate(from: [flow("light", cycleStart: "0"), flow("medium", cycleStart: "1")]) == .flow("medium", periodStart: true))
        #expect(CycleDayRule.flowUpdate(from: [flow("light", cycleStart: "0")]) == .flow("light", periodStart: false))
    }

    @Test func noSamplesMeansNothingLogged() {
        #expect(CycleDayRule.flowUpdate(from: []) == .flow(nil, periodStart: false))
        #expect(CycleDayRule.spottingUpdate(from: []) == .spotting(false))
        #expect(CycleDayRule.spottingUpdate(from: [makeSample(type: .spotting, start: "2026-10-12T12:00:00Z", value: .category("notApplicable"))]) == .spotting(true))
    }
}
