import Foundation

/// Watchdog — порт PluginsWatchdog: обрамляет каждый вызов плагина,
/// ловит зависания (плагин "не отвечает") и маркирует виновника краша.
public final class PluginsWatchdog {
    public static let shared = PluginsWatchdog()

    /// Таймаут, после которого плагин считается зависшим (как в extera — неск. секунд).
    public var hangTimeout: TimeInterval = 5.0

    private let queue = DispatchQueue(label: "org.telegram.plugins.watchdog", attributes: .concurrent)
    private var running: [String: Date] = [:]
    private var timer: DispatchSourceTimer?
    private var started = false

    public func start() {
        queue.sync(flags: .barrier) {
            guard !self.started else { return }
            self.started = true
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            t.schedule(deadline: .now() + 1.0, repeating: 1.0)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
    }

    public func stop() {
        queue.sync(flags: .barrier) {
            self.timer?.cancel()
            self.timer = nil
            self.started = false
            self.running.removeAll()
        }
    }

    /// Вызывается ПЕРЕД исполнением кода плагина. Маркирует виновника:
    /// если процесс умрёт внутри плагина, на следующем запуске
    /// PluginStore.hadCrash == true и crashedPluginId укажет на него.
    public func onPluginExecutionStarted(_ pluginId: String) {
        PluginStore.shared.hadCrash = true
        PluginStore.shared.crashedPluginId = pluginId
        queue.async(flags: .barrier) { self.running[pluginId] = Date() }
    }

    /// Вызывается ПОСЛЕ успешного исполнения — маркер краша снимается.
    public func onPluginExecutionFinished(_ pluginId: String) {
        queue.async(flags: .barrier) { self.running.removeValue(forKey: pluginId) }
        if PluginStore.shared.crashedPluginId == pluginId {
            PluginStore.shared.hadCrash = false
            PluginStore.shared.crashedPluginId = nil
        }
    }

    private func tick() {
        queue.sync {
            let now = Date()
            for (pluginId, since) in running where now.timeIntervalSince(since) > hangTimeout {
                // Плагин висит в исполнении дольше таймаута.
                PluginController.shared.markNotResponding(pluginId)
            }
        }
    }
}
