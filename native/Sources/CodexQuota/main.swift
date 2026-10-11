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
let coordinator = StandaloneCoordinator()
application.delegate = coordinator
withExtendedLifetime(coordinator) { application.run() }
