import UIKit

/// Экран плагина: информация + сгенерированные настройки (create_settings).
/// Типы элементов совместимы с extera: header/text/switch/selector/input/
/// edit_text/divider/custom.
public final class PluginDetailController: UITableViewController {

    private let plugin: Plugin
    private var settingsSchema: [[String: Any]] = []

    public init(plugin: Plugin) {
        self.plugin = plugin
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = plugin.name
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(SwitchCell.self, forCellReuseIdentifier: "switch")
        loadSchema()
    }

    private func loadSchema() {
        // Схема настроек из Python-инстанса (create_settings), JSON через bridge.
        let json = PythonRuntime.shared.dumpPluginSettingsSchema(pluginId: plugin.id)
        if let json, let data = json.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            settingsSchema = arr
        }
        tableView.reloadData()
    }

    public override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Информация" : "Настройки"
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 4 }
        return settingsSchema.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var conf = cell.defaultContentConfiguration()
            switch indexPath.row {
            case 0: conf.text = "Версия"; conf.secondaryText = plugin.version
            case 1: conf.text = "Автор"; conf.secondaryText = plugin.author
            case 2: conf.text = "Описание"; conf.secondaryText = plugin.descriptionText
            default: conf.text = "ID"; conf.secondaryText = plugin.id
            }
            conf.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = conf
            cell.selectionStyle = .none
            return cell
        }
        let item = settingsSchema[indexPath.row]
        let type = item["type"] as? String ?? "text"
        let key = item["key"] as? String ?? ""
        let title = item["text"] as? String ?? key

        switch type {
        case "switch":
            let cell = tableView.dequeueReusableCell(withIdentifier: "switch", for: indexPath) as! SwitchCell
            cell.textLabel?.text = title
            let current = PluginStore.shared.getSetting(pluginId: plugin.id, key: key) as? Bool
                ?? item["default"] as? Bool ?? false
            cell.configure(on: current) { [weak self] value in
                guard let self else { return }
                PluginStore.shared.setSetting(pluginId: self.plugin.id, key: key, value: value)
                // on_change в Python
                PluginController.shared.notifySettingChanged(pluginId: self.plugin.id, key: key, value: value)
            }
            return cell
        case "divider":
            let cell = UITableViewCell()
            cell.backgroundColor = .clear
            cell.isUserInteractionEnabled = false
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var conf = cell.defaultContentConfiguration()
            conf.text = title
            if let subtext = item["subtext"] as? String { conf.secondaryText = subtext }
            cell.contentConfiguration = conf
            return cell
        }
    }
}

final class SwitchCell: UITableViewCell {
    private let sw = UISwitch()
    private var onChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        sw.addTarget(self, action: #selector(changed), for: .valueChanged)
        accessoryView = sw
        selectionStyle = .none
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(on: Bool, onChange: @escaping (Bool) -> Void) {
        sw.isOn = on
        self.onChange = onChange
    }

    @objc private func changed() { onChange?(sw.isOn) }
}
