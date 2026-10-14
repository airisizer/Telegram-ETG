import Foundation

/// Модель плагина — порт com.exteragram.messenger.plugins.Plugin.
/// Плагин — Python-файл с расширением .plugin и dunder-метаданными
/// (__id__, __name__, __version__, __author__, __description__, __icon__,
///  __min_app_version__, __sdk_version__, __requirements__).
public final class Plugin {
    public let id: String
    public var name: String
    public var version: String = "1.0"
    public var descriptionText: String = ""
    public var author: String = ""
    public var icon: String?           // формат "pack/index" (как в extera)
    public var appVersion: String = "" // минимальная версия клиента, ">=13.0"
    public var sdkVersion: String = "" // минимальная версия SDK,  ">=1.4.5.7"
    public var requirements: [String] = [] // pip-зависимости (только pure-python на iOS)

    public private(set) var isEnabled: Bool = false
    public private(set) var error: Error?
    public var isNotResponding: Bool = false

    public var hasError: Bool { error != nil }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public func setEnabled(_ value: Bool) {
        // Порт логики extera: плагин с ошибкой не может быть включён.
        isEnabled = value && !hasError
    }

    public func setError(_ error: Error?) {
        self.error = error
        if error != nil { isEnabled = false }
    }

    public static func isIconValid(_ icon: String?) -> Bool {
        guard let icon else { return false }
        return icon.range(of: "^[a-zA-Z][a-zA-Z0-9_]*/\\d+$", options: .regularExpression) != nil
    }
}

/// Результат выполнения хука — порт PluginsController.HookResult.
public struct HookResult<T> {
    public var result: T?
    public var cancel: Bool
    public var isFinal: Bool

    public init(result: T?, cancel: Bool = false, isFinal: Bool = false) {
        self.result = result
        self.cancel = cancel
        self.isFinal = isFinal
    }
}

/// Стратегии обработки — порт PluginsConstants.Strategy.
public enum HookStrategy: String {
    case `default` = "DEFAULT"
    case modify = "MODIFY"
    case modifyFinal = "MODIFY_FINAL"
    case cancel = "CANCEL"
}
