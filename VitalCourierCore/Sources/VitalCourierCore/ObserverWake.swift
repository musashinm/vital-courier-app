import Synchronization

/// One HealthKit observer wake (spec: Observer Acknowledgement Spec, Units). The update handler calls `start` and acknowledges HealthKit right after it returns, so nothing blocks HealthKit's serial queue, which also delivers the run's own query results.
///
/// Background time can expire at any point: during `beginBackgroundTime`, before the run task exists, or while the run finishes. Expiry arrives on the main thread and the run doesn't, so every transition is claimed under one lock and every callback runs after the lock is released.
public final class ObserverWake: Sendable {
  /// `UIBackgroundTaskIdentifier.rawValue` in the app.
  public typealias BackgroundTimeToken = Int

  private struct State {
    var isTokenKnown = false
    var token: BackgroundTimeToken?
    var hasExpired = false
    var hasEnded = false
    var hasBeenCutShort = false
    var runTask: Task<Void, Never>?
  }

  private let state = Mutex(State())
  private let endBackgroundTime: @Sendable (BackgroundTimeToken) -> Void
  private let onCutShort: @Sendable () -> Void
  private let deliverCutShort: @Sendable (@escaping @Sendable () -> Void) -> Void

  private init(
    endBackgroundTime: @escaping @Sendable (BackgroundTimeToken) -> Void,
    onCutShort: @escaping @Sendable () -> Void,
    deliverCutShort: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
  ) {
    self.endBackgroundTime = endBackgroundTime
    self.onCutShort = onCutShort
    self.deliverCutShort = deliverCutShort
  }

  /// Begins background time, starts `run` in a new task, and returns at once. `beginBackgroundTime` returns nil when no time was granted: the run still starts, nothing is ended, and expiry is ignored. For a granted token, `endBackgroundTime` is called exactly once, by the run finishing or by expiry, whichever claims it first; expiry also cancels the run. `onFailure` gets any error but cancellation. `onCutShort` is called at most once, in its own task after the end, when expiry claimed the token or the run ended cancelled.
  @discardableResult
  public static func start(
    beginBackgroundTime: (_ onExpire: @escaping @Sendable () -> Void) -> BackgroundTimeToken?,
    endBackgroundTime: @escaping @Sendable (BackgroundTimeToken) -> Void,
    onFailure: @escaping @Sendable (String) -> Void,
    onCutShort: @escaping @Sendable () -> Void,
    run: @escaping @Sendable () async throws -> Void
  ) -> ObserverWake {
    start(
      beginBackgroundTime: beginBackgroundTime,
      endBackgroundTime: endBackgroundTime,
      onFailure: onFailure,
      onCutShort: onCutShort,
      beforeRegistration: {},
      beforeCompletion: {},
      deliverCutShort: { callback in Task { callback() } },
      run: run
    )
  }

  /// Test seams: `beforeRegistration` runs after background time is known and before the run task is registered; `beforeCompletion` runs after `run` returned or threw and before the wake claims its end; `deliverCutShort` is asked once per cut-short, after the lock is released, to run the callback.
  static func start(
    beginBackgroundTime: (_ onExpire: @escaping @Sendable () -> Void) -> BackgroundTimeToken?,
    endBackgroundTime: @escaping @Sendable (BackgroundTimeToken) -> Void,
    onFailure: @escaping @Sendable (String) -> Void,
    onCutShort: @escaping @Sendable () -> Void,
    beforeRegistration: () -> Void,
    beforeCompletion: @escaping @Sendable () async -> Void,
    deliverCutShort: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
    run: @escaping @Sendable () async throws -> Void
  ) -> ObserverWake {
    let wake = ObserverWake(
      endBackgroundTime: endBackgroundTime, onCutShort: onCutShort, deliverCutShort: deliverCutShort)
    let token = beginBackgroundTime { wake.expire() }
    wake.recordToken(token)
    beforeRegistration()
    let runTask = Task {
      var endedCancelled = false
      do {
        try await run()
        endedCancelled = Task.isCancelled
      } catch is CancellationError {
        endedCancelled = true
      } catch {
        if Task.isCancelled {
          endedCancelled = true
        } else {
          onFailure(String(describing: error))
        }
      }
      await beforeCompletion()
      wake.complete(endedCancelled: endedCancelled)
    }
    wake.register(runTask)
    return wake
  }

  func untilRunFinishes() async {
    await state.withLock { $0.runTask }?.value
  }

  private struct ExpiryClaim {
    let token: BackgroundTimeToken
    let runTask: Task<Void, Never>?
    let isFirstCutShort: Bool
  }

  /// Expiry before the token is known is only recorded, and `recordToken` acts on it. With no token there is nothing to end, and the run is left alone.
  private func expire() {
    let claim = state.withLock { current -> ExpiryClaim? in
      current.hasExpired = true
      guard current.isTokenKnown, let token = current.token, !current.hasEnded else { return nil }
      return Self.claimExpiry(of: token, in: &current)
    }
    if let claim { act(on: claim) }
  }

  private func recordToken(_ token: BackgroundTimeToken?) {
    let claim = state.withLock { current -> ExpiryClaim? in
      current.isTokenKnown = true
      current.token = token
      guard current.hasExpired, let token, !current.hasEnded else { return nil }
      return Self.claimExpiry(of: token, in: &current)
    }
    if let claim { act(on: claim) }
  }

  private static func claimExpiry(of token: BackgroundTimeToken, in current: inout State) -> ExpiryClaim {
    current.hasEnded = true
    let isFirstCutShort = !current.hasBeenCutShort
    current.hasBeenCutShort = true
    return ExpiryClaim(token: token, runTask: current.runTask, isFirstCutShort: isFirstCutShort)
  }

  /// Ends first, so a slow `onCutShort` can never delay the end iOS requires.
  private func act(on claim: ExpiryClaim) {
    endBackgroundTime(claim.token)
    claim.runTask?.cancel()
    if claim.isFirstCutShort { scheduleCutShort() }
  }

  /// In its own task: expiry can be claimed synchronously inside `start`, on HealthKit's queue, and the callback may write the store.
  private func scheduleCutShort() {
    deliverCutShort(onCutShort)
  }

  /// A run registered after a granted token expired is cancelled at once.
  private func register(_ runTask: Task<Void, Never>) {
    let shouldCancel = state.withLock { current -> Bool in
      current.runTask = runTask
      return current.hasExpired && current.token != nil
    }
    if shouldCancel { runTask.cancel() }
  }

  private func complete(endedCancelled: Bool) {
    let (tokenToEnd, isFirstCutShort) = state.withLock { current -> (BackgroundTimeToken?, Bool) in
      var tokenToEnd: BackgroundTimeToken?
      if let token = current.token, !current.hasEnded {
        current.hasEnded = true
        tokenToEnd = token
      }
      var isFirstCutShort = false
      if endedCancelled, !current.hasBeenCutShort {
        current.hasBeenCutShort = true
        isFirstCutShort = true
      }
      return (tokenToEnd, isFirstCutShort)
    }
    if let tokenToEnd { endBackgroundTime(tokenToEnd) }
    if isFirstCutShort { scheduleCutShort() }
  }
}
