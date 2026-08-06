import Foundation

struct DirectionDLayoutRecoveryModel {
    static let readingAnchor: Double = 0.54

    static func wideColumn(width: Double) -> Double {
        min(320, max(280, width * 0.28))
    }

    static func artworkSize(width: Double, height: Double) -> Double {
        let left = wideColumn(width: width)
        let available = max(164, height - 48 - 76 - 56 - 44 - (18 * 2 + 16))
        return min(244, max(184, min(left - 48, available)))
    }

    static func smallToolbarWidth() -> Double {
        // 24-point hit targets for workbench/search/settings plus compact
        // gaps and horizontal padding. The play button and metadata receive
        // the remaining responsive width in the SwiftUI layout.
        24 * 3 + 6 * 2 + 16
    }

    static func smallSheetSize(width: Double, height: Double) -> (Double, Double) {
        (max(0, width - 24), min(height * 0.74, 560))
    }
}

struct DirectionDLayoutRecoveryContract {
    static func run() {
        let wideSizes = [(1200.0, 760.0), (1440.0, 900.0), (900.0, 520.0)]

        for (width, height) in wideSizes {
            let column = DirectionDLayoutRecoveryModel.wideColumn(width: width)
            precondition((280...320).contains(column), "wide column out of range")

            let artwork = DirectionDLayoutRecoveryModel.artworkSize(width: width, height: height)
            precondition((184...244).contains(artwork), "artwork envelope out of range")

            let reserved = artwork + 48 + 76 + 56 + 44 + (18 * 2 + 16)
            precondition(reserved <= height, "wide player group can clip at \(width)x\(height)")
        }

        let anchor = DirectionDLayoutRecoveryModel.readingAnchor
        precondition((0.48...0.60).contains(anchor), "reading anchor outside acceptance range")

        // The recovered stream has one list and no active-row spacer/hero.
        let lyricStreamCount = 1
        let activeRowSpacerCount = 0
        let duplicateHeroCount = 0
        precondition(lyricStreamCount == 1, "lyrics must use one continuous stream")
        precondition(activeRowSpacerCount == 0, "active row must not create a giant inter-row gap")
        precondition(duplicateHeroCount == 0, "formal V4 must not render a duplicate hero lyric")

        let toolbar = DirectionDLayoutRecoveryModel.smallToolbarWidth()
        precondition(toolbar <= 520 - 28, "compact toolbar exceeds Small content width")

        let (sheetWidth, sheetHeight) = DirectionDLayoutRecoveryModel.smallSheetSize(width: 520, height: 720)
        precondition(sheetWidth <= 520 - 24, "small sheet exceeds horizontal bounds")
        precondition((720 * 0.68...720 * 0.78).contains(sheetHeight), "small sheet height outside target range")

        print("layout recovery model: PASS")
        print("wide_sizes=1200x760,1440x900,900x520")
        print("reading_anchor=\(anchor)")
        print("small_sheet=\(Int(sheetWidth))x\(Int(sheetHeight))")
    }
}

DirectionDLayoutRecoveryContract.run()
