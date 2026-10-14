import Foundation
import UIKit

/// Диспетчер команд Python→Swift. Команды — JSON-контракт, ответы — JSON.
/// Реальная интеграция с TelegramCore/TelegramUI делается через
/// внедряемые обработчики (handlers): приложение регистрирует их при старте.
/// Так модуль остаётся самодостаточным и компилируется отдельно.
public final class ETGBridgeDispatcher {
    public static let shared = ETGBridgeDispatcher()

    public typealias Handler = ([String: Any]) -> [String: Any]
    private var handlers: [String: Handler] = [:]
    private let lock = NSLock()

    private init() {
        registerBuiltinHandlers()
    }

    public func register(_ command: String, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers[command] = handler
    }

    public func handle(command: String, payloadJson: String) -> String {
        let payload = (try? JSONSerialization.jsonObject(with: Data(payloadJson.utf8))) as? [String: Any] ?? [:]
        lock.lock(); let handler = handlers[command]; lock.unlock()
        let response: [String: Any]
        if let handler {
            response = handler(payload)
        } else {
            response = ["ok": false, "error": "unknown command: \(command)"]
        }
        guard JSONSerialization.isValidJSONObject(response),
              let data = try? JSONSerialization.data(withJSONObject: response),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"response serialization failed\"}"
        }
        return str
    }

    private func registerBuiltinHandlers() {
        // --- настройки плагинов (PluginStore) ---
        register("get_setting") { payload in
            guard let pluginId = payload["plugin_id"] as? String,
                  let key = payload["key"] as? String else { return ["ok": false] }
            let value = PluginStore.shared.getSetting(pluginId: pluginId, key: key) ?? payload["default"] as Any
            return ["ok": true, "value": value]
        }
        register("set_setting") { payload in
            guard let pluginId = payload["plugin_id"] as? String,
                  let key = payload["key"] as? String else { return ["ok": false] }
            PluginStore.shared.setSetting(pluginId: pluginId, key: key, value: payload["value"])
            return ["ok": true]
        }
        register("get_all_settings") { payload in
            guard let pluginId = payload["plugin_id"] as? String else { return ["ok": false] }
            return ["ok": true, "value": PluginStore.shared.allSettings(pluginId: pluginId)]
        }
        register("clear_settings") { payload in
            if let pluginId = payload["plugin_id"] as? String {
                PluginStore.shared.clearSettings(pluginId: pluginId)
            }
            return ["ok": true]
        }
        // --- логирование ---
        register("log") { payload in
            FileLogger.log("[plugin \(payload["plugin_id"] ?? "")] \(payload["message"] ?? "")")
            return ["ok": true]
        }
        // --- события приложения (проброс в контроллер) ---
        register("register_hook") { payload in
            guard let pluginId = payload["plugin_id"] as? String,
                  let name = payload["name"] as? String else { return ["ok": false] }
            PluginController.shared.addEventHook(EventHook(
                pluginId: pluginId,
                hookName: name,
                matchSubstring: payload["match_substring"] as? Bool ?? false,
                priority: payload["priority"] as? Int ?? 0
            ))
            return ["ok": true]
        }
        // --- UI ---
        register("show_alert") { payload in
            let title = payload["title"] as? String ?? ""
            let text = payload["text"] as? String ?? ""
            DispatchQueue.main.async { PluginUIFacade.showAlert(title: title, text: text) }
            return ["ok": true]
        }
        register("show_bulletin") { payload in
            let text = payload["text"] as? String ?? ""
            DispatchQueue.main.async { PluginUIFacade.showBulletin(text: text) }
            return ["ok": true]
        }
    }
}

/// Фасад UI-уведомлений — реализация инжектится из TelegramUI.
public enum PluginUIFacade {
    public static var showAlertImpl: ((String, String) -> Void)?
    public static var showBulletinImpl: ((String) -> Void)?

    public static func showAlert(title: String, text: String) {
        if let showAlertImpl { showAlertImpl(title, text); return }
        // Фолбэк: системный UIAlertController поверх верхнего контроллера.
        guard let top = topViewController() else { return }
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        top.present(alert, animated: true)
    }

    public static func showBulletin(text: String) {
        if let showBulletinImpl { showBulletinImpl(text); return }
        showAlert(title: nil2title, text: text)
    }

    private static let nil2title = ""

    /// Открывает менеджер плагинов поверх текущего экрана (чистый UIKit,
    /// без привязки к Display/ViewController Telegram).
    public static func presentPluginsList() {
        guard let top = topViewController() else { return }
        let nav = UINavigationController(rootViewController: PluginsListController())
        nav.modalPresentationStyle = .pageSheet
        top.present(nav, animated: true)
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base {
            root = base
        } else {
            root = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first
        }
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}
