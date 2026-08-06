import SwiftUI

/// Gate component for Basic vs Advanced Settings.
/// Keeps basic settings clean and simple, while isolating engineering controls behind an explicit expander/gate.
public struct DirectionDSettingsSectionGate<BasicContent: View, AdvancedContent: View>: View {
    public let basicTitle: String
    public let basicContent: BasicContent
    public let advancedContent: AdvancedContent

    @State private var isAdvancedUnlocked = false

    public init(
        basicTitle: String = "常规设置",
        @ViewBuilder basicContent: () -> BasicContent,
        @ViewBuilder advancedContent: () -> AdvancedContent
    ) {
        self.basicTitle = basicTitle
        self.basicContent = basicContent()
        self.advancedContent = advancedContent()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Basic Settings Block
            VStack(alignment: .leading, spacing: 12) {
                Text(basicTitle)
                    .font(DirectionDDesignTokens.Typography.trackTitle)
                    .foregroundColor(Color.white)

                basicContent
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Advanced Gate / Expander
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "shield.trianglebadge.exclamationmark")
                        .foregroundColor(isAdvancedUnlocked ? .orange : Color.white.opacity(0.7))

                    Text("高级工程设置")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.white)

                    Spacer()

                    Button(action: {
                        withAnimation {
                            isAdvancedUnlocked.toggle()
                        }
                    }) {
                        Text(isAdvancedUnlocked ? "隐藏高级设置" : "打开高级工程设置...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                if isAdvancedUnlocked {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("包含 AI Base URL, Whisper 模型参数, SQLite Migration 与开发者诊断。非必要无需修改。")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.75))

                        advancedContent
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(DirectionDDesignTokens.CornerRadius.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: DirectionDDesignTokens.CornerRadius.card)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
            }
        }
        .padding(20)
    }
}

/// User-friendly Version & Source Summary component.
public struct DirectionDVersionSummaryView: View {
    public let sourceTitle: String
    public let isSynced: Bool
    public let versionCount: Int

    public init(sourceTitle: String = "社区同步歌词", isSynced: Bool = true, versionCount: Int = 3) {
        self.sourceTitle = sourceTitle
        self.isSynced = isSynced
        self.versionCount = versionCount
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSynced ? "sparkles" : "text.alignleft")
                .foregroundColor(isSynced ? .green : Color.white.opacity(0.7))

            Text(sourceTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white)

            if isSynced {
                DirectionDUserTaskBadge(title: "逐行时间轴", style: .success)
            } else {
                DirectionDUserTaskBadge(title: "纯文本", style: .normal)
            }

            Spacer()

            Text("\(versionCount) 个历史版本")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.65))
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(DirectionDDesignTokens.CornerRadius.card)
    }
}
