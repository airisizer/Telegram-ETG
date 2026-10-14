import Foundation
import TelegramCore

/// Точка входа движка — порт com.exteragram.messenger.plugins.PluginsController.
/// Синглтон, владеет реестром плагинов, хуков, пунктов меню; управляет
/// Python-рантаймом; безопасен для вызова с любого потока.
public final class PluginController {
    public static let shared = PluginController()

    /// Поток исполнения движка (аналог runOnPluginsQueue в exteraGram).
    public let pluginsQueue = DispatchQueue(label: "org.telegram.plugins.queue")

    // MARK: - Состояние

    public private(set) var plugins: [String: Plugin] = [:]       // id -> метаданные
    public private(set) var initialized = false

    /// Хуки событий: имя события -> записи (по убыванию приоритета).
    private var eventHooks: [String: [EventHook]] = [:]
    /// Xposed-стиль хуки методов (через AndroidCompatMap на iOS-точки).
    private var methodHooks: [String: [MethodHook]] = [:]
    /// Пункты меню: тип меню -> записи.
    private var menuItems: [String: [PluginMenuItem]] = [:]
    /// Кэш «кто подписан на событие» — инвалидируется при add/remove.
    private var interestedCache: [String: [String]] = [:]

    /// Папка плагинов: Documents/plugins (аналог filesDir/plugins).
    public var pluginsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("plugins", isDirectory: true)
    }

    /// Колбэк «список плагинов изменился» — UI подписывается.
    public var onPluginsChanged: (() -> Void)?

    private init() {}

    // MARK: - Инициализация (порт init())

    public func initialize(startWithSafeMode: Bool = false, completion: (() -> Void)? = nil) {
        // Подключаемся к точкам встраивания TelegramCore (инверсия зависимостей).
        PluginSendMessageHook.handler = { [weak self] payload in
            guard let self else { return payload }
            // Сначала — событийный хук (on_send_message_hook extera API)...
            let (modified, cancelled) = self.dispatchEvent("message.send.before", payload: payload)
            if cancelled { return nil }
            // ...потом xposed-стиль хуки Android-плагинов (SendMessagesHelper#sendMessage)
            return self.dispatchMethodHook(pointId: "message.send.before", args: modified ?? payload)
        }
        pluginsQueue.async {
            // Краш-прошлого-запуска → отключить виновника или safe mode.
            PluginStore.shared.resolveCrashState(startWithSafeMode: startWithSafeMode)
            PluginsWatchdog.shared.start()

            try? FileManager.default.createDirectory(at: self.pluginsDir, withIntermediateDirectories: true)

            PythonRuntime.shared.initialize { [weak self] ok in
                guard let self else { completion?(); return }
                if ok && !PluginStore.shared.safeMode {
                    self.loadAllPlugins()
                }
                self.initialized = true
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    public func shutdown(completion: (() -> Void)? = nil) {
        pluginsQueue.async {
            for id in self.plugins.keys { self.unloadPlugin(id) }
            PythonRuntime.shared.shutdown()
            PluginsWatchdog.shared.stop()
            self.plugins.removeAll()
            self.initialized = false
            DispatchQueue.main.async { completion?() }
        }
    }

    // MARK: - Загрузка плагинов (порт loadPlugins/loadPlugin)

    private func loadAllPlugins() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "plugin" {
            loadPlugin(file: file)
        }
        DispatchQueue.main.async { self.onPluginsChanged?() }
    }

    @discardableResult
    public func loadPlugin(file: URL) -> Plugin? {
        // Метаданные читаются Swift-парсером (regex по dunder-полям) — быстро
        // и без поднятия Python; Python поднимается только для исполнения.
        guard let meta = PluginMetadataParser.parse(file: file) else { return nil }
        let plugin = Plugin(id: meta.id, name: meta.name)
        plugin.version = meta.version
        plugin.descriptionText = meta.description
        plugin.author = meta.author
        plugin.icon = meta.icon
        plugin.appVersion = meta.appVersion
        plugin.sdkVersion = meta.sdkVersion
        plugin.requirements = meta.requirements
        plugin.setEnabled(PluginStore.shared.isPluginEnabled(meta.id))
        plugins[meta.id] = plugin

        if plugin.isEnabled {
            activatePlugin(plugin, file: file)
        }
        return plugin
    }

    /// Активация: pip-зависимости → импорт модуля → on_plugin_load → сбор хуков.
    private func activatePlugin(_ plugin: Plugin, file: URL) {
        guard !PluginStore.shared.safeMode else { return }
        do {
            try PluginPip.shared.installDependencies(plugin: plugin)
            try PythonRuntime.shared.loadPluginModule(pluginId: plugin.id, file: file)
            // on_plugin_load
            _ = PythonRuntime.shared.callPluginEvent(pluginId: plugin.id, event: "on_plugin_load", payload: [:])
            refreshHooksFromPython(pluginId: plugin.id)
        } catch {
            plugin.setError(error)
        }
    }

    /// Забирает из Python-инстанса зарегистрированные хуки/меню (JSON из _etg bridge).
    private func refreshHooksFromPython(pluginId: String) {
        guard let json = PythonRuntime.shared.dumpPluginHooks(pluginId: pluginId),
              let data = json.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // события
        if let events = map["events"] as? [[String: Any]] {
            for e in events {
                guard let name = e["name"] as? String else { continue }
                addEventHook(EventHook(
                    pluginId: pluginId,
                    hookName: name,
                    matchSubstring: e["match_substring"] as? Bool ?? false,
                    priority: e["priority"] as? Int ?? 0
                ))
            }
        }
        // xposed-стиль хуки методов — через таблицу совместимости
        if let methods = map["method_hooks"] as? [[String: Any]] {
            for m in methods {
                guard let className = m["class"] as? String, let method = m["method"] as? String else { continue }
                addMethodHook(MethodHook(
                    pluginId: pluginId,
                    androidClass: className,
                    androidMethod: method,
                    mode: MethodHook.Mode(rawValue: m["mode"] as? String ?? "before_after") ?? .beforeAfter
                ))
            }
        }
        // меню
        if let menus = map["menu_items"] as? [[String: Any]] {
            for mi in menus {
                guard let type = mi["menu_type"] as? String, let text = mi["text"] as? String else { continue }
                addMenuItem(PluginMenuItem(
                    pluginId: pluginId,
                    menuType: type,
                    text: text,
                    subtext: mi["subtext"] as? String,
                    iconName: mi["icon"] as? String,
                    itemId: mi["item_id"] as? String ?? UUID().uuidString,
                    priority: mi["priority"] as? Int ?? 0,
                    condition: mi["condition"] as? String
                ))
            }
        }
    }

    public func unloadPlugin(_ pluginId: String) {
        _ = PythonRuntime.shared.callPluginEvent(pluginId: pluginId, event: "on_plugin_unload", payload: [:])
        eventHooks = eventHooks.mapValues { $0.filter { $0.pluginId != pluginId } }
        methodHooks = methodHooks.mapValues { $0.filter { $0.pluginId != pluginId } }
        for key in menuItems.keys { menuItems[key]?.removeAll { $0.pluginId == pluginId } }
        interestedCache.removeAll()
        PythonRuntime.shared.unloadPluginModule(pluginId: pluginId)
        PluginPip.shared.removeDependencies(pluginId: pluginId)
    }

    // MARK: - Хуки событий (порт executeGenericHook)

    public func addEventHook(_ hook: EventHook) {
        eventHooks[hook.hookName, default: []].append(hook)
        eventHooks[hook.hookName]?.sort { $0.priority > $1.priority }
        interestedCache.removeAll()
    }

    /// Универсальный диспетчер: цепочка MODIFY → финальный объект; CANCEL — обрыв;
    /// MODIFY_FINAL — результат не уходит дальше по цепочке.
    /// payload/result — JSON-словари (универсальный контракт бриджа).
    @discardableResult
    public func dispatchEvent(_ name: String, payload: [String: Any]) -> (payload: [String: Any]?, cancelled: Bool) {
        guard initialized, !PluginStore.shared.safeMode else { return (payload, false) }
        var current: [String: Any]? = payload

        // точные + substring-подписчики
        var ids = interestedCache[name] ?? []
        if ids.isEmpty {
            var set = Set<String>()
            eventHooks[name].map { $0.pluginId }.forEach { set.insert($0) }
            for (hookName, hooks) in eventHooks where hooks.contains(where: { $0.matchSubstring }) {
                if hooks.contains(where: { $0.matchSubstring && name.contains($0.hookName) }) {
                    hooks.filter { $0.matchSubstring && name.contains($0.hookName) }.forEach { set.insert($0.pluginId) }
                }
            }
            ids = Array(set)
            interestedCache[name] = ids
        }

        for pluginId in ids {
            guard let plugin = plugins[pluginId], plugin.isEnabled, current != nil else { continue }
            PluginsWatchdog.shared.onPluginExecutionStarted(pluginId)
            defer { PluginsWatchdog.shared.onPluginExecutionFinished(pluginId) }

            let result = PythonRuntime.shared.callPluginEvent(pluginId: pluginId, event: name, payload: current ?? [:])
            guard let result else { continue }
            switch result.strategy {
            case .cancel:
                return (nil, true)
            case .modifyFinal:
                return (result.payload, false)
            case .modify:
                current = result.payload
            case .default:
                break
            }
        }
        return (current, false)
    }

    // MARK: - Хуки методов (Android-совместимость)

    public func addMethodHook(_ hook: MethodHook) {
        let iosPoint = AndroidCompatMap.resolve(androidClass: hook.androidClass, method: hook.androidMethod)
        if iosPoint == nil {
            AndroidCompatMap.logUnmapped(className: hook.androidClass, method: hook.androidMethod, pluginId: hook.pluginId)
        }
        methodHooks[hook.androidClass + "#" + hook.androidMethod, default: []].append(hook)
    }

    /// Вызывается из iOS-точек встраивания: pointId — идентификатор из AndroidCompatMap.
    @discardableResult
    public func dispatchMethodHook(pointId: String, args: [String: Any]) -> [String: Any]? {
        let androidKeys = AndroidCompatMap.androidKeys(for: pointId)
        var current: [String: Any]? = args
        for key in androidKeys {
            for hook in methodHooks[key] ?? [] {
                guard let plugin = plugins[hook.pluginId], plugin.isEnabled else { continue }
                PluginsWatchdog.shared.onPluginExecutionStarted(hook.pluginId)
                let res = PythonRuntime.shared.callPluginMethodHook(pluginId: hook.pluginId, className: hook.androidClass, method: hook.androidMethod, args: current ?? [:])
                PluginsWatchdog.shared.onPluginExecutionFinished(hook.pluginId)
                if let res { current = res }
            }
        }
        return current
    }

    // MARK: - Меню

    public func addMenuItem(_ item: PluginMenuItem) {
        menuItems[item.menuType, default: []].append(item)
        menuItems[item.menuType]?.sort { $0.priority > $1.priority }
    }

    public func menuItems(for menuType: String) -> [PluginMenuItem] {
        menuItems[menuType] ?? []
    }

    /// Нажатие пункта меню — проброс в Python.
    public func invokeMenuItem(_ item: PluginMenuItem, context: [String: Any]) {
        PluginsWatchdog.shared.onPluginExecutionStarted(item.pluginId)
        PythonRuntime.shared.callMenuItem(pluginId: item.pluginId, itemId: item.itemId, context: context)
        PluginsWatchdog.shared.onPluginExecutionFinished(item.pluginId)
    }

    // MARK: - Управление плагинами

    public func setPluginEnabled(_ pluginId: String, _ enabled: Bool) {
        pluginsQueue.async {
            guard let plugin = self.plugins[pluginId] else { return }
            PluginStore.shared.setPluginEnabled(pluginId, enabled)
            if enabled {
                let file = self.pluginsDir.appendingPathComponent(pluginId + ".plugin")
                if FileManager.default.fileExists(atPath: file.path) {
                    plugin.setError(nil)
                    plugin.setEnabled(true)
                    self.activatePlugin(plugin, file: file)
                }
            } else {
                plugin.setEnabled(false)
                self.unloadPlugin(pluginId)
            }
            DispatchQueue.main.async { self.onPluginsChanged?() }
        }
    }

    public func deletePlugin(_ pluginId: String, completion: ((String?) -> Void)? = nil) {
        pluginsQueue.async {
            self.unloadPlugin(pluginId)
            self.plugins.removeValue(forKey: pluginId)
            PluginStore.shared.setPluginEnabled(pluginId, false)
            PluginStore.shared.clearSettings(pluginId: pluginId)
            try? FileManager.default.removeItem(at: self.pluginsDir.appendingPathComponent(pluginId + ".plugin"))
            DispatchQueue.main.async {
                self.onPluginsChanged?()
                completion?(nil)
            }
        }
    }

    /// Установка из файла (плагин прислан документом в чат / через Files).
    public func installPlugin(from sourceURL: URL, completion: @escaping (Plugin?, Error?) -> Void) {
        pluginsQueue.async {
            do {
                guard let meta = PluginMetadataParser.parse(file: sourceURL) else {
                    throw PluginError.invalidMetadata
                }
                let dst = self.pluginsDir.appendingPathComponent(meta.id + ".plugin")
                if FileManager.default.fileExists(atPath: dst.path) {
                    self.unloadPlugin(meta.id)
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: sourceURL, to: dst)
                let plugin = self.loadPlugin(file: dst)
                DispatchQueue.main.async {
                    self.onPluginsChanged?()
                    completion(plugin, nil)
                }
            } catch {
                DispatchQueue.main.async { completion(nil, error) }
            }
        }
    }

    func markNotResponding(_ pluginId: String) {
        plugins[pluginId]?.isNotResponding = true
    }

    /// Изменение настройки из UI → проброс on_change в Python (если плагин слушает).
    public func notifySettingChanged(pluginId: String, key: String, value: Any) {
        pluginsQueue.async {
            _ = self.dispatchEvent("setting_changed", payload: [
                "plugin_id": pluginId, "key": key, "value": value,
            ])
        }
    }

    // MARK: - События приложения (app_start/app_resume/...)

    public func fireAppEvent(_ event: String) {
        pluginsQueue.async { [weak self] in
            self?.dispatchEvent("on_app_event", payload: ["event_type": event])
        }
    }
}

public enum PluginError: Error {
    case invalidMetadata
    case pythonNotAvailable
    case pipFailed(String)
}
