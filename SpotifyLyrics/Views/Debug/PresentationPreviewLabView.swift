#if DEBUG
import SwiftUI
import AppKit

/// Debug-only, read-only catalog browser.  Each card is rendered by the
/// category/stable-ID adapter registry against one immutable snapshot.
struct PresentationPreviewLabView: View {
    @EnvironmentObject private var playbackState: PlaybackState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let catalog = PresentationCatalog.shared
    @State private var selectedCategory: PresentationCategory = .mainWindow
    @State private var selectedStableID: String?
    @State private var comparedStableID: String?
    @State private var source: PresentationPreviewSource = .mock
    @State private var compareEnabled = true
    @State private var capsulePreviewState: PresentationPreviewCapsuleState = .expanded
    @State private var showDirectionDMatrix = false

    private var categoryEntries: [PresentationMetadata] {
        catalog.entries(for: selectedCategory)
    }

    private var selectedEntry: PresentationMetadata {
        if let selectedStableID,
           let exact = catalog.metadata(for: selectedStableID),
           exact.category == selectedCategory {
            return exact
        }
        return catalog.resolve(stableID: "", category: selectedCategory)
    }

    private var comparedEntry: PresentationMetadata {
        if let comparedStableID,
           let exact = catalog.metadata(for: comparedStableID),
           exact.category == selectedCategory {
            return exact
        }
        return categoryEntries.first(where: { $0.stableID != selectedEntry.stableID }) ?? selectedEntry
    }

    private var previewContext: PresentationPreviewContext? {
        let base: PresentationPreviewContext?
        switch source {
        case .mock:
            base = .mock(
                surface: .preview,
                windowSize: PresentationPreviewSize(width: 1_060, height: 680),
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency,
                increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            )
        case .live:
            guard playbackState.hasLiveTrack else { return nil }
            base = PresentationPreviewContextFactory.live(
                from: playbackState,
                surface: .preview,
                windowSize: PresentationPreviewSize(width: 1_060, height: 680)
            )
        }
        return base?.with(capsuleState: capsulePreviewState)
    }

    var body: some View {
        NavigationSplitView {
            categoryList
                .navigationTitle("Presentation")
        } content: {
            versionList
                .navigationTitle(selectedCategory.displayName)
        } detail: {
            detailPane
                .navigationTitle("Preview")
        }
        .frame(minWidth: 1_060, minHeight: 680)
        .preferredColorScheme(.dark)
        .onAppear(perform: ensureSelection)
        .onChange(of: selectedCategory) { _, _ in ensureSelection() }
    }

    private var categoryList: some View {
        List(PresentationCategory.allCases, selection: $selectedCategory) { category in
            Label(category.displayName, systemImage: category.systemImage)
                .tag(category)
        }
        .listStyle(.sidebar)
    }

    private var versionList: some View {
        List(selection: $selectedStableID) {
            Section("可维护版本") {
                ForEach(categoryEntries) { entry in
                    PresentationVersionRow(entry: entry)
                        .tag(entry.stableID)
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: selectedStableID) { _, _ in
            if comparedStableID == selectedStableID {
                comparedStableID = nil
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            metadataHeader

            HStack(alignment: .center, spacing: 12) {
                Picker("数据来源", selection: $source) {
                    Text("Mock Snapshot").tag(PresentationPreviewSource.mock)
                    Text("Live Snapshot").tag(PresentationPreviewSource.live)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Toggle("A/B 对照", isOn: $compareEnabled)
                    .toggleStyle(.checkbox)

                if compareEnabled {
                    Picker(
                        "对照版本",
                        selection: Binding(
                            get: { comparedStableID ?? selectedEntry.stableID },
                            set: { comparedStableID = $0 }
                        )
                    ) {
                        ForEach(categoryEntries.filter { $0.stableID != selectedEntry.stableID }) { entry in
                            Text("B · \(entry.displayName)").tag(entry.stableID)
                        }
                    }
                    .frame(width: 220)
                }

                if selectedCategory == .capsule {
                    Picker("胶囊状态", selection: $capsulePreviewState) {
                        ForEach(PresentationPreviewCapsuleState.allCases, id: \.self) { state in
                            Text(state.displayName).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Button("方向 D 矩阵…") {
                    showDirectionDMatrix = true
                }
                .buttonStyle(.bordered)
                .help("打开 Direction D 23 状态设计系统预览（仅 DEBUG）")

                Spacer()
            }
            .sheet(isPresented: $showDirectionDMatrix) {
                DirectionDPreviewMatrixView()
                    .frame(minWidth: 1_000, minHeight: 660)
            }

            if let context = previewContext {
                HStack(alignment: .top, spacing: 14) {
                    previewCard(
                        entry: selectedEntry,
                        context: context,
                        label: "A · 当前选择"
                    )
                    if compareEnabled {
                        previewCard(
                            entry: comparedEntry,
                            context: context,
                            label: "B · 同一 Snapshot"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "没有可用的 Live Snapshot",
                    systemImage: "waveform.path.ecg",
                    description: Text("当前没有 live 歌曲；切换到 Mock Snapshot 可预览。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(22)
    }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedEntry.displayName)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(selectedEntry.status.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.22), in: Capsule())
                Spacer()
                Text(selectedEntry.availability.displayName)
                    .foregroundStyle(.secondary)
            }

            Text(selectedEntry.stableID)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("v\(selectedEntry.version)", systemImage: "number")
                Label(selectedEntry.supportsLivePreview ? "支持 Live" : "不支持 Live", systemImage: "dot.radiowaves.left.and.right")
                Label(selectedEntry.supportsMockPreview ? "支持 Mock" : "不支持 Mock", systemImage: "rectangle.on.rectangle")
                Text(selectedEntry.compatibleSurfaces.map(\.displayName).joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
        }
    }

    private func previewCard(
        entry: PresentationMetadata,
        context: PresentationPreviewContext,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.stableID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            PresentationPreviewAdapterView(entry: entry, context: context)
                .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 330)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Snapshot: \(context.snapshotKey)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text("\(context.source.rawValue) · \(context.windowSize.width, specifier: "%.0f")×\(context.windowSize.height, specifier: "%.0f") · \(context.lyricsState.displayName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func ensureSelection() {
        let entries = catalog.entries(for: selectedCategory)
        if !entries.contains(where: { $0.stableID == selectedStableID }) {
            selectedStableID = catalog.resolve(stableID: "", category: selectedCategory).stableID
        }
        if !entries.contains(where: { $0.stableID == comparedStableID }) || comparedStableID == selectedStableID {
            comparedStableID = entries.first(where: { $0.stableID != selectedStableID })?.stableID
        }
    }
}

private struct PresentationVersionRow: View {
    let entry: PresentationMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(entry.status.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.status == .experimental ? .orange : .secondary)
            }
            Text(entry.stableID)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(entry.availability.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private extension PresentationCategory {
    var systemImage: String {
        switch self {
        case .mainWindow: return "rectangle.split.3x1"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .capsule: return "capsule"
        case .floatingLyrics: return "text.bubble"
        case .backdrop: return "paintpalette"
        case .lyricsTransition: return "arrow.left.and.right"
        case .lyricsState: return "ellipsis.bubble"
        case .progress: return "chart.bar.xaxis"
        case .responsiveLayout: return "rectangle.resize"
        }
    }
}
#endif
