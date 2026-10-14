import Foundation

/// Swift-парсер dunder-метаданных .plugin файлов.
/// Читает ТОЛЬКО заголовок файла (первые ~200 строк) — быстрее, чем поднимать
/// Python ради метаданных (в extera это делает extera_utils.metadata_parser).
public struct PluginMetadata {
    public var id: String = ""
    public var name: String = ""
    public var version: String = "1.0"
    public var description: String = ""
    public var author: String = ""
    public var icon: String = ""
    public var appVersion: String = ""
    public var sdkVersion: String = ""
    public var requirements: [String] = []
}

public enum PluginMetadataParser {
    public static func parse(file: URL) -> PluginMetadata? {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text: text)
    }

    public static func parse(text: String) -> PluginMetadata? {
        // Берём шапку файла — dunder-поля по конвенции в начале.
        let head = text.components(separatedBy: .newlines).prefix(200).joined(separator: "\n")
        var meta = PluginMetadata()

        func dunder(_ key: String) -> String? {
            // __key__ = "value" | 'value' | """value"""
            let pattern = "__\(key)__\\s*=\\s*(?:\"\"\"([\\s\\S]*?)\"\"\"|\"([^\"]*)\"|'([^']*)')"
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)) else { return nil }
            for i in 1...3 {
                let r = m.range(at: i)
                if r.location != NSNotFound, let range = Range(r, in: head) {
                    return String(head[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        meta.id = dunder("id") ?? ""
        meta.name = dunder("name") ?? ""
        meta.version = dunder("version") ?? "1.0"
        meta.description = dunder("description") ?? ""
        meta.author = dunder("author") ?? ""
        meta.icon = dunder("icon") ?? ""
        meta.appVersion = dunder("min_app_version") ?? dunder("app_version") ?? ""
        meta.sdkVersion = dunder("sdk_version") ?? ""

        // __requirements__ = ["a", "b"] — простой список строк
        if let reqRaw = dunder("requirements") {
            let pattern = "\"([^\"]+)\"|'([^']+)'"
            if let re = try? NSRegularExpression(pattern: pattern) {
                let matches = re.matches(in: reqRaw, range: NSRange(reqRaw.startIndex..., in: reqRaw))
                meta.requirements = matches.compactMap { m in
                    for i in 1...2 {
                        let r = m.range(at: i)
                        if r.location != NSNotFound, let range = Range(r, in: reqRaw) {
                            return String(reqRaw[range])
                        }
                    }
                    return nil
                }
            }
        }

        // id обязателен; fallback — имя файла без расширения (конвенция extera:
        // id плагина = имя Python-модуля).
        if meta.id.isEmpty { return nil }
        if meta.name.isEmpty { meta.name = meta.id }
        // id должен быть валидным именем Python-модуля
        guard meta.id.range(of: "^[a-zA-Z_][a-zA-Z0-9_]*$", options: .regularExpression) != nil else { return nil }
        return meta
    }
}
