import Foundation

enum MainWindowLayoutStyle: String, CaseIterable, Identifiable {
    case lyricsFocus
    case immersiveSplit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyricsFocus:
            return "歌词专注"
        case .immersiveSplit:
            return "沉浸分栏"
        }
    }

    var systemImage: String {
        switch self {
        case .lyricsFocus:
            return "text.alignleft"
        case .immersiveSplit:
            return "rectangle.split.2x1"
        }
    }
}
