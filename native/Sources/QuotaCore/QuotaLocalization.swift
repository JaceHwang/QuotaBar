import Foundation

public struct QuotaLocalization: Sendable {
    public let language: CodexDisplayLanguage

    public init(language: CodexDisplayLanguage) {
        self.language = language
    }

    public var locale: Locale {
        switch language {
        case .simplifiedChinese:
            Locale(identifier: "zh_CN")
        case .traditionalChinese:
            Locale(identifier: "zh_TW")
        case .english:
            Locale(identifier: "en_US_POSIX")
        }
    }

    public var title: String {
        switch language {
        case .simplifiedChinese: "Codex 剩余额度"
        case .traditionalChinese: "Codex 剩餘額度"
        case .english: "Codex quota"
        }
    }

    public var plan: String {
        switch language {
        case .simplifiedChinese: "套餐"
        case .traditionalChinese: "方案"
        case .english: "Plan"
        }
    }

    public var quotaWindow: String {
        switch language {
        case .simplifiedChinese: "额度周期"
        case .traditionalChinese: "額度週期"
        case .english: "Quota window"
        }
    }

    public var primaryQuotaWindow: String {
        switch language {
        case .simplifiedChinese: "5 小时"
        case .traditionalChinese: "5 小時"
        case .english: "5 hours"
        }
    }

    public var secondaryQuotaWindow: String {
        switch language {
        case .simplifiedChinese: "额度周期（7天）"
        case .traditionalChinese: "額度週期（7天）"
        case .english: "Quota window (7 days)"
        }
    }

    public var secondaryQuotaWindowValue: String {
        switch language {
        case .simplifiedChinese: "7 天"
        case .traditionalChinese: "7 天"
        case .english: "7 days"
        }
    }

    public var secondaryNextReset: String {
        switch language {
        case .simplifiedChinese: "下次重置（7天）"
        case .traditionalChinese: "下次重設（7天）"
        case .english: "Next reset (7 days)"
        }
    }

    public var nextReset: String {
        switch language {
        case .simplifiedChinese: "下次重置"
        case .traditionalChinese: "下次重設"
        case .english: "Next reset"
        }
    }

    public var primaryNextReset: String {
        switch language {
        case .simplifiedChinese: "下次重置（5小时）"
        case .traditionalChinese: "下次重設（5小時）"
        case .english: "Next reset (5 hours)"
        }
    }

    public var resizeHeight: String {
        switch language {
        case .simplifiedChinese: "调整高度"
        case .traditionalChinese: "調整高度"
        case .english: "Adjust height"
        }
    }



    public var settings: String {
        switch language {
        case .simplifiedChinese: "设置"
        case .traditionalChinese: "設定"
        case .english: "Settings"
        }
    }

    public var lockDetailWindow: String {
        switch language {
        case .simplifiedChinese, .traditionalChinese: "固定浮窗"
        case .english: "Keep popover open"
        }
    }

    public var unlockDetailWindow: String {
        switch language {
        case .simplifiedChinese, .traditionalChinese: "取消固定浮窗"
        case .english: "Stop keeping popover open"
        }
    }

    public var checkForUpdates: String {
        switch language {
        case .simplifiedChinese: "检查更新"
        case .traditionalChinese: "檢查更新"
        case .english: "Check for Updates"
        }
    }

    public var reloadCompanion: String {
        switch language {
        case .simplifiedChinese: "重新加载"
        case .traditionalChinese: "重新載入"
        case .english: "Reload"
        }
    }

    public var quitCompanion: String {
        switch language {
        case .simplifiedChinese: "退出应用"
        case .traditionalChinese: "結束應用程式"
        case .english: "Quit App"
        }
    }







    public var bankAvailable: String {
        switch language {
        case .simplifiedChinese: "Bank 可用重置"
        case .traditionalChinese: "Bank 可用重設"
        case .english: "Bank resets available"
        }
    }

    public func bankExpiryLabel(_ index: Int) -> String {
        switch language {
        case .simplifiedChinese: "Bank \(index)到期时间"
        case .traditionalChinese: "Bank \(index)到期時間"
        case .english: "Bank \(index) expires"
        }
    }

    public var bankDetails: String {
        switch language {
        case .simplifiedChinese: "Bank 明细"
        case .traditionalChinese: "Bank 詳情"
        case .english: "Bank details"
        }
    }

    public var updated: String {
        switch language {
        case .simplifiedChinese: "数据更新"
        case .traditionalChinese: "資料更新"
        case .english: "Updated"
        }
    }

    public var tokenUsageTitle: String {
        switch language {
        case .simplifiedChinese, .traditionalChinese: "Token 用量"
        case .english: "Token usage"
        }
    }

    public func remainingSummary(_ percent: Int) -> String {
        switch language {
        case .simplifiedChinese: "剩余 \(percent)%"
        case .traditionalChinese: "剩餘 \(percent)%"
        case .english: "Remaining \(percent)%"
        }
    }

    public func tokenUsageTotal(_ tokens: String) -> String {
        switch language {
        case .simplifiedChinese: "本周期总计 \(tokens) tokens"
        case .traditionalChinese: "本週期總計 \(tokens) tokens"
        case .english: "Current period total \(tokens) tokens"
        }
    }

    public var tokenUsageDelayNote: String {
        switch language {
        case .simplifiedChinese: "使用数据最多可能延迟 6 小时"
        case .traditionalChinese: "使用資料最多可能延遲 6 小時"
        case .english: "Usage data may be delayed by up to 6 hours"
        }
    }

    public var tokenUsageUnavailable: String {
        switch language {
        case .simplifiedChinese: "本周期 Token 用量暂不可用"
        case .traditionalChinese: "本週期 Token 用量暫不可用"
        case .english: "Current-period token usage is unavailable"
        }
    }

    public func tokenUsageDayLabel(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = language == .english ? "MMM d" : "M月d日"
        return formatter.string(from: date)
    }

    public func compactTokenCount(_ tokens: Int64) -> String {
        let magnitude: (value: Double, suffix: String)
        switch tokens {
        case 1_000_000_000...:
            magnitude = (Double(tokens) / 1_000_000_000, "B")
        case 1_000_000...:
            magnitude = (Double(tokens) / 1_000_000, "M")
        case 1_000...:
            magnitude = (Double(tokens) / 1_000, "K")
        default:
            return String(tokens)
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: magnitude.value)) ?? String(magnitude.value))\(magnitude.suffix)"
    }

    public var tiboXTitle: String {
        switch language {
        case .simplifiedChinese: "Tibo 的 X 动态"
        case .traditionalChinese: "Tibo 的 X 動態"
        case .english: "Tibo on X"
        }
    }

    public var tiboXAccessibilityLabel: String {
        switch language {
        case .simplifiedChinese: "在浏览器中打开 Tibo 的 X 主页"
        case .traditionalChinese: "在瀏覽器中開啟 Tibo 的 X 主頁"
        case .english: "Open Tibo's X profile in the browser"
        }
    }

    public var noData: String {
        switch language {
        case .simplifiedChinese: "暂无数据"
        case .traditionalChinese: "暫無資料"
        case .english: "No data"
        }
    }

    public var unlimited: String {
        switch language {
        case .simplifiedChinese: "无限"
        case .traditionalChinese: "無限"
        case .english: "Unlimited"
        }
    }

    public var available: String {
        switch language {
        case .simplifiedChinese: "可用"
        case .traditionalChinese: "可用"
        case .english: "Available"
        }
    }

    public var none: String {
        switch language {
        case .simplifiedChinese: "无"
        case .traditionalChinese: "無"
        case .english: "None"
        }
    }

    public var noExpiry: String {
        switch language {
        case .simplifiedChinese: "未提供到期时间"
        case .traditionalChinese: "未提供到期時間"
        case .english: "No expiry provided"
        }
    }

    public var used: String {
        switch language {
        case .simplifiedChinese: "已使用"
        case .traditionalChinese: "已使用"
        case .english: "Used"
        }
    }

    public var expired: String {
        switch language {
        case .simplifiedChinese: "已过期"
        case .traditionalChinese: "已過期"
        case .english: "Expired"
        }
    }

    public var justNow: String {
        switch language {
        case .simplifiedChinese: "刚刚"
        case .traditionalChinese: "剛剛"
        case .english: "Just now"
        }
    }

    public var detailDateFormat: String {
        language == .english ? "MMM d, HH:mm" : "M月d日 HH:mm"
    }

    public var resetTimestampDateFormat: String { "yyyy/MM/dd HH:mm" }

    public var fullIndicatorDateFormat: String {
        detailDateFormat
    }

    public var openingParenthesis: String {
        language == .english ? " (" : "（"
    }

    public var closingParenthesis: String {
        language == .english ? ")" : "）"
    }

    public var pastSuffix: String {
        language == .english ? " ago" : "前"
    }

    public func bankCount(_ count: Int) -> String {
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            "\(count) 次"
        case .english:
            "\(count) \(count == 1 ? "reset" : "resets")"
        }
    }

    public func period(minutes: Int) -> String {
        if minutes.isMultiple(of: 1_440) {
            return duration(
                minutes / 1_440,
                simplified: "天",
                traditional: "天",
                english: "day"
            )
        }
        if minutes.isMultiple(of: 60) {
            return duration(
                minutes / 60,
                simplified: "小时",
                traditional: "小時",
                english: "hour"
            )
        }
        return duration(
            minutes,
            simplified: "分钟",
            traditional: "分鐘",
            english: "minute"
        )
    }

    public func freshness(minutes: Int) -> String {
        switch language {
        case .simplifiedChinese:
            "\(minutes) 分钟前"
        case .traditionalChinese:
            "\(minutes) 分鐘前"
        case .english:
            "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago"
        }
    }

    public func freshness(hours: Int) -> String {
        switch language {
        case .simplifiedChinese:
            "\(hours) 小时前"
        case .traditionalChinese:
            "\(hours) 小時前"
        case .english:
            "\(hours) \(hours == 1 ? "hour" : "hours") ago"
        }
    }

    private func duration(
        _ value: Int,
        simplified: String,
        traditional: String,
        english: String
    ) -> String {
        switch language {
        case .simplifiedChinese:
            "\(value) \(simplified)"
        case .traditionalChinese:
            "\(value) \(traditional)"
        case .english:
            "\(value) \(english)\(value == 1 ? "" : "s")"
        }
    }
}
