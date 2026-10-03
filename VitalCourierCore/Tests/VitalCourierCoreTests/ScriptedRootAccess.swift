import Foundation
import Synchronization
@testable import VitalCourierCore

/// A `FolderRootAccess` over the real Foundation calls that can be told to fail the way the iCloud file provider does.
final class ScriptedRootAccess: Sendable {
    enum Step: Sendable {
        case resolve
        case staleRefresh
        case probe
    }

    private struct Script {
        var failingStep: Step?
        var error: NSError
        var isStale = false
        var beforeFailingProbe: (@Sendable () -> Void)?
    }

    static let helperNotReady = NSError(domain: NSCocoaErrorDomain, code: 4097, userInfo: [NSLocalizedDescriptionKey: "Couldn’t communicate with a helper application."])

    private let script = Mutex(Script(failingStep: nil, error: ScriptedRootAccess.helperNotReady))

    /// Makes `step` throw `error` until `succeed()`. `staleRefresh` also makes every resolve report a stale bookmark.
    func fail(_ step: Step, with error: NSError = ScriptedRootAccess.helperNotReady) {
        script.withLock {
            $0.failingStep = step
            $0.error = error
            $0.isStale = step == .staleRefresh
        }
    }

    func succeed() {
        script.withLock {
            $0.failingStep = nil
            $0.isStale = false
        }
    }

    /// Runs once, just before a failing probe throws, so a test can change the folder mid-refresh.
    func runBeforeFailingProbe(_ action: @escaping @Sendable () -> Void) {
        script.withLock { $0.beforeFailingProbe = action }
    }

    var access: FolderRootAccess {
        FolderRootAccess(
            resolve: { [self] bookmark in
                let current = script.withLock { $0 }
                if current.failingStep == .resolve { throw current.error }
                let live = try FolderRootAccess.live.resolve(bookmark)
                return (live.url, current.isStale || live.isStale)
            },
            makeBookmark: { [self] url in
                let current = script.withLock { $0 }
                if current.failingStep == .staleRefresh { throw current.error }
                return try FolderRootAccess.live.makeBookmark(url)
            },
            probe: { [self] url in
                let current = script.withLock { $0 }
                if current.failingStep == .probe {
                    let action = script.withLock { script -> (@Sendable () -> Void)? in
                        defer { script.beforeFailingProbe = nil }
                        return script.beforeFailingProbe
                    }
                    action?()
                    throw current.error
                }
                return try FolderRootAccess.live.probe(url)
            }
        )
    }
}
