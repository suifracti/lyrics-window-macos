import SwiftUI

/// Native macOS Inspector Component for Song Workbench (Direction D).
///
/// The primary surface uses continuous sections and user-task language rather
/// than a dashboard of status cards.  It remains a presentation-only view:
/// actions are supplied by the existing router/operation layer.
public struct DirectionDInspectorView: View {
    public let trackTitle: String
    public let artistName: String
    public let albumName: String
    public let artworkImage: Image?
    public let onClose: () -> Void

    @State private var isAdvancedExpanded = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        trackTitle: String = "丸ノ内サディスティック",
        artistName: String = "椎名林檎",
        albumName: String = "無罪モラトリアム",
        artworkImage: Image? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.trackTitle = trackTitle
        self.artistName = artistName
        self.albumName = albumName
        self.artworkImage = artworkImage
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                Text("歌曲工作台")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("关闭歌曲工作台")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()
                .overlay(Color.white.opacity(DirectionDDesignTokens.Surface.hairlineOpacity))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    trackSummary
                    sectionDivider

                    inspectorSection(title: "歌词与版本", icon: "text.book.closed") {
                        selectionRow(
                            title: "社区同步歌词",
                            detail: "包含逐行时间轴",
                            status: "当前使用"
                        )

                        HStack(spacing: 16) {
                            inspectorAction("切换候选", systemImage: "arrow.left.arrow.right") {}
                            inspectorAction("重新搜索", systemImage: "magnifyingglass") {}
                        }
                        .padding(.top, 10)
                    }
                    sectionDivider

                    inspectorSection(title: "翻译与读音", icon: "character.book.closed") {
                        selectionRow(
                            title: "智能意译",
                            detail: "自然流畅风格",
                            status: "当前显示"
                        )
                        selectionRow(
                            title: "日文平假名注音",
                            detail: "与原文保持对齐",
                            status: "可显示"
                        )
                    }
                    sectionDivider

                    inspectorSection(title: "时间同步", icon: "clock") {
                        selectionRow(
                            title: "逐行时间轴同步",
                            detail: "当前版本已完成",
                            status: "已完成"
                        )
                        inspectorAction("校准时间", systemImage: "slider.horizontal.3") {}
                            .padding(.top, 10)
                    }
                    sectionDivider

                    inspectorSection(title: "历史版本", icon: "clock.arrow.circlepath") {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("查看歌词与翻译的历史版本")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                                Text("保留原始内容，随时可以恢复")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.56))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {}
                    }
                    sectionDivider

                    inspectorSection(title: "导入与导出", icon: "square.and.arrow.down") {
                        HStack(spacing: 16) {
                            inspectorAction("导出 .lrc", systemImage: "square.and.arrow.up") {}
                            inspectorAction("导入本地文件", systemImage: "square.and.arrow.down") {}
                        }
                    }
                    sectionDivider

                    DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("来源与运行细节")
                            Text("仅用于排查问题，不影响歌词显示")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.54))
                        .padding(.top, 10)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "ellipsis.circle")
                            Text("高级详细信息")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.64))
                    }
                    .tint(.white.opacity(0.58))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        }
        .background {
            ZStack {
                Color.black.opacity(reduceTransparency ? 0.94 : 0.78)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(reduceTransparency ? 0.04 : 0.30)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(DirectionDDesignTokens.Surface.hairlineOpacity))
                .frame(width: 1)
        }
    }

    private var trackSummary: some View {
        HStack(spacing: 12) {
            if let artworkImage {
                artworkImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.52))
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(trackTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(artistName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Text(albumName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.white.opacity(DirectionDDesignTokens.Surface.hairlineOpacity))
            .padding(.vertical, 16)
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            content()
        }
    }

    private func selectionRow(title: String, detail: String, status: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.56))
            }
            Spacer(minLength: 8)
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
    }

    private func inspectorAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

/// Small window Sheet Overlay component for Direction D.
/// Emerges from bottom of viewport, max height ~80%, legible dark glass surface with ScrollView.
public struct DirectionDSmallSheetView: View {
    public let trackTitle: String
    public let artistName: String
    public let albumName: String
    public let onClose: () -> Void

    public init(
        trackTitle: String = "丸ノ内サディスティック",
        artistName: String = "椎名林檎",
        albumName: String = "無罪モラトリアム",
        onClose: @escaping () -> Void
    ) {
        self.trackTitle = trackTitle
        self.artistName = artistName
        self.albumName = albumName
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.40))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            DirectionDInspectorView(
                trackTitle: trackTitle,
                artistName: artistName,
                albumName: albumName,
                onClose: onClose
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.thickMaterial)
                .opacity(0.92)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.48), radius: 16, x: 0, y: -4)
    }
}
