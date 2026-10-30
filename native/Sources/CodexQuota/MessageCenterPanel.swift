import AppKit
import QuotaCore

@MainActor final class MessageCenterPanel: NSObject, NSWindowDelegate {
    private(set) var window: NSPanel?
    private var content: MessageCenterView?
    func show(router: AppNotificationRouter, language: CodexDisplayLanguage) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        let copy = ExperienceCopy(language)
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:900,height:600),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title = copy.text("Messages", "消息提醒", "消息提醒"); panel.isReleasedWhenClosed = false; panel.delegate = self
        let view = MessageCenterView(router:router,language:language); panel.contentView = view; content = view; window = panel
        let area = (NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1000,height:720)).insetBy(dx:20,dy:20)
        let titleHeight = panel.frame.height-(panel.contentView?.bounds.height ?? 0)
        panel.setContentSize(NSSize(width:min(900,area.width),height:min(600,max(200,area.height-titleHeight))))
        panel.minSize = NSSize(width:min(680,area.width),height:min(440,area.height))
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification: Notification) { content?.detach(); content = nil; window = nil }
    func close() { content?.detach(); window?.close(); window = nil; content = nil }
}
