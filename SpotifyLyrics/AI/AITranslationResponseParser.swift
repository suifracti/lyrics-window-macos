import Foundation

public enum AITranslationResponseError: Error, Equatable, Sendable {
    case validationFailed(String)
}

public enum AITranslationResponseParser {
    public static func parse(_ data: Data, expectedLineCount: Int) throws -> [AITranslationLine] {
        guard expectedLineCount >= 0 else {
            throw AITranslationResponseError.validationFailed("行数无效")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw AITranslationResponseError.validationFailed("响应不是合法 JSON")
        }
        guard let array = object as? [[String: Any]] else {
            throw AITranslationResponseError.validationFailed("响应不是 JSON 数组")
        }
        var parsed: [AITranslationLine] = []
        parsed.reserveCapacity(array.count)
        for item in array {
            let allowed = Set(["index", "translation"])
            guard Set(item.keys).isSubset(of: allowed), Set(item.keys) == allowed,
                  let index = item["index"] as? NSNumber,
                  String(cString: index.objCType) != "c",
                  ["f", "d"].contains(String(cString: index.objCType)) == false,
                  let translation = item["translation"] as? String else {
                throw AITranslationResponseError.validationFailed("响应字段不严格")
            }
            parsed.append(AITranslationLine(index: index.intValue, translation: translation))
        }
        return try validate(parsed, expectedLineCount: expectedLineCount)
    }

    public static func validate(
        _ lines: [AITranslationLine],
        against originalLines: [String]
    ) throws -> [AITranslationLine] {
        _ = try validate(lines, expectedLineCount: originalLines.count)
        for line in lines {
            let original = originalLines[line.index]
            let sourceIsBlank = original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let translatedIsBlank = line.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard sourceIsBlank == translatedIsBlank,
                  !sourceIsBlank || line.translation.isEmpty else {
                throw AITranslationResponseError.validationFailed("空白行规则不满足 index=\(line.index)")
            }
        }
        return lines
    }

    public static func validate(
        _ lines: [AITranslationLine],
        expectedLineCount: Int
    ) throws -> [AITranslationLine] {
        guard lines.count == expectedLineCount else {
            throw AITranslationResponseError.validationFailed("行数不匹配")
        }
        let indexes = lines.map(\.index)
        guard Set(indexes).count == expectedLineCount,
              Set(indexes) == Set(0..<expectedLineCount) else {
            throw AITranslationResponseError.validationFailed("index 集合不完整或重复")
        }
        for line in lines {
            guard !line.translation.contains("\n"), !line.translation.contains("\r") else {
                throw AITranslationResponseError.validationFailed("翻译包含换行")
            }
        }
        return lines.sorted { $0.index < $1.index }
    }
}

/// Named validation entry point used by engine adapters and contracts. It
/// intentionally delegates to the existing strict parser so no second output
/// format or relaxed mapping path can appear.
public enum AITranslationResponseValidator {
    public static func validate(
        _ lines: [AITranslationLine],
        against original: [String]
    ) throws -> [AITranslationLine] {
        try AITranslationResponseParser.validate(lines, against: original)
    }
}
