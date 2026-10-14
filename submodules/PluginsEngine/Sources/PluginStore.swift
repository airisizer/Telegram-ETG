import Foundation

/// Хранилище состояния движка — порт префов exteraGram
/// (plugin_enabled_<id>, had_crash, crashed_plugin_id).
public final class PluginStore {
    public static let shared = PluginStore()
    private let defaults: UserDefaults
    private let enabledPrefix = "plugin_enabled_"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isPluginEnabled(_ id: String) -> Bool {
        defaults.bool(forKey: enabledPrefix + id)
    }

    public func setPluginEnabled(_ id: String, _ value: Bool) {
        defaults.set(value, forKey: enabledPrefix + id)
    }

    // MARK: - Краш-безопасность (safe mode)

    public var hadCrash: Bool {
        get { defaults.bool(forKey: "plugins_had_crash") }
        set { defaults.set(newValue, forKey: "plugins_had_crash") }
    }

    public var crashedPluginId: String? {
        get { defaults.string(forKey: "plugins_crashed_plugin_id") }
        set { defaults.set(newValue, forKey: "plugins_crashed_plugin_id") }
    }

    public var safeMode: Bool {
        get { defaults.bool(forKey: "pluginsSafeMode") }
        set { defaults.set(newValue, forKey: "pluginsSafeMode") }
    }

    /// Порт init()-логики exteraGram: разбор краша прошлого запуска.
    /// Возвращает: id плагина, которого надо отключить, либо nil.
    /// Если краш был "manual!" или запрошен safe mode — глобальный safe mode.
    @discardableResult
    public func resolveCrashState(startWithSafeMode: Bool) -> String? {
        let hadCrash = self.hadCrash
        let crashedId = self.crashedPluginId
        self.hadCrash = false
        self.crashedPluginId = nil
        guard hadCrash else {
            safeMode = startWithSafeMode
            return nil
        }
        let manual = crashedId == "manual!"
        if manual || startWithSafeMode {
            safeMode = true
            return nil
        }
        if let crashedId {
            setPluginEnabled(crashedId, false)
            return crashedId
        }
        return nil
    }

    // MARK: - Настройки плагинов (ключ-значение, JSON-кодируемые)

    public func getSetting(pluginId: String, key: String) -> Any? {
        defaults.object(forKey: "plugin_setting_\(pluginId)_\(key)")
    }

    public func setSetting(pluginId: String, key: String, value: Any?) {
        if let value {
            defaults.set(value, forKey: "plugin_setting_\(pluginId)_\(key)")
        } else {
            defaults.removeObject(forKey: "plugin_setting_\(pluginId)_\(key)")
        }
    }

    public func allSettings(pluginId: String) -> [String: Any] {
        let prefix = "plugin_setting_\(pluginId)_"
        var out: [String: Any] = [:]
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            out[String(key.dropFirst(prefix.count))] = defaults.object(forKey: key)
        }
        return out
    }

    public func clearSettings(pluginId: String) {
        let prefix = "plugin_setting_\(pluginId)_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
