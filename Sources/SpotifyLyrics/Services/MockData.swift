import Foundation

public struct MockData {
    public static let sampleTrack = Track(
        id: "mock-track-1",
        title: "夜に駆ける (Into The Night)",
        artist: "YOASOBI",
        album: "THE BOOK",
        duration: 261,
        artworkName: "music.note.house",
        isrc: "JPX002000001",
        spotifyId: "3d9QxchW9R249VjX2l"
    )
    
    public static let sampleLyrics: [LyricLine] = [
        LyricLine(
            timestamp: 0.0,
            originalText: "沈むように溶けてゆくように",
            translationText: "像沉入其中一样 像融化一样",
            romajiText: "sizumu you ni tokete yuku you ni",
            kanaText: "しずむようにとけてゆくように"
        ),
        LyricLine(
            timestamp: 4.5,
            originalText: "二人だけの空が広がる夜に",
            translationText: "在只有我们两人的天空展开的夜晚",
            romajiText: "futari dake no sora ga hirogaru yoru ni",
            kanaText: "ふたりだけのそらがひろがるよるに"
        ),
        LyricLine(
            timestamp: 9.2,
            originalText: "「さよなら」だけだった",
            translationText: "仅仅只有一句“再见”",
            romajiText: "sayonara dake datta",
            kanaText: "「さよなら」だけだった"
        ),
        LyricLine(
            timestamp: 12.8,
            originalText: "その一言で全てが分かった",
            translationText: "仅凭那简短的一句话 我便懂了一切",
            romajiText: "sono hitokoto de subete ga wakatta",
            kanaText: "そのひとことですべてがわかった"
        ),
        LyricLine(
            timestamp: 17.5,
            originalText: "日が沈み出した空と君の姿",
            translationText: "夕阳西下的天空与你的身姿",
            romajiText: "hi ga sizumi dasita sora to kimi no sugata",
            kanaText: "ひがしずみだしたそらときみのすがた"
        ),
        LyricLine(
            timestamp: 22.0,
            originalText: "フェンス越しに重なり合っていた",
            translationText: "穿过围栏重叠在一起",
            romajiText: "fensu gosi ni kasani atte ita",
            kanaText: "フェンスごしにかさなりあっていた"
        )
    ]
}
