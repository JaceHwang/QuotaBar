import Foundation
import AppKit
import Darwin
import QuotaCore

@MainActor final class ApplicationUpdateService {
    typealias Execute = @Sendable (String, @escaping @Sendable (ApplicationUpdateProgress) -> Void) async throws -> Void
    private let execute: Execute?
    private let currentVersion: String
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private(set) var targetVersion: String?
    private(set) var progress = ApplicationUpdateProgress(.idle)
    var onChange: (() -> Void)?
    var onReady: (() -> Void)?
    init(currentVersion: String, execute: Execute? = nil, resultReader: (() -> ApplicationUpdatePhase?)? = nil) {
        let readResult = resultReader ?? { Bundle.main.bundleURL.standardizedFileURL.path == UpdateLocations.target.standardizedFileURL.path ? UpdateInstallJob.consumeResult(in: UpdateLocations.cache, expectedTarget: UpdateLocations.target.path) : nil }
        if execute == nil, let result = readResult() { progress = ApplicationUpdateProgress(result) }
        self.execute = execute; self.currentVersion = currentVersion
        if execute == nil { Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.progress.phase == .idle, let result = readResult() else { return }
            self.progress = ApplicationUpdateProgress(result); self.onChange?()
        } }
    }
    func start(version: String) {
        guard !progress.phase.busy else { return }
        let id = UUID(); generation = id; targetVersion = version; progress = ApplicationUpdateProgress(.resolving); onChange?()
        let run = execute, currentVersion = self.currentVersion
        task = Task { [weak self] in
            var handoff: UpdateReadyHandoff?
            do {
                let emit: @Sendable (ApplicationUpdateProgress) -> Void = { [weak self] update in
                    Task { @MainActor [weak self] in guard let self, self.generation == id, self.progress.phase.canCancel else { return }; self.progress = update; self.onChange?() }
                }
                if let run { try await run(version, emit) }
                else {
                    let worker = Task.detached { try await Self.perform(version: version, currentVersion: currentVersion, emit: emit) }
                    handoff = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                }
                guard let self, generation == id, !Task.isCancelled else { handoff?.cancel(); return }
                try handoff?.commit()
                progress = ApplicationUpdateProgress(.handingOff); task = nil; onChange?(); onReady?()
            } catch {
                handoff?.cancel()
                guard let self, generation == id else { return }
                task = nil; progress = ApplicationUpdateProgress(Task.isCancelled ? .cancelled : .failed); onChange?()
            }
        }
    }
    func cancel() {
        guard progress.phase.canCancel else { return }
        generation = UUID(); task?.cancel(); task = nil; progress = ApplicationUpdateProgress(.cancelled); onChange?()
    }
    nonisolated private static func perform(version: String, currentVersion: String, emit: @escaping @Sendable (ApplicationUpdateProgress) -> Void) async throws -> UpdateReadyHandoff {
        guard Bundle.main.bundleURL.standardizedFileURL.path == UpdateLocations.target.standardizedFileURL.path else { throw UpdatePackageError.invalidIdentity }
        let download = try await UpdateDownloadClient().download(version: version, platform: "macos-arm64", currentVersion: currentVersion, cache: UpdateLocations.cache) { n, total in emit(ApplicationUpdateProgress(.downloading, received: n, total: total)) }
        var handedOff = false
        defer { if !handedOff { try? FileManager.default.removeItem(at: download.directory) } }
        emit(ApplicationUpdateProgress(.verifying)); _ = try MacUpdatePackage.prepare(download); try Task.checkCancellation()
        emit(ApplicationUpdateProgress(.preparing))
        let job = UpdateInstallJob(operationID: UUID().uuidString, target: UpdateLocations.target.path, parentPID: ProcessInfo.processInfo.processIdentifier, nonce: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), expiresAt: Date().addingTimeInterval(600), release: download.release)
        try job.write(download.directory)
        let current = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QuotaBarUpdater"), helper = download.directory.appendingPathComponent("QuotaBarUpdater")
        guard try current.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]).isSymbolicLink != true, try current.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw UpdatePackageError.linkedContent }
        try FileManager.default.copyItem(at: current, to: helper)
        guard try UpdateFileIntegrity.sha256(current) == UpdateFileIntegrity.sha256(helper) else { throw UpdatePackageError.invalidPackage }
        try Task.checkCancellation()
        let process = Process(); process.executableURL = helper; process.arguments = [download.directory.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            let deadline = Date().addingTimeInterval(10)
            while !job.hasReceipt("ready", directory: download.directory) {
                try Task.checkCancellation()
                guard process.isRunning, Date() < deadline else { throw UpdatePackageError.commandTimedOut }
                try await Task.sleep(for: .milliseconds(50))
            }
            try Task.checkCancellation(); handedOff = true
            return UpdateReadyHandoff(process: process, download: download, job: job)
        } catch {
            if process.isRunning { process.terminate(); process.waitUntilExit() }; throw error
        }
    }
}

/// Ownership crosses the worker/UI boundary once. Only the current UI generation may commit.
private final class UpdateReadyHandoff: @unchecked Sendable {
    let process: Process, download: DownloadedUpdate, job: UpdateInstallJob
    private var committed = false
    init(process: Process, download: DownloadedUpdate, job: UpdateInstallJob) { self.process = process; self.download = download; self.job = job }
    func commit() throws {
        guard process.isRunning else { throw UpdatePackageError.commandFailed }
        try job.receipt("handoff", directory: download.directory); committed = true
    }
    func cancel() {
        guard !committed else { return }
        if process.isRunning { process.terminate(); let end = Date().addingTimeInterval(2); while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }; if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit() }
        try? FileManager.default.removeItem(at: download.directory)
    }
    deinit { cancel() }
}
