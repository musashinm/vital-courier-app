import Foundation
import HealthKit

/// The one place a foreground launch or return asks Health about types not asked about yet, then requests the app-open run (Cycle Tracking Spec, Launch check). Only `RootView`'s scene phase reaches it, never a background launch, which builds no scene and can't show a sheet.
@MainActor
final class ForegroundEntry {
    private let authorizationRequestStatus: @MainActor () async throws -> HKAuthorizationRequestStatus
    private let requestAuthorization: @MainActor () async throws -> Void
    private let recordError: @MainActor (String) -> Void
    /// Set by `AppModel` once it is initialized.
    var requestAppOpenRun: @MainActor () -> Void = {}
    /// Set by `AppModel`: records the enabled types as asked and rebuilds the observer (Exercise Minutes Spec, Launch observer).
    var typesWereAsked: @MainActor () -> Void = {}
    private var isSceneActive = false
    private var isReady = false
    private var isEntering = false

    init(
        authorizationRequestStatus: @escaping @MainActor () async throws -> HKAuthorizationRequestStatus,
        requestAuthorization: @escaping @MainActor () async throws -> Void,
        recordError: @escaping @MainActor (String) -> Void
    ) {
        self.authorizationRequestStatus = authorizationRequestStatus
        self.requestAuthorization = requestAuthorization
        self.recordError = recordError
    }

    /// `RootView` reports every scene phase, its first value included.
    func sceneActivityChanged(isActive: Bool) {
        isSceneActive = isActive
    }

    /// Boot reached `.ready`. On a cold foreground launch the scene is already active and no transition follows, so it enters now; with the scene inactive it requests nothing and the next `sceneBecameActive` enters.
    func bootReachedReady() async {
        isReady = true
        if isSceneActive { await enter() }
    }

    /// Onboarding just asked for access and requested its own run, so this only lets later transitions enter.
    func setupCompleted() {
        isReady = true
    }

    func sceneBecameActive() async {
        guard isReady else { return }
        await enter()
    }

    /// Asks Health first and requests the run only once the sheet is answered: a read started earlier would miss the new types, and nothing would retry it. A second call while one is running returns at once, so one sheet shows.
    ///
    /// The Health sheet can itself move the scene to inactive and back. Both orders end in one run: a transition that lands while `isEntering` is true returns at once and the in-flight entry runs the request, if the scene is active again by then; an answer that lands while the scene is inactive requests nothing, and the next active transition calls `enter()` again. That second call asks Health again, gets `.unnecessary` because the sheet was answered, shows no second sheet, and requests the run.
    func enter() async {
        guard !isEntering else { return }
        isEntering = true
        defer { isEntering = false }
        await askForTypesNotAskedYet()
        // With the scene inactive or in the background, nothing is requested here: the next active transition's `enter()` requests the run, so no read starts from the background.
        if isSceneActive {
            requestAppOpenRun()
        }
    }

    /// A failed or unknown check never blocks the export; it is recorded and the run goes ahead.
    private func askForTypesNotAskedYet() async {
        do {
            switch try await authorizationRequestStatus() {
            case .shouldRequest:
                try await requestAuthorization()
                // Allowed, denied or dismissed: Health won't show this sheet again, so every enabled type now counts as asked.
                typesWereAsked()
            case .unnecessary:
                // Every type was asked about before. This says nothing about whether reading was allowed.
                typesWereAsked()
            case .unknown:
                recordError("health authorization status unknown")
            @unknown default:
                recordError("health authorization status unknown")
            }
        } catch {
            recordError("health authorization: \(error)")
        }
    }
}
