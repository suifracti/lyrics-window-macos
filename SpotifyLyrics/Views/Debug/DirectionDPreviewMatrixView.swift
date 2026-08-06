#if DEBUG
import SwiftUI

/// Direction D Design System Multi-State Preview Matrix (Phase 3.2).
/// Validates all 23 Direction D states using real SwiftUI Preview Adapters.
public struct DirectionDPreviewMatrixView: View {
    public enum MatrixState: String, CaseIterable, Identifiable, Sendable {
        case wideQuiet = "1. Wide 安静态"
        case wideHover = "2. Wide Hover"
        case inspectorClosed = "3. Inspector 关闭"
        case inspectorOpen = "4. Inspector 展开"
        case smallSheet = "5. Small Sheet"
        case currentLineContextMenu = "6. 当前行语境菜单"
        case originalAndTranslation = "7. 原文 + 翻译"
        case originalAndRuby = "8. 原文 + Ruby"
        case learningMode3Layer = "9. 学习模式三层"
        case longLyrics = "10. 长歌词"
        case idle = "11. Idle 待机"
        case spotifyNotRunning = "12. Spotify 未运行"
        case loading = "13. Loading 加载中"
        case noLyrics = "14. No Lyrics 未找到"
        case networkError = "15. Network Error 网络失败"
        case syncing = "16. 自动同步进行中"
        case partialSaved = "17. 部分进度落盘"
        case syncComplete = "18. 同步完成"
        case basicSettings = "19. 普通设置入口"
        case advancedSettings = "20. 高级设置入口"
        case reduceMotion = "21. Reduce Motion"
        case reduceTransparency = "22. Reduce Transparency"
        case increaseContrast = "23. Increase Contrast"

        public var id: String { rawValue }
    }

    @State private var selectedState: MatrixState = DirectionDPreviewMatrixView.initialStateFromEnvironment()
    @State private var isInspectorOpen = false

    public init() {}

    /// Audit/harness: `SPOTIFYLYRICS_DIRECTION_D_STATE=1` … `23` selects a matrix card.
    private static func initialStateFromEnvironment() -> MatrixState {
        let raw = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_DIRECTION_D_STATE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let idx = Int(raw), idx >= 1, idx <= MatrixState.allCases.count else {
            return .wideQuiet
        }
        return MatrixState.allCases[idx - 1]
    }

    public var body: some View {
        VStack(spacing: 0) {
            // State Selector Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MatrixState.allCases) { state in
                        Button(action: { selectedState = state }) {
                            Text(state.rawValue)
                                .font(.system(size: 12, weight: selectedState == state ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedState == state ? Color.accentColor : Color.white.opacity(0.10))
                                .foregroundColor(selectedState == state ? .white : Color.white.opacity(0.70))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.6))

            Divider()
                .background(Color.white.opacity(0.15))

            // Preview Stage - Always renders with DirectionDDesignTokens.Surface.defaultCanvasGradient
            ZStack {
                DirectionDDesignTokens.Surface.defaultCanvasGradient
                    .edgesIgnoringSafeArea(.all)

                renderStateView(selectedState)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 660)
        .accessibilityIdentifier("directionD.previewMatrix")
    }

    @ViewBuilder
    private func renderStateView(_ state: MatrixState) -> some View {
        let sampleLine = LyricLine(
            id: UUID(),
            timestamp: 15.0,
            originalText: "東京は夜七時 慌ただしい街に雨が降り出す",
            translationText: "东京晚上七点 匆忙的街头开始下起了雨",
            romajiText: "Tokyo wa yoru shichiji awadatasui machi ni ame ga furidasu",
            kanaText: "とうきょう は よる しちじ あわただしい まち に あめ が ふりだす"
        )
        let longLine = LyricLine(
            id: UUID(),
            timestamp: 24.5,
            originalText: "そっと抱き寄せて耳元で囁く「マーシャルのアンプで狂わせてよ、三波春夫でいさせて」",
            translationText: "轻轻将你搂入怀中 在耳边轻声细语「用马歇尔音箱让我沉醉吧」",
            romajiText: "sotto dakiyosete mimimoto de sasayaku",
            kanaText: "そっと だきよせて みみもと で ささやく"
        )

        switch state {
        case .wideQuiet, .inspectorClosed:
            VStack {
                DirectionDQuietToolbar(isInspectorOpen: false, onToggleInspector: {}, onOpenSearch: {}, onOpenSettings: {})
                Spacer()
                DirectionDLyricRowView(line: sampleLine, isActive: true, distance: 0)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .wideHover:
            VStack {
                // Wide Hover state: Toolbar is fully visible (opacity 1.0) with identical background gradient
                DirectionDQuietToolbar(isInspectorOpen: true, onToggleInspector: {}, onOpenSearch: {}, onOpenSettings: {})
                Spacer()
                DirectionDLyricRowView(line: sampleLine, isActive: true, distance: 0)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .inspectorOpen:
            HStack(spacing: 0) {
                VStack {
                    DirectionDQuietToolbar(isInspectorOpen: true, onToggleInspector: {}, onOpenSearch: {}, onOpenSettings: {})
                    Spacer()
                    DirectionDLyricRowView(line: sampleLine, isActive: true, distance: 0)
                    Spacer()
                }
                .frame(maxWidth: .infinity) // Adapts cleanly without clipping lyrics

                DirectionDInspectorView(onClose: {})
                    .frame(width: DirectionDDesignTokens.Spacing.inspectorWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .smallSheet:
            ZStack(alignment: .bottom) {
                VStack {
                    Text("Small 520px Viewport Context")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.top, 16)
                    Spacer()
                    DirectionDLyricRowView(line: sampleLine, isActive: true, distance: 0, availableWidth: 520)
                    Spacer()
                }
                .frame(width: 520, height: 600)
                .background(Color.black.opacity(0.40))

                DirectionDSmallSheetView(onClose: {})
                    .frame(width: 520)
            }
            .cornerRadius(12)

        case .currentLineContextMenu:
            VStack(spacing: 24) {
                DirectionDLyricRowView(line: sampleLine, isActive: true, distance: 0)
                DirectionDLineContextMenuView(
                    onEditTranslation: {},
                    onAdjustPhonetics: {},
                    onAdjustTiming: {},
                    onClose: {}
                )
            }
            .padding(40)

        case .originalAndTranslation:
            VStack(alignment: .leading, spacing: 12) {
                Text("硬约束：原文 + 翻译 (Single Auxiliary)")
                    .font(.caption)
                    .foregroundColor(.green)
                DirectionDLyricRowView(
                    line: sampleLine,
                    isActive: true,
                    distance: 0,
                    policy: DirectionDLyricsPolicy(defaultAuxiliaryChoice: .translation)
                )
            }
            .padding(30)

        case .originalAndRuby:
            VStack(alignment: .leading, spacing: 12) {
                Text("硬约束：原文 + Ruby (Single Auxiliary)")
                    .font(.caption)
                    .foregroundColor(.green)
                DirectionDLyricRowView(
                    line: sampleLine,
                    isActive: true,
                    distance: 0,
                    policy: DirectionDLyricsPolicy(defaultAuxiliaryChoice: .ruby)
                )
            }
            .padding(30)

        case .learningMode3Layer:
            VStack(alignment: .leading, spacing: 12) {
                Text("学习模式：Ruby + 原文 + 翻译")
                    .font(.caption)
                    .foregroundColor(.orange)
                DirectionDLyricRowView(
                    line: sampleLine,
                    isActive: true,
                    distance: 0,
                    policy: DirectionDLyricsPolicy(isLearningModeEnabled: true)
                )
            }
            .padding(30)

        case .longLyrics:
            DirectionDLyricRowView(line: longLine, isActive: true, distance: 0)
                .frame(maxWidth: 700)

        case .idle:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .idle)
            }

        case .spotifyNotRunning:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .spotifyNotRunning)
            }

        case .loading:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .loading)
            }

        case .noLyrics:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .notFound)
            }

        case .networkError:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .networkError, onRetry: {})
            }

        case .syncing:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .syncing)
            }

        case .partialSaved:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .partialSaved)
            }

        case .syncComplete:
            VStack(spacing: 20) {
                DirectionDStatusBanner(stateKind: .syncComplete)
            }

        case .basicSettings:
            DirectionDSettingsSectionGate {
                Text("基本设置项目：显示层、字号、快捷键、桌面/胶囊开关。")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.8))
            } advancedContent: {
                Text("高级内容（已门禁保护）")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.8))
            }
            .frame(width: 600)

        case .advancedSettings:
            DirectionDSettingsSectionGate {
                Text("基本设置项目")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.8))
            } advancedContent: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Base URL: https://api.openai.com/v1")
                    Text("SQLite Schema Version: v4")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.white)
            }
            .frame(width: 600)

        case .reduceMotion, .reduceTransparency, .increaseContrast:
            VStack(spacing: 16) {
                Text("系统 Accessibility 模式测试: \(state.rawValue)")
                    .font(.headline)
                    .foregroundColor(Color.white)
                DirectionDLyricRowView(line: sampleLine, isActive: true, distance: 0)
            }
            .padding(30)
        }
    }
}
#endif
