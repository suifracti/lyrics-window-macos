import Foundation

public enum LyricsTimelineIssueSeverity: String, Equatable, Sendable {
    case warning
    case error
}

public struct LyricsTimelineIssue: Equatable, Sendable {
    public let lineIndex: Int?
    public let severity: LyricsTimelineIssueSeverity
    public let message: String

    public init(lineIndex: Int? = nil, severity: LyricsTimelineIssueSeverity, message: String) {
        self.lineIndex = lineIndex
        self.severity = severity
        self.message = message
    }
}

public struct LyricsTimelineValidationResult: Equatable, Sendable {
    public let issues: [LyricsTimelineIssue]
    public let isSynchronized: Bool

    public init(issues: [LyricsTimelineIssue], isSynchronized: Bool) {
        self.issues = issues
        self.isSynchronized = isSynchronized
    }

    public var errors: [LyricsTimelineIssue] {
        issues.filter { $0.severity == .error }
    }

    public var warnings: [LyricsTimelineIssue] {
        issues.filter { $0.severity == .warning }
    }

    public var isSaveAllowed: Bool { errors.isEmpty }
}

public enum LyricsTimelineValidator {
    public static func validate(
        lines: [LyricsEditorLineDraft],
        duration: TimeInterval?,
        tolerance: TimeInterval = 0.5
    ) -> LyricsTimelineValidationResult {
        var issues: [LyricsTimelineIssue] = []
        let nonBlankIndices = lines.indices.filter {
            !lines[$0].originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let timedNonBlank = nonBlankIndices.filter { lines[$0].startTime != nil }
        let isSynchronized = !nonBlankIndices.isEmpty && timedNonBlank.count == nonBlankIndices.count
        var previousStart: TimeInterval?

        for index in lines.indices {
            let line = lines[index]
            if let start = line.startTime {
                validateValue(start, index: index, label: "开始时间", duration: duration, tolerance: tolerance, issues: &issues)
                if let previousStart {
                    if start < previousStart {
                        issues.append(LyricsTimelineIssue(lineIndex: index, severity: .error, message: "时间戳必须单调不减"))
                    } else if start == previousStart {
                        issues.append(LyricsTimelineIssue(lineIndex: index, severity: .warning, message: "与上一行时间相同"))
                    }
                }
                previousStart = start
            }
            if let end = line.endTime {
                validateValue(end, index: index, label: "结束时间", duration: duration, tolerance: tolerance, issues: &issues)
                guard let start = line.startTime else {
                    issues.append(LyricsTimelineIssue(lineIndex: index, severity: .error, message: "有结束时间时必须有开始时间"))
                    continue
                }
                if end < start {
                    issues.append(LyricsTimelineIssue(lineIndex: index, severity: .error, message: "结束时间不能早于开始时间"))
                }
            }
            if !line.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               line.startTime == nil,
               timedNonBlank.count > 0 {
                issues.append(LyricsTimelineIssue(lineIndex: index, severity: .warning, message: "歌词行没有时间，将按纯文本保存"))
            }
        }

        if !nonBlankIndices.isEmpty && timedNonBlank.isEmpty {
            // A document with no timestamps is valid and remains plain text.
        }
        return LyricsTimelineValidationResult(issues: issues, isSynchronized: isSynchronized)
    }

    private static func validateValue(
        _ value: TimeInterval,
        index: Int,
        label: String,
        duration: TimeInterval?,
        tolerance: TimeInterval,
        issues: inout [LyricsTimelineIssue]
    ) {
        guard value.isFinite, value >= 0 else {
            issues.append(LyricsTimelineIssue(lineIndex: index, severity: .error, message: "\(label)不能为负数或非有限值"))
            return
        }
        guard let duration, duration.isFinite, duration > 0 else { return }
        if value > duration + tolerance {
            issues.append(LyricsTimelineIssue(lineIndex: index, severity: .error, message: "\(label)明显超过歌曲时长"))
        } else if value > duration {
            issues.append(LyricsTimelineIssue(lineIndex: index, severity: .warning, message: "\(label)略超过歌曲时长"))
        }
    }
}
