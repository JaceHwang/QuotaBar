import Foundation

public enum QuotaCountdownSegmentRole: Equatable, Sendable {
    case plain
    case punctuation
    case digits
    case unit
    case suffix
}

public struct QuotaCountdownSegment: Equatable, Sendable {
    public let text: String
    public let role: QuotaCountdownSegmentRole

    public init(text: String, role: QuotaCountdownSegmentRole) {
        self.text = text
        self.role = role
    }
}

public enum QuotaCountdownSegmenter {
    private struct Candidate {
        let openingRange: Range<String.Index>
        let closingRange: Range<String.Index>
        let intervalSegments: [QuotaCountdownSegment]
    }

    public static func segments(in value: String) -> [QuotaCountdownSegment] {
        if let resetSegments = resetPrefixSegments(in: value) {
            return resetSegments
        }
        let pairs = [(opening: "（", closing: "）"), (opening: "(", closing: ")")]
        let candidates = pairs.compactMap { pair -> Candidate? in
            guard
                let openingRange = value.range(
                    of: pair.opening,
                    options: .backwards
                ),
                let closingRange = value.range(
                    of: pair.closing,
                    range: openingRange.upperBound..<value.endIndex
                )
            else {
                return nil
            }

            let interval = String(
                value[openingRange.upperBound..<closingRange.lowerBound]
            )
            guard let intervalSegments = intervalSegments(in: interval) else {
                return nil
            }
            return Candidate(
                openingRange: openingRange,
                closingRange: closingRange,
                intervalSegments: intervalSegments
            )
        }
        guard let candidate = candidates.max(by: {
            $0.openingRange.lowerBound < $1.openingRange.lowerBound
        }) else {
            return [.init(text: value, role: .plain)]
        }

        var result: [QuotaCountdownSegment] = []
        append(
            String(value[..<candidate.openingRange.lowerBound]),
            role: .plain,
            to: &result
        )
        append(
            String(value[candidate.openingRange]),
            role: .punctuation,
            to: &result
        )
        for segment in candidate.intervalSegments {
            append(segment.text, role: segment.role, to: &result)
        }
        append(
            String(value[candidate.closingRange]),
            role: .punctuation,
            to: &result
        )
        append(
            String(value[candidate.closingRange.upperBound...]),
            role: .plain,
            to: &result
        )
        return result
    }

    private static func resetPrefixSegments(
        in value: String
    ) -> [QuotaCountdownSegment]? {
        let patterns = [
            #"^([0-9]+)(天)([0-9]+)(小时|小時)(\s*[（(].*)$"#,
            #"^([0-9]+)(d\s+)([0-9]+)(h)(\s+\(.*)$"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                      in: value,
                      range: NSRange(value.startIndex..., in: value)
                  ),
                  match.numberOfRanges == 6
            else {
                continue
            }
            let captures = (1...5).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: value) else {
                    return nil
                }
                return String(value[range])
            }
            guard captures.count == 5 else { continue }
            return [
                .init(text: captures[0], role: .digits),
                .init(text: captures[1], role: .unit),
                .init(text: captures[2], role: .digits),
                .init(text: captures[3], role: .unit),
                .init(text: captures[4], role: .plain)
            ]
        }
        return nil
    }

    private static func intervalSegments(
        in interval: String
    ) -> [QuotaCountdownSegment]? {
        var cursor = interval.startIndex
        var segments: [QuotaCountdownSegment] = []

        if cursor < interval.endIndex, interval[cursor] == "<" {
            append("<", role: .punctuation, to: &segments)
            cursor = interval.index(after: cursor)
        }

        var pairCount = 0
        while cursor < interval.endIndex {
            let digitsStart = cursor
            while cursor < interval.endIndex, interval[cursor].isNumber {
                cursor = interval.index(after: cursor)
            }
            guard digitsStart < cursor, cursor < interval.endIndex else {
                break
            }

            let unit = interval[cursor]
            guard unit == "d" || unit == "h" || unit == "m" else {
                break
            }
            append(
                String(interval[digitsStart..<cursor]),
                role: .digits,
                to: &segments
            )
            append(String(unit), role: .unit, to: &segments)
            cursor = interval.index(after: cursor)
            pairCount += 1
        }

        guard pairCount > 0 else {
            return nil
        }
        let suffix = String(interval[cursor...])
        guard suffix.isEmpty || suffix == "前" || suffix == " ago" else {
            return nil
        }
        append(suffix, role: .suffix, to: &segments)
        return segments
    }

    private static func append(
        _ text: String,
        role: QuotaCountdownSegmentRole,
        to segments: inout [QuotaCountdownSegment]
    ) {
        guard !text.isEmpty else {
            return
        }
        if segments.last?.role == role {
            let previous = segments.removeLast()
            segments.append(.init(text: previous.text + text, role: role))
        } else {
            segments.append(.init(text: text, role: role))
        }
    }
}
