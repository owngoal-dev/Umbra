import UIKit

final class SettingsViewController: UITableViewController {
    private let check: EnvironmentCheck
    private var services: [ManagedService] = []
    private var showsURLSchemeReplacements = false
    private var servicesSection: Int {
        0
    }

    private var rulesSection: Int {
        services.isEmpty ? 0 : 1
    }

    private var appsSection: Int? {
        #if os(iOS)
            rulesSection + 1
        #else
            nil
        #endif
    }

    init(check: EnvironmentCheck) {
        self.check = check
        super.init(style: AppPlatform.tableStyle)
        title = localized("Settings")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        refreshServices()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        services = ManagedService.installed
        showsURLSchemeReplacements = URLSchemeRules.isSupported
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.tableHeaderView = brandHeader()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshServices),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    @objc private func refreshServices() {
        services = ManagedService.installed
        showsURLSchemeReplacements = URLSchemeRules.isSupported
        tableView.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        let width = tableView.bounds.width
        let height = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        if header.frame.width != width || abs(header.frame.height - height) > 0.5 {
            header.frame.size = CGSize(width: width, height: height)
            tableView.tableHeaderView = header
        }
    }

    override func numberOfSections(in _: UITableView) -> Int {
        #if os(iOS)
            rulesSection + 2
        #else
            rulesSection + 1
        #endif
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == appsSection {
            return OwnGoalApps.all.count
        }
        return section == rulesSection ? (showsURLSchemeReplacements ? 2 : 1) : services.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        if section == appsSection {
            return localized("OwnGoal Picks")
        }
        return localized(section == rulesSection ? "Advanced" : "Services")
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if indexPath.section == appsSection {
            return appCell(in: tableView, app: OwnGoalApps.all[indexPath.row])
        }
        let isRule = indexPath.section == rulesSection
        let isReplacement = isRule && showsURLSchemeReplacements && indexPath.row == 0
        let cell = detailCell(in: tableView, reuseIdentifier: isRule ? "Rules" : "Service")
        var content = cell.defaultContentConfiguration()
        content.text =
            isRule
                ? localized(isReplacement ? "URL Scheme Replacements" : "Custom Cleanup Rules")
                : services[indexPath.row].title
        content.secondaryText =
            isRule
                ? (isReplacement ? nil : localized("Edit cleanup rules in a file manager."))
                : services[indexPath.row].portSummary
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = .secondaryLabel
        content.textToSecondaryTextVerticalPadding = 6
        content.image = UIImage(
            systemName: isRule
                ? (isReplacement ? "arrow.triangle.branch" : "doc.text")
                : services[indexPath.row].symbol
        )
        content.imageProperties.tintColor = AppTheme.tint
        content.imageProperties.maximumSize = CGSize(
            width: AppPlatform.listSymbolPointSize, height: AppPlatform.listSymbolPointSize
        )
        content.imageProperties.reservedLayoutSize = AppPlatform.listSymbolReservedSize
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: AppPlatform.listSymbolPointSize
        )
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 16, leading: 20, bottom: 16, trailing: 20
        )
        cell.contentConfiguration = content
        cell.accessoryType = isRule ? .disclosureIndicator : AppPlatform.detailAccessory
        #if os(iOS)
            cell.selectionStyle = isRule ? .default : .none
        #else
            cell.selectionStyle = .default
        #endif
        return cell
    }

    private func appCell(in tableView: UITableView, app: OwnGoalApp) -> UITableViewCell {
        let cell = detailCell(in: tableView, reuseIdentifier: "OwnGoalApp")
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(named: app.iconName)
        content.imageProperties.maximumSize = AppPlatform.applicationIconSize
        content.imageProperties.reservedLayoutSize = AppPlatform.applicationIconSize
        content.imageProperties.cornerRadius = AppPlatform.applicationIconCornerRadius
        content.imageToTextPadding = 16
        content.text = app.name
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.textProperties.adjustsFontForContentSizeCategory = true
        content.secondaryText = localized(app.taglineKey)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.textToSecondaryTextVerticalPadding = 2
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12, leading: 20, bottom: 12, trailing: 20
        )
        cell.contentConfiguration = content

        let arrow = UIImageView(image: UIImage(systemName: "arrow.up.right"))
        arrow.tintColor = .tertiaryLabel
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13, weight: .semibold
        )
        cell.accessoryView = arrow
        cell.selectionStyle = .default
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = "\(app.name), \(localized(app.taglineKey))"
        cell.accessibilityTraits = .button
        return cell
    }

    private func brandHeader() -> UIView {
        let header = UIView()
        header.backgroundColor = AppTheme.background

        let icon = EclipseView()
        icon.layer.cornerRadius = 17
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        let name = UILabel()
        name.text = "Umbra"
        name.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .semibold)
        )
        let version = UILabel()
        version.text = String(
            format: localized("Version %@"),
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "—"
        )
        version.font = .preferredFont(forTextStyle: .subheadline)
        version.textColor = .secondaryLabel
        for label in [name, version] {
            label.numberOfLines = 0
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
        }
        let stack = UIStackView(arrangedSubviews: [icon, name, version])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 76),
            icon.heightAnchor.constraint(equalToConstant: 76),
            name.widthAnchor.constraint(equalTo: stack.widthAnchor),
            version.widthAnchor.constraint(equalTo: stack.widthAnchor),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 44),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(
                equalTo: header.trailingAnchor, constant: -24
            ),
        ])
        header.isAccessibilityElement = true
        header.accessibilityLabel = name.text
        header.accessibilityValue = version.text
        header.accessibilityTraits = .staticText
        return header
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        #if os(iOS)
            if indexPath.section == appsSection {
                open(OwnGoalApps.all[indexPath.row])
                return
            }
        #endif
        #if os(tvOS)
            if indexPath.section == servicesSection, !services.isEmpty {
                self.tableView(tableView, accessoryButtonTappedForRowWith: indexPath)
                return
            }
        #endif
        if indexPath.section == rulesSection {
            if showsURLSchemeReplacements, indexPath.row == 0 {
                navigationController?.pushViewController(
                    URLSchemeRulesViewController(), animated: true
                )
            } else {
                openInFileManager(path: UMBBackend.customRulesPath(), from: self)
            }
        }
    }

    #if os(iOS)
        private func open(_ app: OwnGoalApp) {
            open([app.irisinURL, app.sileoURL, app.repositoryURL], at: 0)
        }

        private func open(_ urls: [URL], at index: Int) {
            guard index < urls.count else { return }
            let url = urls[index]
            guard UIApplication.shared.canOpenURL(url) else {
                open(urls, at: index + 1)
                return
            }
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                guard !opened else { return }
                self?.open(urls, at: index + 1)
            }
        }
    #endif

    override func tableView(
        _: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath
    ) {
        guard indexPath.section == servicesSection, !services.isEmpty else { return }
        presentServicePorts(services[indexPath.row], from: self) { [weak self] in
            self?.check.refresh()
            self?.refreshServices()
        }
    }
}
