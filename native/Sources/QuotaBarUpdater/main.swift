import Foundation
import Darwin
import QuotaCore

func executablePath(_ pid: Int32) throws -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { throw UpdatePackageError.invalidIdentity }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
func launch(_ target: URL, args: [String]) throws -> Process {
    let process = Process(); process.executableURL = target.appendingPathComponent("Contents/MacOS/CodexQuota"); process.arguments = args
    process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
    try process.run(); return process
}
// Recovery accepts only the fixed target's journal-bound job, never a caller supplied target.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--recover" {
    do {
        let directory = try UpdateLocations.directory(CommandLine.arguments[2]), job = try UpdateInstallJob.read(directory)
        guard URL(fileURLWithPath: job.target).standardizedFileURL.path == UpdateLocations.target.standardizedFileURL.path,
              try ApplicationUpdateTransaction.recoveryJob(target: UpdateLocations.target)?.standardizedFileURL.path == directory.standardizedFileURL.path,
              job.hasReceipt("ready", directory: directory), let parent = Int32(CommandLine.arguments[3]), parent == 0 || parent > 1 else { throw UpdatePackageError.invalidPackage }
        if parent > 1, kill(parent, 0) == 0 {
            guard try URL(fileURLWithPath: executablePath(parent)).standardizedFileURL.path == UpdateLocations.target.appendingPathComponent("Contents/MacOS/CodexQuota").standardizedFileURL.path else { throw UpdatePackageError.invalidIdentity }
            let end = Date().addingTimeInterval(20)
            while kill(parent, 0) == 0 { guard Date() < end else { throw UpdatePackageError.commandTimedOut }; Thread.sleep(forTimeInterval: 0.05) }
        }
        try ApplicationUpdateTransaction(target: UpdateLocations.target).recover()
        try job.receipt("rolledBack", directory: directory); _ = try launch(UpdateLocations.target, args: []); exit(0)
    } catch { fputs("QuotaBar recovery failed; backup and journal retained.\n", stderr); exit(1) }
}
var phase = "job-location"
do {
    guard CommandLine.arguments.count == 2 else { throw UpdatePackageError.invalidPackage }
    let directory = try UpdateLocations.directory(CommandLine.arguments[1]), job = try UpdateInstallJob.read(directory)
    phase = "job-validation"
    try job.validate(directory: directory, expectedTarget: UpdateLocations.target.path, now: Date())
    let reservation = try UpdateHandoffReservation(target: UpdateLocations.target)
    defer { reservation.release() }
    phase = "parent-validation"
    guard try URL(fileURLWithPath: executablePath(job.parentPID)).standardizedFileURL.path == URL(fileURLWithPath: job.target + "/Contents/MacOS/CodexQuota").standardizedFileURL.path else { throw UpdatePackageError.invalidIdentity }
    let archive = directory.appendingPathComponent(job.release.package.name), proof = directory.appendingPathComponent(job.release.provenance.name), candidate = directory.appendingPathComponent("QuotaBar.app")
    phase = "package-validation"
    try UpdateFileIntegrity.verify(archive, asset: job.release.package); try UpdateFileIntegrity.verify(proof, asset: job.release.provenance)
    try MacUpdatePackage.verifyApp(candidate, release: job.release, provenance: proof)
    phase = "operation-lock"
    let fd = open(directory.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw UpdatePackageError.invalidPackage }
    defer { close(fd) }
    let consumed = open(directory.appendingPathComponent("consumed").path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
    guard consumed >= 0 else { throw UpdatePackageError.invalidPackage }; fsync(consumed); close(consumed)
    try job.receipt("ready", directory: directory)
    let deadline = Date().addingTimeInterval(20)
    while kill(job.parentPID, 0) == 0 {
        guard Date() < deadline else { try job.receipt("failed", directory: directory); throw UpdatePackageError.commandTimedOut }
        Thread.sleep(forTimeInterval: 0.05)
    }
    guard job.hasReceipt("handoff", directory: directory) else { try job.receipt("failed", directory: directory); throw UpdatePackageError.invalidPackage }
    let transaction = ApplicationUpdateTransaction(target: UpdateLocations.target)
    do {
        try transaction.install(candidate: candidate, operationDirectory: directory, validate: { try MacUpdatePackage.verifyApp($0, release: job.release, provenance: proof) }, health: {
            let process = try launch(UpdateLocations.target, args: ["--update-health", directory.path, job.nonce])
            var healthy = false
            defer { if !healthy && process.isRunning { process.terminate(); if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit() } }
            let end = Date().addingTimeInterval(15)
            while !job.hasReceipt("health", directory: directory) {
                guard process.isRunning, Date() < end else { throw UpdatePackageError.commandTimedOut }; Thread.sleep(forTimeInterval: 0.05)
            }
            Thread.sleep(forTimeInterval: 2)
            guard process.isRunning else { throw UpdatePackageError.commandFailed }; healthy = true
        })
        try job.receipt("succeeded", directory: directory)
    } catch {
        try? job.receipt("rolledBack", directory: directory); _ = try? launch(UpdateLocations.target, args: []); throw error
    }
} catch { let category = (error as? UpdatePackageError).map { String(describing: $0) } ?? "validation-or-filesystem"; fputs("QuotaBar update failed (\(phase):\(category)); use manual installation if needed.\n", stderr); exit(1) }
