import UIKit

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum AppTheme {
    static let tint = UIColor.systemIndigo
}

func showMessage(_ message: String, title: String, from controller: UIViewController) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: localized("Done"), style: .default))
    controller.present(alert, animated: true)
}

func openInFileManager(path: String, from controller: UIViewController) {
    UIPasteboard.general.string = path
    var components = URLComponents()
    components.scheme = "fila"
    components.host = "view"
    components.path = path
    guard let fila = components.url else { return }
    components.scheme = "filza"
    guard let filza = components.url else { return }
    UIApplication.shared.open(fila) { opened in
        guard !opened else { return }
        UIApplication.shared.open(filza) { opened in
            guard !opened else { return }
            showMessage(
                localized("Neither Fila nor Filza could be opened. The path has been copied."),
                title: localized("Open in File Manager"), from: controller)
        }
    }
}

func detailCell(in table: UITableView, reuseIdentifier: String = "Detail") -> UITableViewCell {
    table.dequeueReusableCell(withIdentifier: reuseIdentifier)
        ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
}

final class EnvironmentCheck {
    static let didChange = Notification.Name("EnvironmentCheckDidChange")
    private(set) var isChecking = false
    private(set) var findings: [[String: String]] = []

    init() { findings = RHBackend.startupWarnings() }

    var summary: String {
        let titles = findings.compactMap { $0["title"] }
        guard !titles.isEmpty else {
            return isChecking ? localized("Checking environment…") : localized("No issues found")
        }
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let separator = language.hasPrefix("zh") ? "；" : language.hasPrefix("ar") ? "؛ " : "; "
        let serviceNames = [
            localized("SSH Server"): "SSH",
            localized("Dropbear"): "Dropbear",
            localized("Frida Server"): "Frida",
        ]
        let services = titles.compactMap { serviceNames[$0] }
        guard services.count > 1 else { return titles.joined(separator: separator) }
        let abbreviated = titles.count > 3 && services.count == 3
        let names = abbreviated ? ["SSH", "Frida"] : services
        let joined: String
        if language.hasPrefix("zh") {
            joined = names.dropLast().joined(separator: "、") + " 和 " + names[names.count - 1]
        } else {
            let formatter = ListFormatter()
            formatter.locale = Locale(identifier: language)
            joined = formatter.string(from: names) ?? names.joined(separator: ", ")
        }
        let template = abbreviated ? localized("%@ and other services") : localized("%@ services")
        let serviceSummary = String(format: template, joined)
        var components: [String] = []
        var addedServices = false
        for title in titles {
            if serviceNames[title] == nil {
                components.append(title)
            } else if !addedServices {
                components.append(serviceSummary)
                addedServices = true
            }
        }
        return components.joined(separator: separator)
    }

    func refresh() {
        guard !isChecking else { return }
        isChecking = true
        NotificationCenter.default.post(name: Self.didChange, object: self)
        DispatchQueue.global(qos: .utility).async {
            let findings = RHBackend.startupWarnings()
            DispatchQueue.main.async {
                self.findings = findings
                self.isChecking = false
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }

    func configure(_ cell: UITableViewCell) {
        var content = cell.defaultContentConfiguration()
        content.text = localized("Environment Check")
        content.textProperties.numberOfLines = 0
        content.secondaryText = summary
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = .secondaryLabel
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 16, leading: 20, bottom: 16, trailing: 20)
        content.textToSecondaryTextVerticalPadding = 6
        content.image = UIImage(
            systemName: isChecking && findings.isEmpty
                ? "clock"
                : findings.isEmpty
                    ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
        content.imageProperties.maximumSize = CGSize(width: 26, height: 26)
        content.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 26)
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 26)
        content.imageProperties.tintColor =
            isChecking && findings.isEmpty
            ? .secondaryLabel : findings.isEmpty ? AppTheme.tint : .systemOrange
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessoryView = nil
        cell.accessibilityValue = nil
        if !findings.isEmpty {
            let badge = UILabel()
            badge.text = findings.count.formatted()
            badge.font = .preferredFont(forTextStyle: .subheadline)
            badge.adjustsFontForContentSizeCategory = true
            badge.textAlignment = .center
            badge.textColor = .white
            badge.backgroundColor = .systemRed
            badge.isAccessibilityElement = false
            let height = max(24, ceil(badge.font.lineHeight) + 6)
            badge.layer.cornerRadius = height / 2
            badge.clipsToBounds = true
            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(
                    equalToConstant: max(height, ceil(badge.intrinsicContentSize.width) + 12)),
                badge.heightAnchor.constraint(equalToConstant: height),
            ])
            let indicator = UIImageView(
                image: UIImage(
                    systemName: "chevron.forward",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                ))
            indicator.tintColor = .tertiaryLabel
            let accessory = UIStackView(arrangedSubviews: [badge, indicator])
            accessory.alignment = .center
            accessory.spacing = 8
            accessory.isUserInteractionEnabled = false
            accessory.frame.size = accessory.systemLayoutSizeFitting(
                UIView.layoutFittingCompressedSize)
            cell.accessoryView = accessory
            cell.accessibilityValue = badge.text
        }
        cell.accessibilityHint = localized("Show Details")
    }
}

final class EnvironmentViewController: UITableViewController {
    private let check: EnvironmentCheck

    init(check: EnvironmentCheck) {
        self.check = check
        super.init(style: .insetGrouped)
        title = localized("Environment Check")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.allowsSelection = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshCheck), for: .valueChanged)
        NotificationCenter.default.addObserver(
            self, selector: #selector(update), name: EnvironmentCheck.didChange, object: check)
        update()
    }

    @objc private func refreshCheck() { check.refresh() }

    @objc private func update() {
        if check.isChecking && !check.findings.isEmpty { return }
        if !check.isChecking { refreshControl?.endRefreshing() }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, check.findings.count)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        localized("Check Results")
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = detailCell(in: tableView)
        cell.accessoryType = .none
        var content = cell.defaultContentConfiguration()
        if check.findings.isEmpty {
            content.text = check.summary
            content.image = UIImage(systemName: check.isChecking ? "clock" : "checkmark.shield")
            content.imageProperties.tintColor = AppTheme.tint
        } else {
            let finding = check.findings[indexPath.row]
            let symbols = [
                localized("Legacy rootless jailbreak(s)"): "archivebox.fill",
                localized("Unknown preboot system"): "externaldrive.fill",
                localized("Unknown Bindfs Mount(s)"): "externaldrive.connected.to.line.below",
                localized("SSH Server"): "terminal.fill",
                localized("Dropbear"): "key.fill",
                localized("Frida Server"): "ladybug.fill",
                localized("VPN or Proxy"): "network",
            ]
            if let identifier = finding["service"], ManagedService(rawValue: identifier) != nil {
                cell.accessoryType = .detailButton
            }
            content.text = finding["title"]
            content.secondaryText = finding["message"]
            content.image = UIImage(
                systemName: symbols[finding["title"] ?? ""] ?? "exclamationmark.triangle.fill")
            content.imageProperties.tintColor = .systemOrange
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel
        }
        content.imageProperties.maximumSize = CGSize(width: 26, height: 26)
        content.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 26)
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 26)
        content.textProperties.numberOfLines = 0
        content.textToSecondaryTextVerticalPadding = 8
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 20, leading: 20, bottom: 20, trailing: 20)
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(
        _ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath
    ) {
        guard indexPath.row < check.findings.count,
            let identifier = check.findings[indexPath.row]["service"],
            let service = ManagedService(rawValue: identifier)
        else { return }
        presentServicePorts(service, from: self) { [weak self] in self?.check.refresh() }
    }

}
