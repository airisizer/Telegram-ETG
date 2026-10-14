import UIKit

/// Список плагинов — порт ui/PluginsActivity (упрощённый UIKit-вариант).
/// Свитч вкл/выкл, свайп — удалить, плюс — установка из Files.
public final class PluginsListController: UITableViewController {

    private var items: [Plugin] = []

    public init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Плагины"
        tableView.register(PluginCell.self, forCellReuseIdentifier: "PluginCell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        reload()
        PluginController.shared.onPluginsChanged = { [weak self] in self?.reload() }
    }

    private func reload() {
        items = PluginController.shared.plugins.values.sorted { $0.name < $1.name }
        tableView.reloadData()
    }

    @objc private func addTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Table

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PluginCell", for: indexPath) as! PluginCell
        let plugin = items[indexPath.row]
        cell.configure(plugin: plugin)
        cell.onToggle = { [weak self] enabled in
            PluginController.shared.setPluginEnabled(plugin.id, enabled)
        }
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let plugin = items[indexPath.row]
        let vc = PluginDetailController(plugin: plugin)
        navigationController?.pushViewController(vc, animated: true)
    }

    public override func tableView(_ tableView: UITableView,
                                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        let plugin = items[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, done in
            PluginController.shared.deletePlugin(plugin.id) { _ in done(true) }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension PluginsListController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let needStop = url.startAccessingSecurityScopedResource()
        defer { if needStop { url.stopAccessingSecurityScopedResource() } }
        // Копируем во временную папку — security-scoped URL живёт недолго
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
        } catch {
            PluginUIFacade.showAlert(title: "Ошибка", text: "Не удалось прочитать файл")
            return
        }
        PluginController.shared.installPlugin(from: tmp) { [weak self] plugin, error in
            if let error {
                PluginUIFacade.showAlert(title: "Плагин не установлен", text: "\(error.localizedDescription)")
            } else {
                PluginUIFacade.showBulletin(text: "Плагин «\(plugin?.name ?? "")» установлен")
                self?.reload()
            }
        }
    }
}

final class PluginCell: UITableViewCell {
    private let toggle = UISwitch()
    var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        accessoryView = toggle
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(plugin: Plugin) {
        textLabel?.text = plugin.name + (plugin.hasError ? " ⚠️" : "")
        detailTextLabel?.text = plugin.hasError
            ? "Ошибка: \(plugin.error?.localizedDescription ?? "")"
            : "v\(plugin.version) · \(plugin.author)"
        toggle.isOn = plugin.isEnabled
        detailTextLabel?.numberOfLines = 2
    }

    @objc private func toggled() { onToggle?(toggle.isOn) }
}
