import Foundation

/// pip-зависимости плагинов. На iOS работает только pure-python pip
/// (нативных wheel для iOS нет). Установка: `python -m pip install --target <dir>`.
/// Зависимости изолированы per-plugin: Documents/plugins-deps/<pluginId>/.
public final class PluginPip {
    public static let shared = PluginPip()

    private var depsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plugins-deps", isDirectory: true)
    }

    public func installDependencies(plugin: Plugin) throws {
        guard !plugin.requirements.isEmpty else { return }
        let target = depsDir.appendingPathComponent(plugin.id, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let reqList = plugin.requirements.joined(separator: " ")
        let code = """
        import subprocess, sys
        r = subprocess.run([sys.executable, "-m", "pip", "install", "--target", "\(target.path)"] + "\(reqList)".split(), capture_output=True, text=True)
        print("__PIP_RC__" + str(r.returncode))
        if r.returncode != 0:
            print(r.stderr[-2000:])
        if "\(target.path)" not in sys.path:
            sys.path.insert(0, "\(target.path)")
        """
        let output = PythonRuntime.shared.exec(code) ?? ""
        guard output.contains("__PIP_RC__0") else {
            throw PluginError.pipFailed("pip install failed for \(reqList)")
        }
    }

    public func removeDependencies(pluginId: String) {
        try? FileManager.default.removeItem(at: depsDir.appendingPathComponent(pluginId))
    }
}
