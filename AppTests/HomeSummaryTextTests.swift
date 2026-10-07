import Foundation
import Testing
@testable import VitalCourier
import VitalCourierCore

@Suite struct HomeSummaryTextTests {
    let now = date("2026-10-03T11:16:00Z")
    let english = StatusDateFormatter(localization: .english, timeZone: saoPaulo)
    let portuguese = StatusDateFormatter(localization: .portuguese, timeZone: saoPaulo)

    func run(_ start: String, written: Int = 0, failed: Int = 0, errors: [String] = [], trigger: Trigger = .appOpen) -> RunRecord {
        RunRecord(startedAt: date(start), trigger: trigger.rawValue, readOutcome: ReadOutcome.read.rawValue, daysWritten: written, daysFailed: failed, daysPending: 0, errors: errors, id: 7)
    }

    @Test func summaryCopyMatchesTheDesign() {
        let wrote = run("2026-10-03T11:16:00Z", written: 3, trigger: .observerWake)
        let checked = run("2026-10-03T11:16:00Z")
        let failing = run("2026-10-03T11:16:00Z", failed: 2, errors: ["json steps 2026-10: x", "note 2026-10-01: y"])

        #expect(HomeSummary.daysUpdated(run: wrote).text(formatter: english, now: now) == HomeSummaryText(symbolName: "checkmark.circle.fill", title: "3 days updated", detail: "Today at 8:16 AM · Observer wake", errorText: nil, showsMoreErrorsNote: false, action: .runDetails))
        #expect(HomeSummary.daysUpdated(run: run("2026-10-03T11:16:00Z", written: 1)).text(formatter: english, now: now).title == "1 day updated")
        #expect(HomeSummary.upToDate(run: checked).text(formatter: english, now: now).detail == "Checked today at 8:16 AM · App open")
        #expect(HomeSummary.running(lastCompleted: date("2026-10-03T00:42:00Z")).text(formatter: english, now: now).detail == "Last completed yesterday at 9:42 PM.")
        #expect(HomeSummary.running(lastCompleted: nil).text(formatter: english, now: now).detail == nil)
        #expect(HomeSummary.writeFailure(run: failing).text(formatter: english, now: now) == HomeSummaryText(symbolName: "xmark.octagon.fill", title: "2 days failed", detail: nil, errorText: "json steps 2026-10: x", showsMoreErrorsNote: true, action: .runDetails))
        #expect(HomeSummary.writeFailure(run: run("2026-10-03T11:16:00Z", failed: 1)).text(formatter: english, now: now).title == "1 day failed")
        #expect(HomeSummary.folderLost(errorText: "gone").text(formatter: english, now: now) == HomeSummaryText(symbolName: "folder.badge.minus", title: "Folder lost, pick it again", detail: nil, errorText: "gone", showsMoreErrorsNote: false, action: .pickFolderAgain))
        #expect(HomeSummary.noFolder.text(formatter: english, now: now) == HomeSummaryText(symbolName: "folder.badge.questionmark", title: "Pick a folder", detail: "Health data can be read locally, but files need a destination.", errorText: nil, showsMoreErrorsNote: false, action: .pickFolder))
        #expect(HomeSummary.readOverdue.text(formatter: english, now: now) == HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Health data hasn’t been read in 24 hours", detail: "Unlock this iPhone and open Vital Courier. Saved files remain in place.", errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns))
        #expect(HomeSummary.dailyValuesOverdue.text(formatter: english, now: now) == HomeSummaryText(symbolName: "exclamationmark.arrow.triangle.2.circlepath", title: "Daily summaries haven’t refreshed in 24 hours", detail: "Unlock this iPhone and open Vital Courier to try again.", errorText: nil, showsMoreErrorsNote: false, action: .viewRecentRuns))
        #expect(HomeSummary.awaitingReread.text(formatter: english, now: now) == HomeSummaryText(symbolName: "arrow.clockwise.circle", title: "Waiting to reread health data", detail: "Keep this iPhone unlocked and open Vital Courier. Your exported files remain in place.", errorText: nil, showsMoreErrorsNote: false, action: .none))
        #expect(HomeSummary.waitingForFirstExport.text(formatter: english, now: now) == HomeSummaryText(symbolName: "clock.badge.questionmark", title: "Waiting for the first export", detail: "Keep your iPhone unlocked while Vital Courier reads the four data types.", errorText: nil, showsMoreErrorsNote: false, action: .none))
        #expect(HomeSummary.running(lastCompleted: nil).text(formatter: english, now: now).title == "Checking for updates…")
    }

    @Test func protectionFailuresShowTheSavedError() {
        let failing = run("2026-10-03T10:00:00Z", failed: 1, errors: ["note 2026-10-01: x", "file protection: ProtectionFailed()"])
        #expect(HomeSummary.protectionFailure(run: failing).text(formatter: english, now: now) == HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Local data protection failed", detail: nil, errorText: "file protection: ProtectionFailed()", showsMoreErrorsNote: true, action: .runDetails))
        #expect(HomeSummary.protectionFailurePending(errorText: "ProtectionFailed()").text(formatter: english, now: now) == HomeSummaryText(symbolName: "lock.trianglebadge.exclamationmark", title: "Local data protection failed", detail: "Saving it to History failed. It is saved the next time the app can write.", errorText: "file protection: ProtectionFailed()", showsMoreErrorsNote: false, action: .none))
    }

    @Test func recencyCopyMatchesTheDesign() {
        let today = day("2026-10-03")
        #expect(TypeRecency.updated(today).valueText(formatter: english, today: today, source: nil) == "Updated today")
        #expect(TypeRecency.updated(today).valueText(formatter: english, today: today, source: "Apple Watch") == "Updated today · Apple Watch")
        #expect(TypeRecency.updated(day("2026-09-24")).valueText(formatter: english, today: today, source: nil) == "Updated Sep 24")
        #expect(TypeRecency.silentForAWeek.valueText(formatter: english, today: today, source: "Apple Watch") == "No data received in 7 days")
        #expect(TypeRecency.noDataYet.valueText(formatter: english, today: today, source: nil) == "No data yet")
    }

    @Test func portugueseSummaries() {
        let wrote = run("2026-10-03T11:16:00Z", written: 3, trigger: .observerWake)
        #expect(HomeSummary.daysUpdated(run: wrote).text(formatter: portuguese, now: now).title == "3 dias atualizados")
        #expect(HomeSummary.daysUpdated(run: wrote).text(formatter: portuguese, now: now).detail == "Hoje às 08:16 · Aviso do Saúde")
        #expect(HomeSummary.daysUpdated(run: run("2026-10-03T11:16:00Z", written: 1)).text(formatter: portuguese, now: now).title == "1 dia atualizado")
        #expect(HomeSummary.upToDate(run: run("2026-10-03T11:16:00Z")).text(formatter: portuguese, now: now).detail == "Verificado hoje às 08:16 · App aberto")
        #expect(HomeSummary.upToDate(run: run("2026-10-03T11:16:00Z")).text(formatter: portuguese, now: now).title == "Tudo em dia")
        #expect(HomeSummary.running(lastCompleted: date("2026-10-03T00:42:00Z")).text(formatter: portuguese, now: now).detail == "Última conclusão: ontem às 21:42.")
        #expect(HomeSummary.writeFailure(run: run("2026-10-03T11:16:00Z", failed: 2)).text(formatter: portuguese, now: now).title == "2 dias falharam")
        #expect(HomeSummary.writeFailure(run: run("2026-10-03T11:16:00Z", failed: 1)).text(formatter: portuguese, now: now).title == "1 dia falhou")
        #expect(HomeSummary.noFolder.text(formatter: portuguese, now: now).title == "Escolher uma pasta")
        #expect(HomeSummary.readOverdue.text(formatter: portuguese, now: now).title == "Os dados de saúde não são lidos há 24 horas")
        #expect(HomeSummary.waitingForFirstExport.text(formatter: portuguese, now: now).detail == "Deixe o iPhone desbloqueado enquanto o Vital Courier lê os quatro tipos de dados.")
    }

    @Test func portugueseCoversEveryHomeCase() {
        let failing = run("2026-10-03T10:00:00Z", failed: 1, errors: ["note 2026-10-01: x", "file protection: ProtectionFailed()"])
        func text(_ summary: HomeSummary) -> HomeSummaryText { summary.text(formatter: portuguese, now: now) }

        #expect(text(.folderLost(errorText: "gone")).title == "Pasta perdida, escolha de novo")
        #expect(text(.folderLost(errorText: "gone")).detail == nil)
        #expect(text(.noFolder).title == "Escolher uma pasta")
        #expect(text(.noFolder).detail == "Os dados de saúde podem ser lidos no iPhone, mas os arquivos precisam de um destino.")
        #expect(text(.running(lastCompleted: nil)).title == "Procurando atualizações…")
        #expect(text(.running(lastCompleted: nil)).detail == nil)
        #expect(text(.running(lastCompleted: date("2026-10-03T00:42:00Z"))).title == "Procurando atualizações…")
        #expect(text(.awaitingReread).title == "Aguardando para ler os dados de saúde de novo")
        #expect(text(.awaitingReread).detail == "Deixe este iPhone desbloqueado e abra o Vital Courier. Seus arquivos exportados continuam onde estão.")
        #expect(text(.protectionFailurePending(errorText: "ProtectionFailed()")).title == "A proteção dos dados locais falhou")
        #expect(text(.protectionFailurePending(errorText: "ProtectionFailed()")).detail == "Não deu para salvar isso no Histórico. Vai ser salvo na próxima vez que o app conseguir gravar.")
        #expect(text(.protectionFailure(run: failing)).title == "A proteção dos dados locais falhou")
        #expect(text(.protectionFailure(run: failing)).detail == nil)
        #expect(text(.writeFailure(run: failing)).title == "1 dia falhou")
        #expect(text(.writeFailure(run: failing)).detail == nil)
        #expect(text(.writeFailure(run: run("2026-10-03T11:16:00Z"))).title == "0 dias falharam")
        #expect(text(.readOverdue).title == "Os dados de saúde não são lidos há 24 horas")
        #expect(text(.readOverdue).detail == "Desbloqueie este iPhone e abra o Vital Courier. Os arquivos salvos continuam onde estão.")
        #expect(text(.dailyValuesOverdue).title == "Os resumos diários não são atualizados há 24 horas")
        #expect(text(.dailyValuesOverdue).detail == "Desbloqueie este iPhone e abra o Vital Courier para tentar de novo.")
        #expect(text(.daysUpdated(run: run("2026-10-03T11:16:00Z", written: 0))).title == "0 dias atualizados")
        #expect(text(.upToDate(run: run("2026-10-03T11:16:00Z"))).title == "Tudo em dia")
        #expect(text(.waitingForFirstExport).title == "Aguardando a primeira exportação")
        #expect(text(.waitingForFirstExport).detail == "Deixe o iPhone desbloqueado enquanto o Vital Courier lê os quatro tipos de dados.")
    }

    @Test func portugueseRecency() {
        let today = day("2026-10-03")
        #expect(TypeRecency.updated(today).valueText(formatter: portuguese, today: today, source: nil) == "Atualizado hoje")
        #expect(TypeRecency.updated(today).valueText(formatter: portuguese, today: today, source: "Apple Watch") == "Atualizado hoje · Apple Watch")
        #expect(TypeRecency.updated(day("2026-09-24")).valueText(formatter: portuguese, today: today, source: nil) == "Atualizado 24 de set.")
        #expect(TypeRecency.silentForAWeek.valueText(formatter: portuguese, today: today, source: nil) == "Nenhum dado recebido em 7 dias")
        #expect(TypeRecency.noDataYet.valueText(formatter: portuguese, today: today, source: nil) == "Nenhum dado ainda")
        #expect(TypeRecency.updated(day("2026-10-02")).valueText(formatter: portuguese, today: today, source: nil) == "Atualizado ontem")
        #expect(TypeRecency.silentForAWeek.valueText(formatter: portuguese, today: today, source: "Apple Watch") == "Nenhum dado recebido em 7 dias")
        #expect(TypeRecency.noDataYet.valueText(formatter: portuguese, today: today, source: "Apple Watch") == "Nenhum dado ainda")
    }
}
