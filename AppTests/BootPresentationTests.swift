import Testing

@testable import VitalCourier

@Suite struct BootPresentationTests {
  @Test func aFreshStateWhileBootingDoesNothing() {
    let presentation = BootPresentation()
    #expect(presentation.step(phaseIsBooting: true, isInitial: true, reduceMotion: false) == .none)
  }

  @Test func aViewCreatedAfterBootCuts() {
    let presentation = BootPresentation()
    #expect(presentation.step(phaseIsBooting: false, isInitial: true, reduceMotion: false) == .cut)
  }

  @Test func leavingBootFadesUnlessReduceMotionIsOn() {
    let presentation = BootPresentation()
    #expect(presentation.step(phaseIsBooting: false, isInitial: false, reduceMotion: false) == .fade)
    #expect(presentation.step(phaseIsBooting: false, isInitial: false, reduceMotion: true) == .cut)
  }

  @Test func afterACutLaterPhaseChangesDoNothing() {
    var presentation = BootPresentation()
    presentation.showRootImmediately()
    #expect(presentation.overlayVisible == false)
    #expect(presentation.bootOpacity == 0)
    #expect(presentation.rootOpacity == 1)
    #expect(presentation.rootIsInteractive == true)
    #expect(presentation.step(phaseIsBooting: false, isInitial: false, reduceMotion: false) == .none)
  }

  @Test func theFadeKeepsTheDestinationUntouchableUntilItFinishes() {
    var presentation = BootPresentation()
    presentation.beginFade()
    #expect(presentation.rootOpacity == 1)
    #expect(presentation.bootOpacity == 0)
    #expect(presentation.overlayVisible == true)
    #expect(presentation.rootIsInteractive == false)
    #expect(presentation.step(phaseIsBooting: false, isInitial: false, reduceMotion: false) == .none)
    presentation.finishFade()
    #expect(presentation.overlayVisible == false)
    #expect(presentation.rootIsInteractive == true)
  }

  @Test func aFadeInterruptedAfterBootCompletesAsACut() {
    var presentation = BootPresentation()
    presentation.beginFade()
    presentation.completeInterruptedFade(phaseIsBooting: false)
    #expect(presentation.overlayVisible == false)
    #expect(presentation.rootOpacity == 1)
    #expect(presentation.rootIsInteractive == true)
  }

  @Test func interruptionLeavesOtherStatesAlone() {
    var booting = BootPresentation()
    booting.completeInterruptedFade(phaseIsBooting: false)
    #expect(booting == BootPresentation())

    var midFadeButBooting = BootPresentation()
    midFadeButBooting.beginFade()
    let beforeCall = midFadeButBooting
    midFadeButBooting.completeInterruptedFade(phaseIsBooting: true)
    #expect(midFadeButBooting == beforeCall)

    var finished = BootPresentation()
    finished.beginFade()
    finished.finishFade()
    let afterFinish = finished
    finished.completeInterruptedFade(phaseIsBooting: false)
    #expect(finished == afterFinish)
  }
}
