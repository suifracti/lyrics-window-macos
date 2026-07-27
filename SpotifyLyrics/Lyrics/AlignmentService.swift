import Foundation

/// Abstraction so SwiftUI / PlaybackState never depend on a concrete ML stack.
public protocol AlignmentService: Sendable {
    var id: String { get }
    func align(
        _ request: AlignmentRequest,
        progress: (@Sendable (AlignmentProgress) -> Void)?
    ) async throws -> AlignmentReport
}
