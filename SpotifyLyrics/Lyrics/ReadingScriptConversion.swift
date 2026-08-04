import Foundation

public enum ReadingScriptConverter {
    private static let traditionalToSimplified: [Character: Character] = [
        "銀": "银", "長": "长", "樂": "乐", "學": "学", "國": "国", "門": "门",
        "車": "车", "東": "东", "風": "风", "慶": "庆", "開": "开", "過": "过",
        "時": "时", "間": "间", "讀": "读", "見": "见", "聽": "听", "歡": "欢",
        "這": "这", "為": "为", "個": "个", "會": "会", "來": "来", "與": "与"
    ]

    public static func convert(_ text: String, using conversion: ScriptConversionID) -> String {
        switch conversion {
        case .none: return text
        case .traditionalToSimplified:
            return String(text.map { traditionalToSimplified[$0] ?? $0 })
        case .simplifiedToTraditional:
            let reverse = Dictionary(uniqueKeysWithValues: traditionalToSimplified.map { ($0.value, $0.key) })
            return String(text.map { reverse[$0] ?? $0 })
        }
    }
}
