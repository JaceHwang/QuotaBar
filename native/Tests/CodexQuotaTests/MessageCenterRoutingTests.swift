import AppKit
import XCTest
import QuotaCore
@testable import CodexQuota
@MainActor final class MessageCenterRoutingTests: XCTestCase {
    func testAllRealCategoriesAndMultiChannelCaptureWithReadRestartNoReplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), url = root.appendingPathComponent("message-center.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let router = AppNotificationRouter(defaults: UserDefaults(suiteName: "MessageRoute.\(UUID())")!); defer { router.stop() }
        router.bindMessageCenter(MessageCenterStore(url: url)); var p = NotificationPolicyPreferences.allSelected(); p.enabledChannels = [.system,.mobile]; XCTAssertTrue(router.configurePolicy(p))
        var sends = 0; router.sendSystem = { _,done in sends += 1; done(true) }
        let categories: [NotificationCategory] = [.quotaExhausted,.quotaRecovered,.quotaLow,.bankExpiring72h,.updateAvailable]
        for category in categories {
            let kind: ExperienceNotificationKind = category == .updateAvailable ? .update : category == .bankExpiring72h ? .bank : .recovery
            let m = ExperienceNotification(id: category.rawValue, kind: kind, epoch: "one", title: category.rawValue, body: "snapshot", createdAt: Date(), category: category, reminderThreshold: category == .quotaLow ? 20 : category == .bankExpiring72h ? 72 : nil)
            router.enqueue(m,valid:{true},failed:{})
        }
        XCTAssertEqual(router.messageHistory.count,5); XCTAssertEqual(router.messageUnreadCount,5); XCTAssertEqual(sends,5)
        XCTAssertTrue(router.messageHistory.allSatisfy { $0.channels == [.system,.mobile] })
        let first = try XCTUnwrap(router.messageHistory.first)
        XCTAssertTrue(router.markMessageRead(first.key)); XCTAssertEqual(router.messageUnreadCount,4)
        router.cancelAuthenticationEpoch("one"); router.stop()
        let restored = AppNotificationRouter(defaults: UserDefaults(suiteName:"Restored.\(UUID())")!); defer { restored.stop() }
        var newSends = 0; restored.sendSystem = { _,done in newSends += 1; done(true) }; restored.presentBubble = { _ in newSends += 1; return true }
        restored.bindMessageCenter(MessageCenterStore(url: url)); restored.updateEnvironment(canPresent:true)
        XCTAssertEqual(restored.messageHistory.count,5); XCTAssertEqual(restored.messageUnreadCount,4); XCTAssertEqual(newSends,0)
        var opened = 0; restored.openDetails = { opened += 1 }
        restored.openMessageLatest(try XCTUnwrap(restored.messageHistory.first { $0.category == .quotaLow }))
        XCTAssertEqual(opened,1); XCTAssertEqual(newSends,0)
        XCTAssertTrue(restored.markAllMessagesRead()); XCTAssertEqual(MessageCenterStore(url:url).unreadCount,0)
    }
    func testPauseMobileOnlyAllOffPreviewAndGenerationCapture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
        let router = AppNotificationRouter(defaults:UserDefaults(suiteName:"MsgChannels.\(UUID())")!); defer { router.stop() }
        router.bindMessageCenter(MessageCenterStore(url:root.appendingPathComponent("message-center.json")))
        var p = NotificationPolicyPreferences.allSelected(); p.enabledChannels = [.bubble]; p.bubblePausedUntil = Date().addingTimeInterval(3600); XCTAssertTrue(router.configurePolicy(p))
        let m = ExperienceNotification(id:"paused",kind:.recovery,epoch:"one",title:"real",body:"snapshot",createdAt:Date(),category:.quotaRecovered)
        router.enqueue(m,valid:{true},failed:{})
        XCTAssertEqual(router.messageHistory.count,1); XCTAssertEqual(router.messageUnreadCount,1)
        router.updateEnvironment(canPresent:true); router.presentBubble = { _ in true }; _ = router.preview(m)
        router.sendTestNotification(title:"test",body:"example"); XCTAssertEqual(router.messageHistory.count,1)
        p.enabledChannels = [.mobile]; XCTAssertTrue(router.configurePolicy(p))
        router.enqueue(ExperienceNotification(id:"mobile",kind:.update,epoch:nil,title:"update",body:"snapshot",createdAt:Date(),category:.updateAvailable),valid:{true},failed:{})
        XCTAssertEqual(router.messageHistory.count,2); XCTAssertEqual(router.messageHistory.first { $0.key.id == "mobile" }?.channels,[.mobile])
        router.cancelMessage(id:"mobile")
        router.enqueue(ExperienceNotification(id:"mobile",kind:.update,epoch:nil,title:"update",body:"snapshot",createdAt:Date(),reminderGeneration:"later",category:.updateAvailable),valid:{true},failed:{})
        XCTAssertEqual(router.messageHistory.count,3)
        p.enabledChannels = []; XCTAssertTrue(router.configurePolicy(p)); router.enqueue(ExperienceNotification(id:"off",kind:.recovery,epoch:"one",title:"off",body:"",createdAt:Date(),category:.quotaRecovered),valid:{true},failed:{})
        XCTAssertEqual(router.messageHistory.count,3)
    }
    func testHistoryFailureDoesNotSuppressRealDeliveryOrOverwriteUnknownFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); let url=root.appendingPathComponent("message-center.json"); try Data("broken".utf8).write(to:url)
        let router = AppNotificationRouter(defaults:UserDefaults(suiteName:"MsgFailure.\(UUID())")!); defer { router.stop() }
        router.bindMessageCenter(MessageCenterStore(url:url)); var p=NotificationPolicyPreferences.allSelected();p.enabledChannels=[.system];XCTAssertTrue(router.configurePolicy(p))
        var sends=0;router.sendSystem={_,done in sends += 1;done(true)}
        router.enqueue(ExperienceNotification(id:"live",kind:.recovery,epoch:"one",title:"live",body:"",createdAt:Date(),category:.quotaRecovered),valid:{true},failed:{})
        XCTAssertEqual(sends,1);XCTAssertEqual(router.messageUnreadCount,1);XCTAssertNotNil(router.messageStorageError)
        XCTAssertFalse(router.markAllMessagesRead());XCTAssertEqual(try String(contentsOf:url,encoding:.utf8),"broken")
        try Data(#"{"schema":1,"messages":[]}"#.utf8).write(to:url);XCTAssertTrue(router.retryMessageStorage());XCTAssertEqual(router.messageHistory.count,1);XCTAssertNil(router.messageStorageError)
    }
}
