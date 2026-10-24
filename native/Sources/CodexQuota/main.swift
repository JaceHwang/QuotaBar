import AppKit
import ServiceManagement
import QuotaCore

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
if CommandLine.arguments.contains("--startup-status") {
    print(SMAppService.mainApp.status.rawValue)
    exit(0)
}
if CommandLine.arguments.contains("--register-startup") {
    try SMAppService.mainApp.register()
    exit(0)
}
if CommandLine.arguments.contains("--unregister-startup") {
    if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
    exit(0)
}
if Bundle.main.bundleURL.standardizedFileURL.path == UpdateLocations.target.standardizedFileURL.path, !CommandLine.arguments.contains("--update-health"), let directory = try? ApplicationUpdateTransaction.recoveryJob(target: UpdateLocations.target) {
    do {
        let owned = try UpdateLocations.directory(directory.path), helper = owned.appendingPathComponent("QuotaBarUpdater")
        let process = Process(); process.executableURL = helper; process.arguments = ["--recover", owned.path, String(ProcessInfo.processInfo.processIdentifier)]
        try process.run(); exit(0)
    } catch { exit(1) }
}
do { try UpdateLocations.acknowledgeHealth(arguments: CommandLine.arguments, executable: Bundle.main.executableURL?.path ?? "") }
catch { exit(1) }
let coordinator = StandaloneCoordinator()
application.delegate = coordinator
withExtendedLifetime(coordinator) { application.run() }
