#if DEBUG
import SwiftUI

/// What the On-device checklist reads. Debug builds only.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var protectionLines: [String] = []
    @State private var protectionError: String?
    @State private var duringWriteLines: [String] = []
    @State private var duringWriteError: String?

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
#endif
