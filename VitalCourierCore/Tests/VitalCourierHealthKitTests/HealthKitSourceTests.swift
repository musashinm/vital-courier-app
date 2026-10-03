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
}
