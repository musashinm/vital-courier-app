import Foundation
import Testing
import VitalCourierCore

@testable import VitalCourier

@Suite struct RunLabelsTests {
  func run(written: Int = 0, failed: Int = 0, pending: Int = 0) -> RunRecord {
    RunRecord(
      startedAt: date("2026-10-03T11:16:00Z"), trigger: Trigger.appOpen.rawValue,
      readOutcome: ReadOutcome.read.rawValue, daysWritten: written, daysFailed: failed, daysPending: pending,
      errors: [], id: 1)
  }

  @Test func labelsMapTheStoredNamesExactly() {
    #expect(RunLabels.trigger("observerWake", in: .english) == "Observer wake")
    #expect(RunLabels.trigger("appOpen", in: .english) == "App open")
    #expect(RunLabels.trigger("backgroundRefresh", in: .english) == "Background refresh")
    #expect(RunLabels.trigger("appIntent", in: .english) == "Export now")
    #expect(RunLabels.trigger("rebuildAll", in: .english) == "Rebuild all")
    #expect(RunLabels.trigger(RunRecord.appEventTrigger, in: .english) == "App event")
    #expect(RunLabels.trigger("somethingNew", in: .english) == "somethingNew")
    #expect(RunLabels.readOutcome("read", in: .english) == "Read")
    #expect(RunLabels.readOutcome("skipped: locked", in: .english) == "Skipped: locked")
    #expect(RunLabels.readOutcome("not requested", in: .english) == "Not requested")
    #expect(RunLabels.readOutcome("failed", in: .english) == "Failed")
    #expect(RunLabels.readOutcome("somethingNew", in: .english) == "somethingNew")
  }

  @Test func dayCountsShowPendingOnlyWhenNonzero() {
    #expect(RunLabels.dayCounts(run(written: 3), in: .english) == "3 written · 0 failed")
    #expect(
      RunLabels.dayCounts(run(written: 1, failed: 1, pending: 2), in: .english) == "1 written · 1 failed · 2 pending")
  }

  @Test func zeroCountsUseTheirOwnKey() {
    #expect(RunLabels.daysUpdated(0, in: .english) == "0 days updated")
    #expect(RunLabels.daysUpdated(1, in: .english) == "1 day updated")
    #expect(RunLabels.daysUpdated(2, in: .english) == "2 days updated")
    #expect(RunLabels.daysFailed(0, in: .english) == "0 days failed")
    #expect(RunLabels.daysFailed(1, in: .english) == "1 day failed")
    #expect(RunLabels.daysFailed(2, in: .english) == "2 days failed")
  }

  /// The system resolves the dialog in the request's language; the test sets that language through the resource's locale.
  func rendered(_ resource: LocalizedStringResource, _ localeIdentifier: String) -> String {
    var resource = resource
    resource.locale = Locale(identifier: localeIdentifier)
    return String(localized: resource)
  }

  func outcome(written: Int, failed: Int = 0, pending: Int = 0, errors: [String] = []) -> RunOutcome {
    RunOutcome(
      readOutcome: .notRequested, daysWritten: written, daysFailed: failed, daysPending: pending, errors: errors)
  }

  @Test func theExportNowDialogSummarisesTheOutcome() {
    #expect(rendered(RunLabels.exportNowDialog(outcome(written: 3)), "en_US") == "3 days written, 0 failed.")
    #expect(
      rendered(
        RunLabels.exportNowDialog(
          outcome(written: 1, failed: 1, pending: 2, errors: ["json steps 2026-10: x", "note 2026-10-01: y"])), "en_US")
        == "1 day written, 1 failed, 2 pending. json steps 2026-10: x")
    #expect(rendered(RunLabels.exportNowDialog(outcome(written: 3)), "pt_BR") == "3 dias gravados, 0 falhas.")
    #expect(
      rendered(
        RunLabels.exportNowDialog(outcome(written: 1, failed: 1, pending: 2, errors: ["json steps 2026-10: x"])),
        "pt_BR") == "1 dia gravado, 1 falha, 2 pendentes. json steps 2026-10: x")
    #expect(
      rendered(RunLabels.exportNowDialog(outcome(written: 3, failed: 2, pending: 1)), "pt_BR")
        == "3 dias gravados, 2 falhas, 1 pendente.")
  }

  /// Written and failed counts of 0 each branch to their own key (Portuguese plural rules put 0 with 1, so "0 falha" would be wrong).
  @Test func theDialogHandlesZeroWrittenAndZeroFailedDays() {
    #expect(rendered(RunLabels.exportNowDialog(outcome(written: 0)), "en_US") == "0 days written, 0 failed.")
    #expect(
      rendered(RunLabels.exportNowDialog(outcome(written: 0, failed: 1, pending: 2)), "en_US")
        == "0 days written, 1 failed, 2 pending.")
    #expect(rendered(RunLabels.exportNowDialog(outcome(written: 0)), "pt_BR") == "0 dias gravados, 0 falhas.")
    #expect(
      rendered(RunLabels.exportNowDialog(outcome(written: 0, pending: 2)), "pt_BR")
        == "0 dias gravados, 0 falhas, 2 pendentes.")
    #expect(rendered(RunLabels.exportNowDialog(outcome(written: 0, failed: 1)), "pt_BR") == "0 dias gravados, 1 falha.")
    #expect(
      rendered(RunLabels.exportNowDialog(outcome(written: 0, failed: 1, pending: 2)), "pt_BR")
        == "0 dias gravados, 1 falha, 2 pendentes.")
    #expect(
      rendered(RunLabels.exportNowDialog(outcome(written: 3, pending: 1)), "pt_BR")
        == "3 dias gravados, 0 falhas, 1 pendente.")
    #expect(
      rendered(RunLabels.exportNowDialog(outcome(written: 3, failed: 2)), "pt_BR") == "3 dias gravados, 2 falhas.")
  }

  @Test func portugueseLabels() {
    #expect(RunLabels.trigger("observerWake", in: .portuguese) == "Aviso do app Saúde")
    #expect(RunLabels.trigger("appOpen", in: .portuguese) == "App aberto")
    #expect(RunLabels.trigger("backgroundRefresh", in: .portuguese) == "Atualização em segundo plano")
    #expect(RunLabels.trigger("appIntent", in: .portuguese) == "Exportar agora")
    #expect(RunLabels.trigger("rebuildAll", in: .portuguese) == "Reconstruir tudo")
    #expect(RunLabels.trigger(RunRecord.appEventTrigger, in: .portuguese) == "Evento do app")
    #expect(RunLabels.trigger("somethingNew", in: .portuguese) == "somethingNew")
    #expect(RunLabels.readOutcome("read", in: .portuguese) == "Lido")
    #expect(RunLabels.readOutcome("skipped: locked", in: .portuguese) == "Pulado: bloqueado")
    #expect(RunLabels.readOutcome("not requested", in: .portuguese) == "Não solicitado")
    #expect(RunLabels.readOutcome("failed", in: .portuguese) == "Falhou")
    #expect(RunLabels.dayCounts(run(written: 3), in: .portuguese) == "Gravados: 3 · Falhas: 0")
    #expect(
      RunLabels.dayCounts(run(written: 1, failed: 1, pending: 2), in: .portuguese)
        == "Gravados: 1 · Falhas: 1 · Pendentes: 2")
  }

  @Test func portugueseZeroCountsUseTheirOwnKey() {
    #expect(RunLabels.daysUpdated(0, in: .portuguese) == "0 dias atualizados")
    #expect(RunLabels.daysUpdated(1, in: .portuguese) == "1 dia atualizado")
    #expect(RunLabels.daysUpdated(2, in: .portuguese) == "2 dias atualizados")
    #expect(RunLabels.daysFailed(0, in: .portuguese) == "0 dias falharam")
    #expect(RunLabels.daysFailed(1, in: .portuguese) == "1 dia falhou")
    #expect(RunLabels.daysFailed(2, in: .portuguese) == "2 dias falharam")
  }
}
