#if DEBUG
import HealthKit
import SwiftUI

/// What the On-device checklist reads. Debug builds only; Release builds never ask to write health data.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var protectionLines: [String] = []
    @State private var protectionError: String?
    @State private var duringWriteLines: [String] = []
    @State private var duringWriteError: String?
    @State private var sampleStatus: String?

    var body: some View {
        List {
            Section {
                ForEach(protectionLines, id: \.self) { line in ErrorTextView(text: line) }
                if let protectionError { ErrorTextView(text: protectionError) }
                Button("Check again", action: loadProtection)
            } header: {
                Text("Local store protection")
            } footer: {
                Text("Every file and the folder should report NSFileProtectionCompleteUntilFirstUserAuthentication, and the folder excludedFromBackup=true. A -journal, -wal, -shm or temp file listed here must carry it too.")
            }
            Section {
                ForEach(duringWriteLines, id: \.self) { line in ErrorTextView(text: line) }
                if let duringWriteError { ErrorTextView(text: duringWriteError) }
                Button("Read protection during a write", action: loadProtectionDuringWrite)
            } header: {
                Text("Protection during a write")
            } footer: {
                Text("Opens a write transaction that changes the database, lists the files while it is open (the rollback journal exists only now), then rolls it back. The -journal line must carry the same class as the database.")
            }
            Section {
                ErrorTextView(text: BackgroundRefresh.taskIdentifier)
                ErrorTextView(text: "e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@\"\(BackgroundRefresh.taskIdentifier)\"]")
            } header: {
                Text("Background refresh")
            } footer: {
                Text("Pause the app in the debugger after it went to the background, paste the command, then continue.")
            }
            Section {
                if model.environment.setupErrors.isEmpty {
                    Text("None")
                } else {
                    ForEach(model.environment.setupErrors, id: \.self) { line in ErrorTextView(text: line) }
                }
            } header: {
                Text("Setup errors")
            }
            Section {
                Button("Write midnight test sample", action: writeSample)
                Button("Delete midnight test sample", role: .destructive, action: deleteSample)
                if let sampleStatus { ErrorTextView(text: sampleStatus) }
            } header: {
                Text("Midnight split release gate")
            } footer: {
                Text("Writes one 600-step sample from 23:30 two days ago to 00:30 yesterday, tagged VCTestSample. Compare vc_steps on both days with the Health app, then delete it.")
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear(perform: loadProtection)
    }

    private func loadProtection() {
        do {
            protectionLines = try ProtectionReport.lines(directory: AppEnvironment.storeDirectory)
            protectionError = nil
        } catch {
            protectionError = String(describing: error)
        }
    }

    private func loadProtectionDuringWrite() {
        do {
            let store = try model.environment.readyStore()
            duringWriteLines = try store.withWriteTransactionOpen {
                try ProtectionReport.lines(directory: AppEnvironment.storeDirectory)
            }
            duringWriteError = nil
        } catch {
            duringWriteError = String(describing: error)
        }
    }

    private func writeSample() {
        let healthStore = model.environment.health.healthStore
        Task {
            do {
                let window = try await MidnightTestSample.write(healthStore: healthStore, now: Date())
                sampleStatus = "Written: \(window.start.formatted()) – \(window.end.formatted())"
            } catch {
                sampleStatus = String(describing: error)
            }
        }
    }

    private func deleteSample() {
        let healthStore = model.environment.health.healthStore
        Task {
            do {
                let deletedCount = try await MidnightTestSample.delete(healthStore: healthStore)
                sampleStatus = "Deleted \(deletedCount) sample(s)"
            } catch {
                sampleStatus = String(describing: error)
            }
        }
    }
}

enum ProtectionReport {
    static func lines(directory: URL) throws -> [String] {
        let fileManager = FileManager.default
        let backupExcluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        var lines = ["LocalStore/ protection=\(try protection(of: directory)) excludedFromBackup=\(backupExcluded)"]
        for name in try fileManager.contentsOfDirectory(atPath: directory.path).sorted() {
            lines.append("\(name) protection=\(try protection(of: directory.appendingPathComponent(name)))")
        }
        return lines
    }

    private static func protection(of url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.protectionKey] as? FileProtectionType)?.rawValue ?? "none"
    }
}

/// A step sample crossing midnight, for the spec's midnight-split release gate.
enum MidnightTestSample {
    static let metadataKey = "VCTestSample"

    static func window(now: Date, calendar: Calendar = .current) -> DateInterval {
        let yesterdayStart = calendar.startOfDay(for: now.addingTimeInterval(-24 * 60 * 60))
        return DateInterval(start: yesterdayStart.addingTimeInterval(-30 * 60), end: yesterdayStart.addingTimeInterval(30 * 60))
    }

    static func write(healthStore: HKHealthStore, now: Date) async throws -> DateInterval {
        let sampleWindow = window(now: now)
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 600),
            start: sampleWindow.start,
            end: sampleWindow.end,
            metadata: [metadataKey: true]
        )
        try await healthStore.save(sample)
        return sampleWindow
    }

    static func delete(healthStore: HKHealthStore) async throws -> Int {
        try await healthStore.deleteObjects(of: HKQuantityType(.stepCount), predicate: HKQuery.predicateForObjects(withMetadataKey: metadataKey))
    }
}
#endif
