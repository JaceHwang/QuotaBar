import Foundation

/// Restricted, deterministic version identity shared by stable and beta updates.
public struct ProductVersion: Comparable, Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let beta: Int?

    public init(_ value: String) throws {
        func invalid() -> CocoaError { CocoaError(.fileReadCorruptFile) }
        guard value.utf8.count <= 128 else { throw invalid() }
        let parts = value.components(separatedBy: "-beta.")
        guard parts.count == 1 || parts.count == 2 else { throw invalid() }
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        func number(_ value: Substring, maximum: Int, minimum: Int = 0) throws -> Int {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  (value.count == 1 || value.first != "0"), let n = Int(value),
                  (minimum...maximum).contains(n) else { throw invalid() }
            return n
        }
        guard numbers.count == 3 else { throw invalid() }
        major = try number(numbers[0], maximum: 65_534)
        minor = try number(numbers[1], maximum: 65_534)
        patch = try number(numbers[2], maximum: 65_534)
        beta = parts.count == 2 ? try number(Substring(parts[1]), maximum: 2_147_483_647, minimum: 1) : nil
    }

    public var isBeta: Bool { beta != nil }
    public var numericVersion: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ProductVersion, rhs: ProductVersion) -> Bool {
        let a = [lhs.major, lhs.minor, lhs.patch], b = [rhs.major, rhs.minor, rhs.patch]
        if a != b { return a.lexicographicallyPrecedes(b) }
        switch (lhs.beta, rhs.beta) {
        case let (a?, b?): return a < b
        case (_?, nil): return true
        default: return false
        }
    }
}
