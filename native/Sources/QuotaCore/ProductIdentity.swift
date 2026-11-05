import Foundation
public struct ProductIdentity {
    public let version: String
    public let development: Bool
    public static func resolve(numeric: String, full: String?, provenance: Data) throws -> ProductIdentity {
        struct Proof: Decodable { let kind: String; let version: String?; let releaseTag: String?; let workingTreeDirty: Bool?; let sourceCommit: String? }
        func invalid() -> CocoaError { CocoaError(.fileReadCorruptFile) }
        guard provenance.count <= 1_048_576 else { throw invalid() }
        let base = try ProductVersion(numeric)
        guard !base.isBeta else { throw invalid() }
        let proof = try JSONDecoder().decode(Proof.self, from: provenance)
        let version = full ?? numeric, parsed = try ProductVersion(version)
        guard parsed.numericVersion == numeric else { throw invalid() }
        switch proof.kind {
        case "release":
            guard proof.workingTreeDirty == false, proof.version == version, proof.releaseTag == "v" + version, let commit = proof.sourceCommit, TrustedUpdateRelease.hex(commit, count: 40), full != nil || !parsed.isBeta else { throw invalid() }
            return ProductIdentity(version: version, development: false)
        case "local-development-candidate":
            guard proof.releaseTag == nil, full != nil || proof.version != nil, proof.version == nil || proof.version == version,
                  !parsed.isBeta || (full != nil && proof.version == version) else { throw invalid() }
            return ProductIdentity(version: version, development: true)
        default: throw invalid()
        }
    }
}
