import Foundation

public struct PresentationPreviewComparison: Equatable, Sendable {
    public let left: PresentationMetadata
    public let right: PresentationMetadata
    public let context: PresentationPreviewContext
    public let leftSnapshotKey: String
    public let rightSnapshotKey: String

    public init(
        left: PresentationMetadata,
        right: PresentationMetadata,
        context: PresentationPreviewContext
    ) {
        self.left = left
        self.right = right
        self.context = context
        self.leftSnapshotKey = context.snapshotKey
        self.rightSnapshotKey = context.snapshotKey
    }

    public var usesSameSnapshot: Bool {
        leftSnapshotKey == rightSnapshotKey
    }
}

/// Pure resolver/comparison layer for Debug Preview Lab and the future
/// Release Experience Library.  It only resolves metadata and passes an
/// immutable snapshot to a renderer; it never owns any application runtime.
public struct PresentationPreviewEngine: Sendable {
    public let catalog: PresentationCatalog

    public init(catalog: PresentationCatalog = .shared) {
        self.catalog = catalog
    }

    public func resolve(
        stableID: String,
        category: PresentationCategory
    ) -> PresentationMetadata {
        catalog.resolve(stableID: stableID, category: category)
    }

    public func compare(
        leftID: String,
        rightID: String,
        context: PresentationPreviewContext
    ) -> PresentationPreviewComparison? {
        guard let left = catalog.metadata(for: leftID),
              let right = catalog.metadata(for: rightID) else {
            return nil
        }
        return PresentationPreviewComparison(left: left, right: right, context: context)
    }
}
