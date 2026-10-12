/// RootView's boot-overlay state (design App Icon v2, Required RootView / BootView structure).
struct BootPresentation: Equatable {
    static let fadeDuration = Duration.milliseconds(180)

    enum Step: Equatable { case none, cut, fade }

    var overlayVisible = true
    var bootOpacity = 1.0
    var rootOpacity = 0.0
    var rootIsInteractive = false

    /// What a phase change should do. Only the first change away from `.booting` hands off; a RootView created after boot,
    /// and Reduce Motion, get a cut instead of the fade.
    func step(phaseIsBooting: Bool, isInitial: Bool, reduceMotion: Bool) -> Step {
        guard overlayVisible, rootOpacity == 0, !phaseIsBooting else { return .none }
        return isInitial || reduceMotion ? .cut : .fade
    }

    mutating func showRootImmediately() {
        overlayVisible = false
        bootOpacity = 0
        rootOpacity = 1
        rootIsInteractive = true
    }

    /// The animated half of the fade: the destination stays untouchable and hidden from VoiceOver until `finishFade()`.
    mutating func beginFade() {
        bootOpacity = 0
        rootOpacity = 1
    }

    mutating func finishFade() {
        overlayVisible = false
        rootIsInteractive = true
    }

    /// A fade whose removal task was cancelled (the view disappeared) would leave the overlay up and the destination
    /// untouchable. Once the phase has left `.booting`, finish that hand-off as a cut.
    mutating func completeInterruptedFade(phaseIsBooting: Bool) {
        guard overlayVisible, rootOpacity == 1, !rootIsInteractive, !phaseIsBooting else { return }
        showRootImmediately()
    }
}
