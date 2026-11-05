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
        let names = language == .english ? ["Quota low", "Bank credits expiring", "Update available"] : language == .traditionalChinese ? ["額度偏低", "Bank 即將到期", "發現新版本"] : ["额度偏低", "Bank 即将到期", "发现新版本"]
        let rows: [MessageCenterRecord] = (0..<count).map { i in
            let categories: [NotificationCategory] = [.quotaLow, .bankExpiring72h, .updateAvailable]
            let body: String
            if language == .english { body = i%3 == 0 ? "5-hour quota remaining 15%. This is the recorded snapshot." : "Earlier reminder snapshot" }
            else if language == .traditionalChinese { body = i%3 == 0 ? "5 小時額度週期剩餘 15%。這是提醒產生時的記錄。" : "歷史訊息內容" }
            else { body = i%3 == 0 ? "5 小时额度周期剩余 15%。这是提醒产生时的记录。" : "历史消息内容" }
            return MessageCenterRecord(key: MessageCenterKey(id: "message-\(i)", epoch: "one"),
                category: categories[i%3], title: names[i%3], body: body,
                createdAtMilliseconds: time-Int64(i*1000), channels: [.bubble, .system])
        }
        XCTAssertTrue(store.append(rows))
        let router = AppNotificationRouter(defaults:UserDefaults(suiteName:"MessageUI.\(UUID())")!);router.bindMessageCenter(store);router.currentMessageEpoch="one";router.openDetails={};router.openUpdates={}
        let view = MessageCenterView(router:router,language:language)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:600),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=view;window.makeKeyAndOrderFront(nil);view.layoutSubtreeIfNeeded()
        return (root,router,view,window)
    }
    private func table(_ view: NSView) throws -> NSTableView { try XCTUnwrap(tree(view).compactMap { $0 as? NSTableView }.first) }
    private func button(_ view: NSView,_ id: String) throws -> NSButton { try XCTUnwrap(tree(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id }) }
    func testUnreadCardAndSelectionFitInsideListViewport() throws {
        let (root,router,view,window)=setup(count:3); defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        view.layoutSubtreeIfNeeded(); let list=try table(view)
        let cell=try XCTUnwrap(list.view(atColumn:0,row:0,makeIfNecessary:true))
        let card=try XCTUnwrap(tree(cell).first { $0.identifier?.rawValue=="messages.row.card" })
        let rect=card.convert(card.bounds,to:list)
        XCTAssertGreaterThanOrEqual(rect.minX,list.visibleRect.minX)
        XCTAssertLessThanOrEqual(rect.maxX,list.visibleRect.maxX - 1,"rounded card must not clip on the right")
    }
    func testUnreadCardReturnsToDefaultAppearanceAfterReadInBothThemes() throws {
        for appearance in [NSAppearance.Name.darkAqua,.aqua] {
            let (root,router,view,window)=setup(count:1)
            defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
            window.appearance=NSAppearance(named:appearance); view.layoutSubtreeIfNeeded(); RunLoop.current.run(until:Date().addingTimeInterval(0.1))
            let list=try table(view)
            func state() throws -> (NSFont, Float) {
                let cell=try XCTUnwrap(list.view(atColumn:0,row:0,makeIfNecessary:true))
                let title=try XCTUnwrap(tree(cell).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue=="messages.row.title" })
                let card=try XCTUnwrap(tree(cell).first { $0.identifier?.rawValue=="messages.row.card" })
                return (try XCTUnwrap(title.font),try XCTUnwrap(card.layer).shadowOpacity)
            }
            let unread=try state(); XCTAssertGreaterThan(unread.1,0,"appearance=\(appearance.rawValue), unread=\(router.messageUnreadCount)")
            list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false); view.layoutSubtreeIfNeeded()
            let read=try state(); XCTAssertEqual(read.1,0); XCTAssertNotEqual(unread.0,read.0)
            XCTAssertEqual(list.numberOfRows,1); XCTAssertEqual(router.messageUnreadCount,0)
        }
    }
    func testUnifiedListKeepsReadAndUnreadRowsAndReadsOnlyTheClickedRecord() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let records=router.messageHistory, list=try table(view)
        XCTAssertTrue(router.markMessageRead(records[2].key)); view.refresh()
        XCTAssertTrue(tree(view).compactMap { $0 as? NSSegmentedControl }.isEmpty, "One list replaces both tabs")
        XCTAssertEqual(list.numberOfRows,3,"Read messages remain beside unread messages")
        list.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        XCTAssertEqual(router.messageUnreadCount,1)
        XCTAssertEqual(list.numberOfRows,3,"Clicking a row does not remove or reorder it")
        XCTAssertEqual(list.selectedRow,1); XCTAssertEqual(view.selectedKey,records[1].key)
        XCTAssertNil(router.messageHistory.first { $0.key==records[0].key }?.readAtMilliseconds)
        XCTAssertNotNil(router.messageHistory.first { $0.key==records[1].key }?.readAtMilliseconds)
    }
    func testEmptyArchiveShowsSingleEmptyStateWithoutReading() throws {
        let (root,router,view,window)=setup(count:0);defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        XCTAssertEqual(try table(view).numberOfRows,0);XCTAssertEqual(router.messageUnreadCount,0);XCTAssertFalse(try button(view,"messages.allRead").isEnabled)
        XCTAssertTrue(tree(view).compactMap { $0 as? NSTextField }.contains { $0.identifier?.rawValue=="messages.empty" && !$0.isHidden })
    }
    func testInitialLoadDoesNotReadAndSelectionReadsOnlyClickedRecord() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let list=try table(view);XCTAssertEqual(list.numberOfRows,3);XCTAssertEqual(list.selectedRow,-1);XCTAssertEqual(router.messageUnreadCount,3)
        let clicked=router.messageHistory[1].key;list.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        XCTAssertEqual(router.messageUnreadCount,2);XCTAssertEqual(list.numberOfRows,3);XCTAssertEqual(list.selectedRow,1);XCTAssertEqual(view.selectedKey,clicked)
        XCTAssertEqual(router.messageHistory.filter { $0.readAtMilliseconds != nil }.map(\.key),[clicked])
        view.refresh();RunLoop.current.run(until:Date().addingTimeInterval(0.02));XCTAssertEqual(router.messageUnreadCount,2)
        XCTAssertEqual(MessageCenterStore(url:root.appendingPathComponent("message-center.json")).unreadCount,2)
    }
    func testAllReadAndNewArrivalPreserveSelectedDetail() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let list=try table(view);list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);let selected=view.selectedKey
        var p=NotificationPolicyPreferences.allSelected();p.enabledChannels=[.bubble];XCTAssertTrue(router.configurePolicy(p))
        router.enqueue(ExperienceNotification(id:"new",kind:.recovery,epoch:"one",title:"新消息",body:"new",createdAt:Date(),category:.quotaRecovered),valid:{true},failed:{})
        XCTAssertEqual(view.selectedKey,selected);XCTAssertEqual(router.messageUnreadCount,3)
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
    func testSingleHistoryReopensAfterBackByClickAndEnter() throws {
        let (root,router,view,window)=setup(count:1)
        defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        window.setContentSize(NSSize(width:700,height:540))
        let list=try table(view)
        let detail=try XCTUnwrap(tree(view).first { $0.identifier?.rawValue=="messages.detailScroll" })
        list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        try button(view,"messages.back").performClick(nil)
        XCTAssertTrue(detail.isHidden);XCTAssertEqual(list.selectedRow,0)
        let point=list.convert(NSPoint(x:30,y:list.rect(ofRow:0).midY),to:nil)
        let click=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1))
        list.mouseDown(with:click);view.layoutSubtreeIfNeeded();XCTAssertFalse(detail.isHidden)
        try button(view,"messages.back").performClick(nil)
        let enter=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36))
        list.keyDown(with:enter);view.layoutSubtreeIfNeeded();XCTAssertFalse(detail.isHidden)
        XCTAssertEqual(router.messageUnreadCount,0);XCTAssertEqual(router.messageHistory.count,1)
    }
    func testDetailShowsExplicitLocalizedCategory() throws {
        let (root,router,view,window)=setup(count:0)
        defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let cases: [(NotificationCategory,String)]=[(.quotaExhausted,"额度耗尽"),(.quotaRecovered,"额度恢复"),(.quotaLow,"额度偏低"),(.bankExpiring72h,"Bank 到期提醒"),(.updateAvailable,"软件有新版本")]
        for (i,item) in cases.enumerated() {
            XCTAssertTrue(router.messageStore!.append(MessageCenterRecord(key:.init(id:"category-\(i)"),category:item.0,title:"通用标题",body:"记录",createdAtMilliseconds:Int64(i),channels:[.bubble])))
            view.refresh();try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            let label=tree(view).compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue=="messages.detail.category" }
            XCTAssertEqual(label?.stringValue,"类别："+item.1)
        }
    }
    func testStorageErrorRetainsTemporaryMessageAndRetryNeverFakesRead() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);let url=root.appendingPathComponent("message-center.json");try Data("broken".utf8).write(to:url)
        let router=AppNotificationRouter(defaults:UserDefaults(suiteName:"MessageUIFailure.\(UUID())")!);defer { router.stop();try? FileManager.default.removeItem(at:root) }
        router.bindMessageCenter(MessageCenterStore(url:url));var p=NotificationPolicyPreferences.allSelected();p.enabledChannels=[.bubble];XCTAssertTrue(router.configurePolicy(p))
        router.enqueue(ExperienceNotification(id:"new",kind:.recovery,epoch:"one",title:"临时消息",body:"snapshot",createdAt:Date(),category:.quotaRecovered),valid:{true},failed:{})
        let view=MessageCenterView(router:router,language:.simplifiedChinese);view.setFrameSize(NSSize(width:900,height:600));view.layoutSubtreeIfNeeded()
        let list=try table(view); list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);XCTAssertEqual(router.messageUnreadCount,1);XCTAssertNotNil(router.messageStorageError)
        let unreadCell=try XCTUnwrap(list.view(atColumn:0,row:0,makeIfNecessary:true)); let unreadCard=try XCTUnwrap(tree(unreadCell).first { $0.identifier?.rawValue=="messages.row.card" })
        XCTAssertGreaterThan(try XCTUnwrap(unreadCard.layer).shadowOpacity,0,"failed write must preserve unread appearance")
        XCTAssertTrue(tree(view).compactMap { $0 as? NSTextField }.contains { $0.identifier?.rawValue=="messages.storageError" && !$0.isHidden })
        try Data(#"{"schema":1,"messages":[]}"#.utf8).write(to:url);try button(view,"messages.retry").performClick(nil)
        XCTAssertNil(router.messageStorageError);XCTAssertEqual(router.messageUnreadCount,1)
        try button(view,"messages.markRead").performClick(nil);XCTAssertEqual(router.messageUnreadCount,0);XCTAssertEqual(MessageCenterStore(url:url).unreadCount,0)
        let readCell=try XCTUnwrap(list.view(atColumn:0,row:0,makeIfNecessary:true)); let readCard=try XCTUnwrap(tree(readCell).first { $0.identifier?.rawValue=="messages.row.card" }); XCTAssertEqual(try XCTUnwrap(readCard.layer).shadowOpacity,0)
    }
    func testLongSnapshotUsesScrollableMeasuredDetailAndSelectionStartsAtTop() throws {
        let (root,router,view,window)=setup();defer { window.close();router.stop();try? FileManager.default.removeItem(at:root) }
        let row=MessageCenterRecord(key:MessageCenterKey(id:"long",epoch:"one"),category:.quotaLow,title:"长消息",body:String(repeating:"这是一条完整的历史消息记录。",count:500),createdAtMilliseconds:Int64(Date().timeIntervalSince1970*1000)+1000,channels:[.bubble])
        XCTAssertTrue(router.messageStore!.append(row));view.refresh();try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded()
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
        window.appearance=NSAppearance(named:.darkAqua);try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded();window.displayIfNeeded()
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
            window.appearance=NSAppearance(named:appearance);try table(view).selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);view.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.06));window.displayIfNeeded()
            for control in tree(view).filter({ $0.identifier?.rawValue.hasPrefix("messages.")==true && !$0.isHiddenOrHasHiddenAncestor && !($0 is NSTableView) }) {
                if control.superview === view { XCTAssertTrue(view.bounds.insetBy(dx:-1,dy:-1).contains(control.frame),"\(control.identifier!.rawValue) outside window") }
            }
            XCTAssertEqual(router.messageUnreadCount,2)
            let rep=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));window.appearance?.performAsCurrentDrawingAppearance { view.cacheDisplay(in:view.bounds,to:rep) }
            let action=try button(view,"messages.allRead"), rect=action.convert(action.bounds,to:view), scale=CGFloat(rep.pixelsWide)/view.bounds.width
            var whitePixels=0, bluePixels=0
            for y in Int((rect.minY+4)*scale)..<Int((rect.maxY-4)*scale) { for x in Int((rect.minX+6)*scale)..<Int((rect.maxX-6)*scale) {
                if let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) {
                    if c.redComponent>0.85 && c.greenComponent>0.85 && c.blueComponent>0.85 { whitePixels += 1 }
                    if c.blueComponent>0.45 && c.blueComponent>c.redComponent*1.4 && c.blueComponent>c.greenComponent*1.1 { bluePixels += 1 }
                }
            } }
            XCTAssertGreaterThan(bluePixels,100,"Test must sample the blue all-read button in \(language.rawValue), \(appearance.rawValue)")
            XCTAssertGreaterThan(whitePixels,20,"All-read label must be visible in \(language.rawValue), \(appearance.rawValue)")
            if let dir=ProcessInfo.processInfo.environment["QUOTABAR_TEST_ARTIFACTS"] {
                try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
                try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:dir).appendingPathComponent("message-center-\(language.rawValue)-\(appearance.rawValue).png"))
            }
        } }
    }
}
