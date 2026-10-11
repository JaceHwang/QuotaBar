import CoreFoundation
import Foundation

public enum TokenUsageDecoder {
    public static func decodeResponse(
        _ data: Data,
        receivedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> TokenUsageSnapshot {
        let object = try jsonObject(from: data)
        if let error = object["error"] as? [String: Any] {
            throw errorKind(error)
        }

        let response = object["result"] as? [String: Any] ?? object
        let buckets = try decodeBuckets(response["dailyUsageBuckets"], timeZone: timeZone)
        let summary = try decodeSummary(response["summary"])
        return TokenUsageSnapshot(
            receivedAt: receivedAt,
            dailyBuckets: buckets,
            summary: summary,
            availability: .available
        )
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TokenUsageDecodingError.invalidJSON
            }
            return object
        } catch let error as TokenUsageDecodingError {
            throw error
        } catch {
            throw TokenUsageDecodingError.invalidJSON
        }
    }

    private static func errorKind(_ error: [String: Any]) -> TokenUsageDecodingError {
        error["code"] as? NSNumber == -32601 ? .unsupported : .unavailable
    }

    private static func decodeBuckets(_ value: Any?, timeZone: TimeZone) throws -> [TokenUsageDay] {
        guard value != nil && !(value is NSNull) else {
            return []
        }
        guard let rawBuckets = value as? [Any] else {
            throw TokenUsageDecodingError.invalidJSON
        }
        return try rawBuckets.map { value in
            guard
                let bucket = value as? [String: Any],
                let startDate = bucket["startDate"] as? String,
                let date = normalizedDate(startDate, timeZone: timeZone)
            else {
                throw TokenUsageDecodingError.invalidDate
            }
            guard let tokens = int64(bucket["tokens"]), tokens >= 0 else {
                throw TokenUsageDecodingError.invalidTokens
            }
            return TokenUsageDay(date: date, tokens: tokens, timeZone: timeZone)
        }
    }

    private static func decodeSummary(_ value: Any?) throws -> TokenUsageSummary? {
        guard value != nil && !(value is NSNull) else {
            return nil
        }
        guard let summary = value as? [String: Any] else {
            throw TokenUsageDecodingError.invalidJSON
        }
        return TokenUsageSummary(
            lifetimeTokens: try optionalInt64(summary["lifetimeTokens"]),
            peakDailyTokens: try optionalInt64(summary["peakDailyTokens"]),
            longestRunningTurnSec: try optionalInt(summary["longestRunningTurnSec"]),
            currentStreakDays: try optionalInt(summary["currentStreakDays"]),
            longestStreakDays: try optionalInt(summary["longestStreakDays"])
        )
    }

    private static func optionalInt64(_ value: Any?) throws -> Int64? {
        guard value != nil && !(value is NSNull) else {
            return nil
        }
        guard let number = int64(value), number >= 0 else {
            throw TokenUsageDecodingError.invalidNumber
        }
        return number
    }

    private static func optionalInt(_ value: Any?) throws -> Int? {
        guard value != nil && !(value is NSNull) else {
            return nil
        }
        guard let number = int64(value), number >= 0, number <= Int64(Int.max) else {
            throw TokenUsageDecodingError.invalidNumber
        }
        return Int(number)
    }

    private static func int64(_ value: Any?) -> Int64? {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }

        switch String(cString: number.objCType) {
        case "q":
            return number.int64Value
        case "Q":
            let unsigned = number.uint64Value
            guard unsigned <= UInt64(Int64.max) else {
                return nil
            }
            return Int64(unsigned)
        default:
            let decimal = NSDecimalNumber(decimal: number.decimalValue)
            let minimum = NSDecimalNumber(value: Int64.min)
            let maximum = NSDecimalNumber(value: Int64.max)
            guard
                decimal != .notANumber,
                decimal.compare(minimum) != .orderedAscending,
                decimal.compare(maximum) != .orderedDescending
            else {
                return nil
            }
            let integer = decimal.int64Value
            guard decimal.compare(NSDecimalNumber(value: integer)) == .orderedSame else {
                return nil
            }
            return integer
        }
    }

    private static func normalizedDate(_ value: String, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}
