import Foundation

enum MainWindowLayoutStyle: String, CaseIterable, Identifiable {
    case lyricsFocus
    case immersiveSplit
    case appleMusicImmersiveV3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyricsFocus:
            return "歌词专注"
        case .immersiveSplit:
            return "沉浸分栏"
        case .appleMusicImmersiveV3:
            return "Apple Music 沉浸 V3"
        }
    }

    var systemImage: String {
        switch self {
        case .lyricsFocus:
            return "text.alignleft"
        case .immersiveSplit:
            return "rectangle.split.2x1"
        case .appleMusicImmersiveV3:
            return "music.note.house"
        }
    }
}
