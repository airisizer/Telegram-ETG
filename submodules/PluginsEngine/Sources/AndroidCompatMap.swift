import Foundation

/// Таблица совместимости Android→iOS: маппит hook_method("org.telegram.X","y")
/// из Android-плагинов на реальные точки встраивания в Telegram-iOS.
///
/// Модель: iOS-точки встраивания имеют стабильные pointId (см. HookPoints.swift).
/// Плагин хукает Android-класс#метод → мы резолвим в pointId. Если маппинга
/// нет — хук регистрируется, но не срабатывает (no-op) и пишется в лог,
/// чтобы таблицу можно было дополнять по факту (файл Documents/plugins-unmapped.log).
public enum AndroidCompatMap {

    /// android "class#method" -> iOS pointId
    /// Точки iOS (стабильный контракт, встраиваются в код Telegram-iOS):
    ///   message.send.before      — перед отправкой сообщения (EnqueueMessage)
    ///   message.receive          — входящее сообщение/апдейт
    ///   updates.container        — контейнер updates
    ///   request.pre / request.post — до/после MTProto-запроса
    ///   chat.open                — открыт чат
    ///   app.event                — события приложения
    private static let table: [String: String] = [
        // --- отправка сообщений ---
        "org.telegram.messenger.SendMessagesHelper#sendMessage": "message.send.before",
        "org.telegram.messenger.SendMessagesHelper$SendMessageParams#": "message.send.before",
        // --- входящие ---
        "org.telegram.messenger.MessagesController#processUpdates": "updates.container",
        "org.telegram.messenger.MessagesController#processUpdateArray": "updates.container",
        // --- UI чата (частично маппимо) ---
        "org.telegram.ui.ChatActivity#onResume": "chat.open",
        "org.telegram.ui.ChatActivity#didSendMessage": "message.send.before",
    ]

    /// Обратный индекс: pointId -> список android-ключей (для dispatchMethodHook).
    private static var reverse: [String: [String]] = {
        var r: [String: [String]] = [:]
        for (k, v) in table { r[v, default: []].append(k) }
        return r
    }()

    public static func resolve(androidClass: String, method: String) -> String? {
        if let direct = table["\(androidClass)#\(method)"] { return direct }
        // пробуем префиксные правила (класс целиком)
        for (k, v) in table where k.hasPrefix(androidClass + "#") { return v }
        return nil
    }

    public static func androidKeys(for pointId: String) -> [String] {
        reverse[pointId] ?? []
    }

    /// Журнал незамапленных хуков — чтобы видеть, что дописывать в таблицу.
    public static func logUnmapped(className: String, method: String, pluginId: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(pluginId)] \(className)#\(method)\n"
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logURL = docs.appendingPathComponent("plugins-unmapped.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
