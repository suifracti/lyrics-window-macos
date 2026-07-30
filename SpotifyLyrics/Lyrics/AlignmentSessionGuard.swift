import Foundation

/// Immutable identity captured at the beginning of one local-audio alignment
/// task.  Every callback/result must pass this guard before it is allowed to
/// mutate the live lyrics session or reach persistence.
public struct AlignmentSessionGuard: Equatable, Sendable {
    public let identity: TrackIdentity
    public let sourceVersionID: UUID
    public let sourceContentHash: String
    public let revision: UInt64

    public init(
        identity: TrackIdentity,
        sourceVersionID: UUID,
        sourceContentHash: String,
        revision: UInt64
    ) {
        self.identity = identity
        self.sourceVersionID = sourceVersionID
        self.sourceContentHash = sourceContentHash
        self.revision = revision
    }

    public func accepts(
        identity: TrackIdentity?,
        sourceVersionID: UUID?,
        sourceContentHash: String?,
        revision: UInt64
    ) -> Bool {
        identity == self.identity &&
        sourceVersionID == self.sourceVersionID &&
        sourceContentHash == self.sourceContentHash &&
        revision == self.revision
    }
}
