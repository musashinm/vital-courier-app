import Testing
@testable import VitalCourierCore

@Suite struct OnceCallbackTests {
    @Test func aOnceCallbackRunsOnlyTheFirstTime() {
        let calls = Counter()
        let once = OnceCallback { calls.increment() }

        once()
        once()
        once()

        #expect(calls.value == 1)
    }

    @Test func concurrentCallsRunTheCallbackOnce() async {
        let calls = Counter()
        let once = OnceCallback { calls.increment() }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { once() } }
        }

        #expect(calls.value == 1)
    }
}
