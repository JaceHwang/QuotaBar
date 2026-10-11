import CoreFoundation
import Foundation

public enum RateLimitDecoder {
    public static func decodeResponse(
        _ data: Data,
        receivedAt: Date = Date()
    ) throws -> AllowanceSnapshot {
        let object = try jsonObject(from: data)
        let response = dictionary(object["result"]) ?? object
        return try decodeContainer(response, receivedAt: receivedAt)
    }

    public static func decodeNotification(
        _ data: Data,
        receivedAt: Date = Date()
    ) throws -> AllowanceSnapshot {
        let object = try jsonObject(from: data)
        guard
            object["method"] as? String == "account/rateLimits/updated",
            let params = dictionary(object["params"])
        else {
            throw RateLimitDecodingError.missingCodexBucket
        }
        return try decodeContainer(params, receivedAt: receivedAt)
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RateLimitDecodingError.invalidJSON
            }
            return object
        } catch let error as RateLimitDecodingError {
            throw error
        } catch {
            throw RateLimitDecodingError.invalidJSON
        }
    }

    private static func decodeContainer(
        _ container: [String: Any],
        receivedAt: Date
    ) throws -> AllowanceSnapshot {
        let bucket: [String: Any]?

        if
            let buckets = dictionary(container["rateLimitsByLimitId"]),
            let codex = dictionary(buckets["codex"])
        {
            bucket = codex
        } else if let direct = dictionary(container["rateLimits"]) {
            let limitID = direct["limitId"] as? String
            bucket = limitID == nil || limitID == "codex" ? direct : nil
        } else if dictionary(container["primary"]) != nil {
            bucket = container
        } else {
            bucket = nil
        }

        guard
            let bucket,
            let primary = dictionary(bucket["primary"])
        else {
            throw RateLimitDecodingError.missingCodexBucket
        }
        guard let usedPercent = double(primary["usedPercent"]) else {
            throw RateLimitDecodingError.missingUsedPercent
        }
        guard let resetTimestamp = double(primary["resetsAt"]) else {
            throw RateLimitDecodingError.missingResetTime
        }
        guard usedPercent.isFinite, resetTimestamp.isFinite, resetTimestamp > 0 else {
            throw RateLimitDecodingError.invalidNumber
        }

        let clampedRemaining = min(100.0, max(0.0, 100.0 - usedPercent))
        let windowDurationMins = integer(primary["windowDurationMins"])
        let planType = bucket["planType"] as? String
        let credits = decodeCredits(bucket["credits"])
        let bank = decodeBank(container["rateLimitResetCredits"])
        let secondary = decodeWindow(dictionary(bucket["secondary"]))

        return AllowanceSnapshot(
            usedPercent: usedPercent,
            remainingPercent: Int(clampedRemaining.rounded()),
            resetsAt: Date(timeIntervalSince1970: resetTimestamp),
            receivedAt: receivedAt,
            windowDurationMins: windowDurationMins,
            planType: planType,
            credits: credits,
            bank: bank,
            secondary: secondary
        )
    }

    private static func decodeWindow(
        _ window: [String: Any]?
    ) -> QuotaWindowSnapshot? {
        guard
            let window,
            let usedPercent = double(window["usedPercent"]),
            let resetTimestamp = double(window["resetsAt"]),
            usedPercent.isFinite,
            resetTimestamp.isFinite,
            resetTimestamp > 0
        else {
            return nil
        }
        let clampedRemaining = min(100.0, max(0.0, 100.0 - usedPercent))
        return QuotaWindowSnapshot(
            usedPercent: usedPercent,
            remainingPercent: Int(clampedRemaining.rounded()),
            resetsAt: Date(timeIntervalSince1970: resetTimestamp),
            windowDurationMins: integer(window["windowDurationMins"])
        )
    }

    private static func decodeCredits(_ value: Any?) -> CreditBalance? {
        guard let object = dictionary(value) else {
            return nil
        }
        return CreditBalance(
            hasCredits: object["hasCredits"] as? Bool ?? false,
            unlimited: object["unlimited"] as? Bool ?? false,
            balance: object["balance"] as? String
        )
    }

    private static func decodeBank(_ value: Any?) -> BankResetSummary? {
        guard
            let object = dictionary(value),
            let rawCount = integer(object["availableCount"])
        else {
            return nil
        }

        let details: [BankResetCredit]?
        if object["credits"] is NSNull || object["credits"] == nil {
            details = nil
        } else if let objects = object["credits"] as? [Any] {
            details = objects.compactMap { value in
                guard let detail = dictionary(value) else {
                    return nil
                }
                return BankResetCredit(
                    status: detail["status"] as? String,
                    grantedAt: date(detail["grantedAt"]),
                    expiresAt: date(detail["expiresAt"]),
                    title: detail["title"] as? String,
                    description: detail["description"] as? String
                )
            }
        } else {
            details = nil
        }

        return BankResetSummary(availableCount: max(0, rawCount), credits: details)
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func integer(_ value: Any?) -> Int? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        return number.doubleValue
    }

    private static func date(_ value: Any?) -> Date? {
        guard
            let timestamp = double(value),
            timestamp.isFinite,
            timestamp > 0
        else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}
