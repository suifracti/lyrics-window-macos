import SwiftUI

/// User Task Language Badge component.
/// Renders clean, HIG-compliant status pills using non-engineering terms.
public struct DirectionDUserTaskBadge: View {
    public enum Style {
        case normal
        case success
        case warning
        case error
        case info
    }

    public let title: String
    public let style: Style

    public init(title: String, style: Style = .normal) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        Text(title)
            .font(DirectionDDesignTokens.Typography.userTaskBadge)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        switch style {
        case .normal: return Color.white.opacity(0.12)
        case .success: return Color.green.opacity(0.20)
        case .warning: return Color.orange.opacity(0.20)
        case .error: return Color.red.opacity(0.20)
        case .info: return Color.blue.opacity(0.20)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .normal: return Color.white.opacity(0.90)
        case .success: return Color.green
        case .warning: return Color.orange
        case .error: return Color.red
        case .info: return Color.cyan
        }
    }

    private var borderColor: Color {
        switch style {
        case .normal: return Color.white.opacity(0.18)
        case .success: return Color.green.opacity(0.40)
        case .warning: return Color.orange.opacity(0.40)
        case .error: return Color.red.opacity(0.40)
        case .info: return Color.cyan.opacity(0.40)
        }
    }
}

/// User-facing Status Banner component.
/// Displays clear natural-language status messages without exposing internal engineering jargon.
public struct DirectionDStatusBanner: View {
    public enum StateKind {
        case idle
        case spotifyNotRunning
        case loading
        case notFound
        case networkError
        case syncing
        case partialSaved
        case waitingContinue
        case syncComplete
        case syncUnreliable
        case engineNotReady
    }

    public let stateKind: StateKind
    public let onRetry: (() -> Void)?
    /// Optional override for secondary banners that share iconography but need distinct copy.
    public let customMessage: String?

    public init(stateKind: StateKind, onRetry: (() -> Void)? = nil, customMessage: String? = nil) {
        self.stateKind = stateKind
        self.onRetry = onRetry
        self.customMessage = customMessage
    }

    public var body: some View {
        HStack(spacing: 10) {
            iconView

            Text(customMessage ?? messageText)
                .font(DirectionDDesignTokens.Typography.statusMessage)
                .foregroundColor(Color.white.opacity(0.92))

            if let onRetry = onRetry {
                Spacer()
                Button(action: onRetry) {
                    Text("重试")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DirectionDDesignTokens.CornerRadius.card)
                .fill(Color(red: 0.10, green: 0.08, blue: 0.20).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: DirectionDDesignTokens.CornerRadius.card)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch stateKind {
        case .idle:
            Image(systemName: "music.note")
                .foregroundColor(.secondary)
        case .spotifyNotRunning:
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .notFound:
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
        case .networkError:
            Image(systemName: "wifi.slash")
                .foregroundColor(.red)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .partialSaved:
            Image(systemName: "bookmark.fill")
                .foregroundColor(.orange)
        case .waitingContinue:
            Image(systemName: "pause.circle")
                .foregroundColor(.secondary)
        case .syncComplete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .syncUnreliable:
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.orange)
        case .engineNotReady:
            Image(systemName: "gearshape")
                .foregroundColor(.secondary)
        }
    }

    private var messageText: String {
        switch stateKind {
        case .idle: return DirectionDDesignTokens.UserTaskLanguage.idleMessage
        case .spotifyNotRunning: return DirectionDDesignTokens.UserTaskLanguage.spotifyNotRunningMessage
        case .loading: return DirectionDDesignTokens.UserTaskLanguage.searchingMessage
        case .notFound: return DirectionDDesignTokens.UserTaskLanguage.notFoundMessage
        case .networkError: return DirectionDDesignTokens.UserTaskLanguage.networkErrorMessage
        case .syncing: return DirectionDDesignTokens.UserTaskLanguage.syncingMessage
        case .partialSaved: return DirectionDDesignTokens.UserTaskLanguage.partialSavedMessage
        case .waitingContinue: return DirectionDDesignTokens.UserTaskLanguage.waitingForPlaybackMessage
        case .syncComplete: return DirectionDDesignTokens.UserTaskLanguage.syncCompleteMessage
        case .syncUnreliable: return DirectionDDesignTokens.UserTaskLanguage.cannotCompleteReliablyMessage
        case .engineNotReady: return DirectionDDesignTokens.UserTaskLanguage.syncNotReadyMessage
        }
    }
}
