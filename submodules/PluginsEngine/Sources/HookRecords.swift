import Foundation

/// Хук события — порт hooks/EventHookRecord.
public struct EventHook {
    public let pluginId: String
    public let hookName: String
    public let matchSubstring: Bool
    public let priority: Int
}

/// Xposed-стиль хук метода — порт hooks/XposedHookRecord.
/// androidClass/androidMethod — имена из мира Android-плагинов;
/// реальная привязка к iOS — через AndroidCompatMap.
public struct MethodHook {
    public enum Mode: String {
        case before = "before"
        case after = "after"
        case beforeAfter = "before_after"
        case replace = "replace"
    }
    public let pluginId: String
    public let androidClass: String
    public let androidMethod: String
    public let mode: Mode
}

/// Пункт меню — порт hooks/MenuItemRecord.
/// condition — MVEL-подобное выражение в extera; на iOS вычисляется
/// упрощённым предикатом (NSPredicate) — см. evaluate().
public struct PluginMenuItem {
    public let pluginId: String
    public let menuType: String      // main_menu/drawer_menu/chat_action_menu/message_context_menu/profile_action_menu
    public let text: String
    public let subtext: String?
    public let iconName: String?
    public let itemId: String
    public let priority: Int
    public let condition: String?

    /// Упрощённая оценка condition: поддержка `key == value`, `key != value`,
    /// `key` (truthy), `!key`. Полный MVEL на iOS не тащим.
    public func evaluate(context: [String: Any]) -> Bool {
        guard let condition, !condition.isEmpty else { return true }
        let expr = condition.trimmingCharacters(in: .whitespaces)
        if let not = expr.stripPrefix("!") {
            return !(context[not.trimmingCharacters(in: .whitespaces)] as? Bool ?? false)
        }
        let parts = expr.components(separatedBy: "==").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 {
            let rhs = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return "\(context[parts[0]] ?? "")" == rhs
        }
        let neq = expr.components(separatedBy: "!=").map { $0.trimmingCharacters(in: .whitespaces) }
        if neq.count == 2 {
            let rhs = neq[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return "\(context[neq[0]] ?? "")" != rhs
        }
        return context[expr] as? Bool ?? false
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
