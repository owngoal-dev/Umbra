import UIKit

enum ManagedService: String, CaseIterable {
    case openssh, dropbear, frida

    var title: String {
        switch self {
        case .openssh: return "OpenSSH"
        case .dropbear: return "Dropbear"
        case .frida: return "Frida"
        }
    }

    var symbol: String {
        switch self {
        case .openssh: return "terminal.fill"
        case .dropbear: return "key.fill"
        case .frida: return "ladybug.fill"
        }
    }

    var defaultPorts: [Int] {
        switch self {
        case .openssh: return [22, 2222]
        case .dropbear: return [44]
        case .frida: return [27042]
        }
    }

    static var installed: [ManagedService] {
        RHServicePorts.installedServices().compactMap(ManagedService.init(rawValue:))
    }

    var portSummary: String {
        guard let ports = try? RHServicePorts.ports(for: rawValue) else {
            return localized("Port settings unavailable")
        }
        let separator =
            Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? "、" : ", "
        return String(
            format: localized("Listening on %@"),
            ports.map(\.stringValue).joined(separator: separator))
    }
}

func presentServicePorts(
    _ service: ManagedService, from controller: UIViewController, onSave: @escaping () -> Void
) {
    guard controller.presentedViewController == nil else { return }
    let form = ServicePortsViewController(service: service, onSave: onSave)
    let navigation = UINavigationController(rootViewController: form)
    navigation.modalPresentationStyle = .formSheet
    controller.present(navigation, animated: true) { form.focusFirstPort() }
}

final class ServicePortsViewController: UITableViewController {
    private let service: ManagedService
    private let onSave: () -> Void
    private let backupSwitch = UISwitch()
    private var fields: [UITextField] = []
    private var originalPorts: [Int] = []
    private var loadError: String?
    private var isSaving = false
    private var saveButton: UIBarButtonItem!

    init(service: ManagedService, onSave: @escaping () -> Void) {
        self.service = service
        self.onSave = onSave
        super.init(style: .insetGrouped)
        title = service.title
        do {
            originalPorts = try RHServicePorts.ports(for: service.rawValue).map(\.intValue)
        } catch {
            loadError = error.localizedDescription
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = AppTheme.tint
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.keyboardDismissMode = .onDrag
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: localized("Cancel"), style: .plain, target: self, action: #selector(cancel))
        saveButton = UIBarButtonItem(
            title: localized("Save"), style: .done, target: self, action: #selector(save))
        if loadError == nil {
            navigationItem.rightBarButtonItem = saveButton
            var ports = originalPorts
            if service == .openssh && ports.count == 1 {
                ports.append(RHServicePorts.opensshBackupPort().intValue)
            }
            fields = ports.enumerated().map { index, port in
                let field = UITextField()
                field.text = String(port)
                field.placeholder = String(service.defaultPorts[index])
                field.keyboardType = .numberPad
                field.textAlignment = .right
                field.font = .preferredFont(forTextStyle: .body)
                field.adjustsFontForContentSizeCategory = true
                field.accessibilityLabel =
                    service == .openssh
                    ? localized(index == 0 ? "Primary Port" : "Backup Port") : localized("Port")
                field.addTarget(self, action: #selector(updateSaveButton), for: .editingChanged)
                return field
            }
            backupSwitch.isOn = originalPorts.count == 2
            backupSwitch.addTarget(self, action: #selector(toggleBackup), for: .valueChanged)
            updateSaveButton()
        }
    }

    fileprivate func focusFirstPort() {
        fields.first?.becomeFirstResponder()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        service == .openssh && loadError == nil ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 1 && backupSwitch.isOn ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        service == .openssh
            ? localized(section == 0 ? "Primary Port" : "Backup Port")
            : localized("Listening Port")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int)
        -> String?
    {
        guard loadError == nil, section == numberOfSections(in: tableView) - 1 else { return nil }
        return localized("Saving restarts active services. Use the new ports to reconnect.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        let cell = detailCell(in: tableView, reuseIdentifier: "Port")
        cell.selectionStyle = .none
        cell.accessoryView = nil
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        if let loadError {
            content.text = loadError
            content.textProperties.color = .secondaryLabel
        } else if indexPath.section == 1 && indexPath.row == 0 {
            content.text = localized("Enabled")
            cell.accessoryView = backupSwitch
        } else {
            content.text = localized("Port")
            let field = fields[indexPath.section]
            field.frame = CGRect(
                x: 0, y: 0, width: max(100, tableView.bounds.width * 0.32),
                height: max(36, field.font!.lineHeight + 12))
            cell.accessoryView = field
        }
        cell.contentConfiguration = content
        return cell
    }

    private var requestedPorts: [Int]? {
        let activeFields =
            service == .openssh && !backupSwitch.isOn ? Array(fields.prefix(1)) : fields
        var ports: [Int] = []
        for field in activeFields {
            let value = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                let port = Int(value), (1...65535).contains(port)
            else { return nil }
            ports.append(port)
        }
        return ports
    }

    @objc private func updateSaveButton() {
        saveButton.isEnabled =
            !isSaving && (requestedPorts == nil || requestedPorts != originalPorts)
    }

    @objc private func toggleBackup() {
        if !backupSwitch.isOn { fields[1].resignFirstResponder() }
        let row = IndexPath(row: 1, section: 1)
        if backupSwitch.isOn {
            tableView.insertRows(at: [row], with: .fade)
        } else {
            tableView.deleteRows(at: [row], with: .fade)
        }
        updateSaveButton()
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        guard !isSaving else { return }
        guard let ports = requestedPorts else {
            showMessage(
                localized("Enter a port from 1 to 65535."),
                title: localized("Could not save service ports."), from: self)
            return
        }
        guard Set(ports).count == ports.count else {
            showMessage(
                localized("Each port must be different."),
                title: localized("Could not save service ports."), from: self)
            return
        }
        view.endEditing(true)
        isSaving = true
        navigationController?.isModalInPresentation = true
        for field in fields { field.isEnabled = false }
        backupSwitch.isEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.accessibilityLabel = localized("Saving…")
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try RHServicePorts.setPorts(
                    ports.map { NSNumber(value: $0) }, for: self.service.rawValue)
            }
            DispatchQueue.main.async {
                self.isSaving = false
                self.navigationController?.isModalInPresentation = false
                for field in self.fields { field.isEnabled = true }
                self.backupSwitch.isEnabled = true
                self.navigationItem.leftBarButtonItem?.isEnabled = true
                self.navigationItem.rightBarButtonItem = self.saveButton
                self.updateSaveButton()
                switch result {
                case .success:
                    self.onSave()
                    self.dismiss(animated: true)
                case .failure(let error):
                    showMessage(
                        error.localizedDescription,
                        title: localized("Could not save service ports."), from: self)
                }
            }
        }
    }
}
