import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota
@MainActor final class MessageCenterSettingsTests: XCTestCase {
    private func tree(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(tree) }
    private func setup(_ language: CodexDisplayLanguage = .simplifiedChinese, count: Int = 3) -> (URL, AppNotificationRouter, MessageCenterView, NSWindow) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MessageCenterStore(url: root.appendingPathComponent("message-center.json"))
        let time = Int64(Date().timeIntervalSince1970 * 1000)
        let names = ["额度偏低", "Bank 即将到期", "发现新版本"]
        let rows = (0..<count).map { i in MessageCenterRecord(key:MessageCenterKey(id:"message-\(i)",epoch:"one"),category:i%3 == 0 ? .quotaLow : i%3 == 1 ? .bankExpiring72h : .updateAvailable,title:names[i%3],body:i%3 == 0 ? "5 小时额度周期剩余 15%。这是提醒产生时的记录。" : "历史消息内容",createdAtMilliseconds:time-Int64(i*1000),channels:[.bubble,.system]) }
        XCTAssertTrue(store.append(rows))
        let router = AppNotificationRouter(defaults:UserDefaults(suiteName:"MessageUI.\(UUID())")!);router.bindMessageCenter(store);router.currentMessageEpoch="one";router.openDetails={};router.openUpdates={}
        let view = MessageCenterView(router:router,language:language)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:600),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;window.makeKeyAndOrderFront(nil);view.layoutSubtreeIfNeeded()
        return (root,router,view,window)
    }
    private func table(_ view: NSView) throws -> NSTableView { try XCTUnwrap(tree(view).compactMap { $0 as? NSTableView }.first) }
    private func tabs(_ view: NSView) throws -> NSSegmentedControl { try XCTUnwrap(tree(view).compactMap { $0 as? NSSegmentedControl }.first) }
    private func button(_ view: NSView,_ id: String) throws -> NSButton { try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id }) }
    private func switchHistory(_ view: NSView) throws { let t=try tabs(view);t.selectedSegment=1;NSApp.sendAction(t.action!,to:t.target,from:t) }
    func testEmptyArchiveShowsBothEmptyStatesWithoutReading() throws {
        let (root,router,view,window)=setup(count:0);defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        XCTAssertEqual(try table(view).numberOfRows,0);XCTAssertEqual(router.messageUnreadCount,0);XCTAssertFalse(try button(view,"messages.allRead").isEnabled)
        try switchHistory(view);XCTAssertEqual(try table(view).numberOfRows,0)
        XCTAssertTrue(tree(view).compactMap { $0 as? NSTextField }.contains { $0.identifier?.rawValue=="messages.empty" && !$0.isHidden })
    }
    func testInitialAndTabChangesDoNotReadButUserSelectionReadsOnlyClickedRecord() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let list=try table(view);XCTAssertEqual(list.numberOfRows,3);XCTAssertEqual(list.selectedRow,-1);XCTAssertEqual(router.messageUnreadCount,3)
        try switchHistory(view);XCTAssertEqual(router.messageUnreadCount,3)
        let t=try tabs(view);t.selectedSegment=0;NSApp.sendAction(t.action!,to:t.target,from:t)
        let clicked=router.messageHistory[1].key;list.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        XCTAssertEqual(router.messageUnreadCount,2);XCTAssertEqual(list.numberOfRows,2);XCTAssertEqual(list.selectedRow,-1);XCTAssertEqual(view.selectedKey,clicked)
        XCTAssertEqual(router.messageHistory.filter { $0.readAtMilliseconds != nil }.map(\.key),[clicked])
        view.refresh();RunLoop.current.run(until:Date().addingTimeInterval(0.02));XCTAssertEqual(router.messageUnreadCount,2)
        try switchHistory(view);XCTAssertEqual(list.numberOfRows,3);XCTAssertEqual(router.messageUnreadCount,2)
        XCTAssertEqual(MessageCenterStore(url:root.appendingPathComponent("message-center.json")).unreadCount,2)
    }
    func testAllReadAndNewArrivalPreserveDetailAndTab() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        try switchHistory(view);let list=try table(view);list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);let selected=view.selectedKey
        var p=NotificationPolicyPreferences.allSelected();p.enabledChannels=[.bubble];XCTAssertTrue(router.configurePolicy(p))
        router.enqueue(ExperienceNotification(id:"new",kind:.recovery,epoch:"one",title:"新消息",body:"new",createdAt:Date(),category:.quotaRecovered),valid:{true},failed:{})
        XCTAssertEqual(try tabs(view).selectedSegment,1);XCTAssertEqual(view.selectedKey,selected);XCTAssertEqual(router.messageUnreadCount,3)
        try button(view,"messages.allRead").performClick(nil);XCTAssertEqual(router.messageUnreadCount,0);XCTAssertEqual(list.numberOfRows,4);XCTAssertEqual(view.selectedKey,selected)
        XCTAssertFalse(try button(view,"messages.allRead").isEnabled)
    }
    func testNarrowLayoutBackAndHistoryEpochKeepSafeDetails() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        window.setContentSize(NSSize(width:700,height:540));view.layoutSubtreeIfNeeded()
        let scrolls=tree(view).compactMap { $0 as? NSScrollView };let list=try XCTUnwrap(scrolls.first { $0.identifier?.rawValue=="messages.listScroll" });let detail=try XCTUnwrap(scrolls.first { $0.identifier?.rawValue=="messages.detailScroll" })
        XCTAssertFalse(list.isHidden);XCTAssertTrue(detail.isHidden)
        try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded()
        XCTAssertTrue(list.isHidden);XCTAssertFalse(detail.isHidden);XCTAssertFalse(try button(view,"messages.back").isHidden)
        XCTAssertEqual(try button(view,"messages.back").frame.height,30,accuracy:0.1)
        router.currentMessageEpoch="later"
        XCTAssertTrue(tree(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("历史会话") })
        var opened=0;router.openDetails={opened += 1};try button(view,"messages.latest").performClick(nil);XCTAssertEqual(opened,1)
        try button(view,"messages.back").performClick(nil);view.layoutSubtreeIfNeeded();XCTAssertFalse(list.isHidden);XCTAssertTrue(detail.isHidden)
        XCTAssertEqual(router.messageHistory.count,3)
    }
    func testStorageErrorRetainsTemporaryMessageAndRetryNeverFakesRead() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);let url=root.appendingPathComponent("message-center.json");try Data("broken".utf8).write(to:url)
        let router=AppNotificationRouter(defaults:UserDefaults(suiteName:"MessageUIFailure.\(UUID())")!);defer { router.stop();try? FileManager.default.removeItem(at:root) }
        router.bindMessageCenter(MessageCenterStore(url:url));var p=NotificationPolicyPreferences.allSelected();p.enabledChannels=[.bubble];XCTAssertTrue(router.configurePolicy(p))
        router.enqueue(ExperienceNotification(id:"new",kind:.recovery,epoch:"one",title:"临时消息",body:"snapshot",createdAt:Date(),category:.quotaRecovered),valid:{true},failed:{})
        let view=MessageCenterView(router:router,language:.simplifiedChinese);view.setFrameSize(NSSize(width:900,height:600));view.layoutSubtreeIfNeeded()
        try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);XCTAssertEqual(router.messageUnreadCount,1);XCTAssertNotNil(router.messageStorageError)
        XCTAssertTrue(tree(view).compactMap { $0 as? NSTextField }.contains { $0.identifier?.rawValue=="messages.storageError" && !$0.isHidden })
        try Data(#"{"schema":1,"messages":[]}"#.utf8).write(to:url);try button(view,"messages.retry").performClick(nil)
        XCTAssertNil(router.messageStorageError);XCTAssertEqual(router.messageUnreadCount,1)
        try button(view,"messages.markRead").performClick(nil);XCTAssertEqual(router.messageUnreadCount,0);XCTAssertEqual(MessageCenterStore(url:url).unreadCount,0)
    }
    func testLongSnapshotUsesScrollableMeasuredDetailAndSelectionStartsAtTop() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let row=MessageCenterRecord(key:MessageCenterKey(id:"long",epoch:"one"),category:.quotaLow,title:"长消息",body:String(repeating:"这是一条完整的历史消息记录。",count:500),createdAtMilliseconds:Int64(Date().timeIntervalSince1970*1000)+1000,channels:[.bubble])
        XCTAssertTrue(router.messageStore!.append(row));view.refresh();try switchHistory(view);try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded()
        let scroll=try XCTUnwrap(tree(view).compactMap { $0 as? NSScrollView }.first { $0.identifier?.rawValue=="messages.detailScroll" })
        let body=try XCTUnwrap(tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue=="messages.detail.body" })
        XCTAssertGreaterThan(scroll.documentView!.bounds.height,scroll.contentSize.height);XCTAssertGreaterThan(body.bounds.height,500)
        scroll.contentView.scroll(to:NSPoint(x:0,y:400));try table(view).selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);view.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.contentView.bounds.minY,0,accuracy:1)
    }
    func testTenThousandRowsUseNativeVirtualization() throws {
        let (root,router,view,window)=setup(count:10_000);defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let list=try table(view);XCTAssertEqual(list.numberOfRows,10_000)
        XCTAssertNil(list.view(atColumn:0,row:9999,makeIfNecessary:false));XCTAssertLessThan(tree(view).compactMap { $0 as? NSTextField }.count,200)
    }
    func testEnabledAccentLabelRemainsVisibleAfterDarkAppearanceChange() throws {
        let (root,router,view,window)=setup(.english);defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        window.appearance=NSAppearance(named:.darkAqua);try switchHistory(view);try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded();window.displayIfNeeded()
        let control=try button(view,"messages.allRead")
        let rep=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));window.appearance?.performAsCurrentDrawingAppearance { view.cacheDisplay(in:view.bounds,to:rep) }
        let scale=CGFloat(rep.pixelsWide)/view.bounds.width;let rect=control.convert(control.bounds,to:view)
        var whites=0
        for y in Int(rect.minY*scale)..<Int(rect.maxY*scale) { for x in Int(rect.minX*scale)..<Int(rect.maxX*scale) {
            if let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),c.redComponent>0.85,c.greenComponent>0.85,c.blueComponent>0.85 { whites += 1 }
        } }
        XCTAssertGreaterThan(whites,20,"enabled action must retain visible white label on dark appearance")
    }
    func testThreeLanguagesAndThemesRenderWithoutClippingAndKeepSelectedHistory() throws {
        for language in [CodexDisplayLanguage.english,.simplifiedChinese,.traditionalChinese] { for appearance in [NSAppearance.Name.aqua,.darkAqua] {
            let (root,router,view,window)=setup(language);defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
            window.appearance=NSAppearance(named:appearance);try switchHistory(view);try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.06));window.displayIfNeeded()
            for control in tree(view).filter({ $0.identifier?.rawValue.hasPrefix("messages.")==true && !$0.isHiddenOrHasHiddenAncestor && !($0 is NSTableView) }) {
                if control.superview === view { XCTAssertTrue(view.bounds.insetBy(dx:-1,dy:-1).contains(control.frame),"\(control.identifier!.rawValue) outside window") }
            }
            XCTAssertEqual(router.messageUnreadCount,2)
            if let dir=ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
                let rep=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));window.appearance?.performAsCurrentDrawingAppearance { view.cacheDisplay(in:view.bounds,to:rep) }
                try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:dir).appendingPathComponent("message-center-\(language.rawValue)-\(appearance.rawValue).png"))
            }
        } }
    }
}
