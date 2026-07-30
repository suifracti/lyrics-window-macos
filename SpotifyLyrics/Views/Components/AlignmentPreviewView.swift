import SwiftUI

/// Read-only evidence preview for a pending alignment.  It intentionally
/// does not expose transcript text or the source audio path; those remain
/// ephemeral implementation details of the current alignment task.
struct AlignmentPreviewView: View {
    let report: AlignmentReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("逐行排轴预览")
                        .font(.title3.weight(.semibold))
                    Text("引擎 \(report.modelID) · 总置信度 \(Int(report.overallConfidence * 100))% · \(report.lines.count) 行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            Text("时间来自带时间的识别证据；插值行仅用于预览，不能直接锁定。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.lines.enumerated()), id: \.element.id) { index, line in
                        row(index: index, line: line)
                    }
                }
            }
            .frame(minWidth: 680, minHeight: 420)
        }
        .padding(18)
        .frame(minWidth: 740, minHeight: 520)
        .preferredColorScheme(.dark)
    }

    private func row(index: Int, line: AlignedLyricLine) -> some View {
        let isLow = line.status != .aligned || line.confidence < 0.6
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.originalText.isEmpty ? "（空行）" : line.originalText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(evidenceDescription(line.evidence))
                    .font(.caption2)
                    .foregroundStyle(isLow ? .orange : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(timeRange(line))
                    .font(.caption.monospacedDigit())
                Text("\(statusLabel(line.status)) · \(Int(line.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(isLow ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isLow ? Color.orange.opacity(0.12) : Color.white.opacity(0.045))
        )
    }

    private func timeRange(_ line: AlignedLyricLine) -> String {
        guard line.startTime.isFinite, line.startTime >= 0 else { return "未匹配" }
        let end = line.endTime.map { String(format: "%.2f", $0) } ?? "—"
        return String(format: "%.2f → %@", line.startTime, end)
    }

    private func statusLabel(_ status: AlignmentLineStatus) -> String {
        switch status {
        case .aligned: return "直接"
        case .lowConfidence: return "低置信"
        case .unmatched: return "未匹配"
        case .interpolated: return "有界插值"
        }
    }

    private func evidenceDescription(_ evidence: AlignmentLineEvidence) -> String {
        let range: String
        if let start = evidence.segmentStartIndex, let end = evidence.segmentEndIndex {
            range = "片段 \(start)…\(end)"
        } else {
            range = "无直接片段"
        }
        return evidence.note.isEmpty ? range : "\(range) · \(evidence.note)"
    }
}
