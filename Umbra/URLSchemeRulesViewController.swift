import UIKit

final class URLSchemeRulesViewController: UITableViewController {
    private var rules: [URLSchemeRule] = []
    private var loadError: String?

    init() {
        super.init(style: .insetGrouped)
        title = localized("URL Scheme Replacements")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addRule))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshRules),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        refreshRules()
    }

    @objc private func refreshRules() {
        do {
            rules = try URLSchemeRules.load()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        navigationItem.rightBarButtonItem?.isEnabled = loadError == nil
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        loadError != nil ? 1 : max(1, rules.count)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        localized("Replacement Rules")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int)
        -> String?
    {
        localized("Replacement rules do not apply to blacklisted apps.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        let cell = detailCell(in: tableView)
        cell.accessoryView = nil
        cell.accessibilityValue = nil
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 16, leading: 20, bottom: 16, trailing: 20)
        if let loadError {
            content.text = loadError
            content.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else if rules.isEmpty {
            content.text = localized("No replacement rules")
            content.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            let rule = rules[indexPath.row]
            content.text = rule.title
            cell.selectionStyle = .default
            let toggle = UISwitch()
            toggle.isOn = rule.enabled
            toggle.accessibilityLabel = rule.title
            toggle.addAction(
                UIAction { [weak self, weak toggle] _ in
                    guard let self, let toggle,
                        let row = self.rules.firstIndex(where: { $0.source == rule.source })
                    else { return }
                    var updated = self.rules[row]
                    updated.enabled = toggle.isOn
                    do {
                        try URLSchemeRules.save(updated, replacing: rule.source)
                        self.rules[row] = updated
                    } catch {
                        toggle.setOn(self.rules[row].enabled, animated: true)
                        showMessage(
                            error.localizedDescription, title: localized("Could not save changes"),
                            from: self)
                    }
                }, for: .valueChanged)
            cell.accessoryView = toggle
        }
        cell.contentConfiguration = content
        return cell
    }

    @objc private func addRule() { edit(nil) }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard loadError == nil, !rules.isEmpty else { return }
        edit(rules[indexPath.row])
    }

    private func edit(_ rule: URLSchemeRule?) {
        let form = URLSchemeRuleForm(rule: rule) { [weak self] in self?.refreshRules() }
        let navigation = UINavigationController(rootViewController: form)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true) { form.focusSource() }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        loadError == nil && !rules.isEmpty
    }

    override func tableView(
        _ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        do {
            try URLSchemeRules.remove(rules[indexPath.row].source)
            rules.remove(at: indexPath.row)
            if rules.isEmpty {
                tableView.reloadRows(at: [indexPath], with: .fade)
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        } catch {
            showMessage(
                error.localizedDescription, title: localized("Could not save changes"), from: self)
        }
    }
}

private final class URLSchemeRuleForm: UITableViewController {
    private let original: URLSchemeRule?
    private let onSave: () -> Void
    private let source = UITextField()
    private let target = UITextField()

    init(rule: URLSchemeRule?, onSave: @escaping () -> Void) {
        original = rule
        self.onSave = onSave
        super.init(style: .insetGrouped)
        title = localized(rule == nil ? "Add Replacement Rule" : "Edit Replacement Rule")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: localized("Cancel"), style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: localized("Save"), style: .done, target: self, action: #selector(save))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.keyboardDismissMode = .onDrag
        source.text = original?.source
        source.placeholder = "filza"
        source.accessibilityLabel = localized("Source Scheme")
        target.text = original?.target
        target.placeholder = "fila"
        target.accessibilityLabel = localized("Target Scheme")
        source.returnKeyType = .next
        target.returnKeyType = .done
        source.addAction(
            UIAction { [weak self] _ in self?.target.becomeFirstResponder() },
            for: .editingDidEndOnExit)
        target.addTarget(self, action: #selector(save), for: .editingDidEndOnExit)
        for field in [source, target] {
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textAlignment = .right
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
        }
    }

    func focusSource() { source.becomeFirstResponder() }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        localized("URL Schemes")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int)
        -> String?
    {
        localized("Replace only the App scheme. Paths and parameters stay unchanged.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        let cell = detailCell(in: tableView)
        cell.selectionStyle = .none
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        let field = indexPath.row == 0 ? source : target
        content.text = localized(indexPath.row == 0 ? "Source Scheme" : "Target Scheme")
        field.frame = CGRect(
            x: 0, y: 0, width: max(130, tableView.bounds.width * 0.38),
            height: max(36, field.font!.lineHeight + 12))
        cell.accessoryView = field
        cell.contentConfiguration = content
        return cell
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        guard let source = URLSchemeRules.normalize(source.text),
            let target = URLSchemeRules.normalize(target.text)
        else {
            showMessage(
                localized("Enter a custom App scheme, such as filza."),
                title: localized("Could not save changes"), from: self)
            return
        }
        do {
            try URLSchemeRules.save(
                URLSchemeRule(source: source, target: target, enabled: original?.enabled ?? true),
                replacing: original?.source)
            onSave()
            dismiss(animated: true)
        } catch {
            showMessage(
                error.localizedDescription, title: localized("Could not save changes"), from: self)
        }
    }
}
