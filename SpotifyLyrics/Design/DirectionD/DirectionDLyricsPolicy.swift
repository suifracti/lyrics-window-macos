import SwiftUI

/// Direction D Lyric Hierarchy Strategy & Projection Policy.
/// Enforces the strict rule: Default displays Original + MAX 1 Auxiliary Layer (Translation OR Ruby).
/// Auxiliary layers are weakened or removed on non-current lines to prevent visual clutter.
public struct DirectionDLyricsPolicy: Sendable {
    public enum AuxiliaryChoice: String, CaseIterable, Identifiable, Sendable {
        case translation
        case ruby
        case none

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .translation: return "中文翻译"
            case .ruby: return "假名注音"
            case .none: return "仅原文"
            }
        }
    }

    /// User-configured learning mode option (allows simultaneous Ruby + Original + Translation)
    public var isLearningModeEnabled: Bool
    /// Selected default auxiliary layer when learning mode is OFF
    public var defaultAuxiliaryChoice: AuxiliaryChoice
    /// Distance-based auxiliary hiding
    public var hideDistantAuxiliary: Bool

    public init(
        isLearningModeEnabled: Bool = false,
        defaultAuxiliaryChoice: AuxiliaryChoice = .translation,
        hideDistantAuxiliary: Bool = true
    ) {
        self.isLearningModeEnabled = isLearningModeEnabled
        self.defaultAuxiliaryChoice = defaultAuxiliaryChoice
        self.hideDistantAuxiliary = hideDistantAuxiliary
    }

    /// Evaluates which layers are visible for a specific lyric line based on distance & row state.
    public func resolveVisibleLayers(
        isActive: Bool,
        distance: Int,
        isRowExpanded: Bool = false
    ) -> (showOriginal: Bool, showTranslation: Bool, showRuby: Bool, showRomaji: Bool) {
        // Original is always shown
        let showOriginal = true

        // Expanded row or learning mode explicitly enables 3-layer rendering
        if isRowExpanded || isLearningModeEnabled {
            return (
                showOriginal: showOriginal,
                showTranslation: true,
                showRuby: true,
                showRomaji: false // Forbid 2 equivalent romaji layers
            )
        }

        // Distance >= 2 hides auxiliary layers on non-active rows if configured
        if hideDistantAuxiliary && distance >= 2 && !isActive {
            return (
                showOriginal: showOriginal,
                showTranslation: false,
                showRuby: false,
                showRomaji: false
            )
        }

        // Enforce Default Single Auxiliary Rule: Translation OR Ruby (Max 1)
        switch defaultAuxiliaryChoice {
        case .translation:
            return (
                showOriginal: showOriginal,
                showTranslation: true,
                showRuby: false,
                showRomaji: false
            )
        case .ruby:
            return (
                showOriginal: showOriginal,
                showTranslation: false,
                showRuby: true,
                showRomaji: false
            )
        case .none:
            return (
                showOriginal: showOriginal,
                showTranslation: false,
                showRuby: false,
                showRomaji: false
            )
        }
    }

    /// Calculates geometric emphasis without blurring glyphs.  Typography
    /// remains crisp at every distance; quietness comes from opacity and a
    /// very small scale difference only.
    public func resolveRowEmphasis(
        isActive: Bool,
        distance: Int,
        increaseContrast: Bool
    ) -> (opacity: Double, blurRadius: CGFloat, scale: CGFloat) {
        if isActive {
            return (opacity: 1.0, blurRadius: 0, scale: DirectionDDesignTokens.Lyrics.activeScale)
        } else if distance == 1 {
            let opacity = increaseContrast ? 0.76 : 0.62
            return (opacity: opacity, blurRadius: 0, scale: 1.0)
        } else {
            let opacity = increaseContrast ? 0.62 : 0.38
            return (opacity: opacity, blurRadius: 0, scale: 1.0)
        }
    }
}
