import Foundation
import CPython
import ETGBridge

/// Результат вызова Python-события с применённой стратегией.
public struct PythonEventResult {
    public let strategy: HookStrategy
    public let payload: [String: Any]?
}

/// CPython-рантайм — аналог Chaquopy на Android.
/// Встраивает интерпретатор, регистрирует нативный модуль _etg,
/// гоняет плагины из Documents/plugins.
public final class PythonRuntime {
    public static let shared = PythonRuntime()

    private var started = false
    private let lock = NSRecursiveLock()

    /// Папка SDK: Documents/plugins-sdk/python (stdlib + extera_compat).
    private var sdkDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plugins-sdk", isDirectory: true)
    }

    private init() {}

    // MARK: - Жизненный цикл

    public func initialize(completion: @escaping (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { completion(true); return }

        // 1. Распаковка SDK из бандла (stdlib.zip + extera_compat)
        do { try unpackSdkIfNeeded() } catch {
            FileLogger.log("PluginsEngine: SDK unpack failed: \(error)")
            completion(false); return
        }

        // 2. Нативный модуль _etg ДО Py_Initialize
        etg_set_swift_callback(etgSwiftCallback)
        etg_register_module()

        // 3. Конфигурация интерпретатора
        var config = PyConfig()
        PyConfig_InitIsolatedConfig(&config)
        let pythonHome = sdkDir.appendingPathComponent("python").path
        pythonHome.withCString { cstr in
            PyConfig_SetBytesString(&config, &config.home, cstr)
        }
        config.buffered_stdio = 0
        config.write_bytecode = 0 // на iOS нельзя писать __pycache__ в бандл
        config.no_site = 1

        let status = Py_InitializeFromConfig(&config)
        PyConfig_Clear(&config)
        if PyStatus_Exception(status) != 0 {
            FileLogger.log("PluginsEngine: Py_Initialize failed")
            completion(false); return
        }

        // 4. sys.path: плагины + корень SDK (там лежит пакет extera_compat)
        let pluginsPath = PluginController.shared.pluginsDir.path
        let sdkPythonPath = sdkDir.appendingPathComponent("python").path
        PyRun_SimpleString("""
        import sys
        for p in ["\(pluginsPath)", "\(sdkPythonPath)"]:
            if p not in sys.path:
                sys.path.insert(0, p)
        """)

        started = true
        FileLogger.log("PluginsEngine: Python runtime started")
        completion(true)
    }

    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return }
        Py_FinalizeEx()
        started = false
    }

    // MARK: - Плагины

    /// Импортирует модуль плагина (id == имя модуля) и инстанцирует класс
    /// BasePlugin — аналог createPluginInstance extera (_findPluginClass).
    public func loadPluginModule(pluginId: String, file: URL) throws {
        try withGIL {
            let code = """
            import importlib.util, importlib.machinery, sys
            sys.modules.pop("\(pluginId)", None)
            importlib.invalidate_caches()
            _loader = importlib.machinery.SourceFileLoader("\(pluginId)", r"\(file.path)")
            _spec = importlib.util.spec_from_loader("\(pluginId)", _loader)
            _mod = importlib.util.module_from_spec(_spec)
            sys.modules["\(pluginId)"] = _mod
            _loader.exec_module(_mod)
            from extera_compat.base_plugin import BasePlugin, _register_instance
            _cls = BasePlugin._findPluginClass(_mod)
            if _cls is None:
                raise RuntimeError("Could not find a class inheriting from BasePlugin in \(pluginId).plugin. Make sure your main plugin class extends BasePlugin.")
            _inst = _cls()
            _inst._plugin_id = "\(pluginId)"
            _register_instance(_mod, _inst)
            """
            if PyRun_SimpleString(code) != 0 {
                PyErr_Print()
                throw PluginError.pythonNotAvailable
            }
        }
    }

    public func unloadPluginModule(pluginId: String) {
        try? withGIL {
            PyRun_SimpleString("""
            import sys
            sys.modules.pop("\(pluginId)", None)
            import importlib; importlib.invalidate_caches()
            """)
        }
    }

    /// Вызов события плагина. Возвращает стратегию+payload.
    /// Контракт: у инстанса BasePlugin вызывается dispatch_event(name, payload_json)
    /// → возвращает JSON {"strategy": "...", "payload": {...}}.
    public func callPluginEvent(pluginId: String, event: String, payload: [String: Any]) -> PythonEventResult? {
        guard started, !PluginStore.shared.safeMode else { return nil }
        guard let payloadJson = toJson(payload) else { return nil }
        var result: PythonEventResult?
        try? withGIL {
            guard let json = runEval("""
            import json, sys
            _m = sys.modules.get("\(pluginId)")
            _inst = getattr(_m, "__plugin_instance__", None) if _m else None
            if _inst is None:
                print("null")
            else:
                print(json.dumps(_inst.dispatch_event("\(escapeForPythonString(event))", '''\(payloadJson)''')))
            """) else { return }
            result = parseEventResult(json)
        }
        return result
    }

    /// Вызов xposed-стиль хука метода.
    public func callPluginMethodHook(pluginId: String, className: String, method: String, args: [String: Any]) -> [String: Any]? {
        guard started, let argsJson = toJson(args) else { return nil }
        var out: [String: Any]?
        try? withGIL {
            guard let json = runEval("""
            import json, sys
            _m = sys.modules.get("\(pluginId)")
            _inst = getattr(_m, "__plugin_instance__", None) if _m else None
            if _inst is None:
                print("null")
            else:
                print(json.dumps(_inst.dispatch_method_hook("\(escapeForPythonString(className))", "\(escapeForPythonString(method))", '''\(argsJson)''')))
            """) else { return }
            out = fromJsonDict(json)
        }
        return out
    }

    public func callMenuItem(pluginId: String, itemId: String, context: [String: Any]) {
        guard started, let ctxJson = toJson(context) else { return }
        try? withGIL {
            PyRun_SimpleString("""
            import sys, json
            _m = sys.modules.get("\(pluginId)")
            _inst = getattr(_m, "__plugin_instance__", None) if _m else None
            if _inst is not None:
                _inst.dispatch_menu_click("\(escapeForPythonString(itemId))", json.loads('''\(ctxJson)'''))
            """)
        }
    }

    /// JSON-дамп зарегистрированных хуков/меню плагина после загрузки.
    public func dumpPluginHooks(pluginId: String) -> String? {
        guard started else { return nil }
        var out: String?
        try? withGIL {
            out = runEval("""
            import sys, json
            _m = sys.modules.get("\(pluginId)")
            _inst = getattr(_m, "__plugin_instance__", None) if _m else None
            print(json.dumps(_inst.dump_hooks() if _inst is not None else {}))
            """)
        }
        return out
    }

    /// Публичный exec для служебных задач (pip и т.п.). Возвращает stdout.
    public func exec(_ code: String) -> String? {
        guard started else { return nil }
        var out: String?
        try? withGIL { out = runEvalRaw(code) }
        return out
    }

    /// JSON схемы настроек (create_settings) плагина.
    public func dumpPluginSettingsSchema(pluginId: String) -> String? {
        guard started else { return nil }
        var out: String?
        try? withGIL {
            out = runEval("""
            import sys, json
            _m = sys.modules.get("\(pluginId)")
            _inst = getattr(_m, "__plugin_instance__", None) if _m else None
            print(json.dumps(_inst.dump_hooks().get("settings", []) if _inst is not None else []))
            """)
        }
        return out
    }

    // MARK: - internals

    private func withGIL(_ body: () throws -> Void) throws {
        guard started else { throw PluginError.pythonNotAvailable }
        let state = PyGILState_Ensure()
        defer { PyGILState_Release(state) }
        try body()
    }

    /// Выполняет код и возвращает ВЕСЬ stdout (для pip и диагностики).
    private func runEvalRaw(_ code: String) -> String? {
        let tmp = NSTemporaryDirectory() + "etg_py_\(UUID().uuidString).out"
        let oldStdout = dup(STDOUT_FILENO)
        let oldStderr = dup(STDERR_FILENO)
        fflush(nil)
        let fd = open(tmp, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        dup2(fd, STDOUT_FILENO)
        dup2(fd, STDERR_FILENO)
        PyRun_SimpleString(code)
        fflush(nil)
        dup2(oldStdout, STDOUT_FILENO); dup2(oldStderr, STDERR_FILENO)
        close(oldStdout); close(oldStderr); close(fd)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        return try? String(contentsOfFile: tmp)
    }

    /// Выполняет код и возвращает последнюю print-строку (stdout перехвачен).
    private func runEval(_ code: String) -> String? {
        let wrapper = """
        import io, contextlib
        _buf = io.StringIO()
        with contextlib.redirect_stdout(_buf):
        \(code.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n"))
        print("__ETG_RESULT__" + _buf.getvalue().strip().split("\\n")[-1])
        """
        // stdout идёт в NSLog — читаем через перехват: проще — выполнить и забрать
        // через временный файл. На iOS чтение своего stdout надёжнее файлом.
        let tmp = NSTemporaryDirectory() + "etg_py_\(UUID().uuidString).out"
        let oldStdout = dup(STDOUT_FILENO)
        let oldStderr = dup(STDERR_FILENO)
        fflush(nil)
        let fd = open(tmp, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        dup2(fd, STDOUT_FILENO)
        dup2(fd, STDERR_FILENO)
        PyRun_SimpleString(wrapper)
        fflush(nil)
        dup2(oldStdout, STDOUT_FILENO); dup2(oldStderr, STDERR_FILENO)
        close(oldStdout); close(oldStderr); close(fd)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        guard let raw = try? String(contentsOfFile: tmp),
              let line = raw.components(separatedBy: "__ETG_RESULT__").last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty, line != "null" else { return nil }
        return line
    }

    private func parseEventResult(_ json: String) -> PythonEventResult? {
        guard let dict = fromJsonDict(json) else { return nil }
        let strategy = HookStrategy(rawValue: dict["strategy"] as? String ?? "DEFAULT") ?? .default
        return PythonEventResult(strategy: strategy, payload: dict["payload"] as? [String: Any])
    }

    private func escapeForPythonString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func toJson(_ dict: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "'''", with: "\\'\\'\\'")
    }

    private func fromJsonDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    // MARK: - SDK unpack

    private func unpackSdkIfNeeded() throws {
        let fm = FileManager.default
        let marker = sdkDir.appendingPathComponent("v.txt")
        // plugins-sdk.tar лежит в корне бандла (resources плющат структуру).
        let bundleRoot = Bundle.main.bundleURL
        let candidates = [
            bundleRoot.appendingPathComponent("plugins-sdk.tar"),
            bundleRoot.appendingPathComponent("Frameworks/PluginsEngine.framework/plugins-sdk.tar"),
        ]
        guard let tarURL = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            throw PluginError.pythonNotAvailable
        }
        // Версия SDK внутри tar (v.txt наверху архива) — сравниваем с распакованной.
        let installedV = (try? String(contentsOf: marker)) ?? ""
        if !installedV.isEmpty, fm.fileExists(atPath: sdkDir.appendingPathComponent("python").path) { return }

        if fm.fileExists(atPath: sdkDir.path) { try fm.removeItem(at: sdkDir) }
        try TarUnpacker.unpack(tarAt: tarURL, to: sdkDir)
    }
}

/// Простой файловый логгер движка (Documents/plugins-engine.log).
public enum FileLogger {
    public static func log(_ message: String) {
        NSLog("PluginsEngine: %@", message)
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("plugins-engine.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path), let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Swift-колбэк для _etg.call — точка входа ВСЕХ запросов из Python в приложение.
/// Команды: send_message, edit_message, get_setting, set_setting, log, ...
private func etgSwiftCallback(command: UnsafePointer<CChar>, payload: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    let cmd = String(cString: command)
    let payloadStr = String(cString: payload)
    let response = ETGBridgeDispatcher.shared.handle(command: cmd, payloadJson: payloadStr)
    return strdup(response)
}
