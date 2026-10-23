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
do { try UpdateLocations.acknowledgeHealth(arguments: CommandLine.arguments, executable: Bundle.main.executableURL?.path ?? "") }
catch { exit(1) }
let coordinator = StandaloneCoordinator()
application.delegate = coordinator
withExtendedLifetime(coordinator) { application.run() }
