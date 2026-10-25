import UIKit

#if os(tvOS)
    private final class ApplicationSearchResultsViewController: UITableViewController {
        var onSelect: ((UMBInstalledAppInfo) -> Void)?
        private var apps: [UMBInstalledAppInfo] = []
        private var configuration: [String: Bool] = [:]
        private var isLoading = false

        init() {
            super.init(style: AppPlatform.tableStyle)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 76
        }

        func update(apps: [UMBInstalledAppInfo], configuration: [String: Bool], isLoading: Bool) {
            self.apps = apps
            self.configuration = configuration
            self.isLoading = isLoading
            if isViewLoaded {
                tableView.reloadData()
            }
        }

        override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
            max(1, apps.count)
        }

        override func tableView(
            _ tableView: UITableView, cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell {
            let cell = detailCell(in: tableView, reuseIdentifier: "SearchResult")
            cell.accessoryView = nil
            cell.accessoryType = .none
            var content = cell.defaultContentConfiguration()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: 14, leading: 16, bottom: 14, trailing: 16
            )
            content.imageToTextPadding = 14
            content.textProperties.numberOfLines = 0
            content.secondaryTextProperties.numberOfLines = 0
            content.secondaryTextProperties.color = .secondaryLabel
            if apps.isEmpty {
                content.text = localized(isLoading ? "Loading…" : "No search results")
                content.image = UIImage(systemName: "magnifyingglass")
                content.imageProperties.tintColor = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                let app = apps[indexPath.row]
                content.text = app.name ?? app.bundleIdentifier
                content.secondaryText = app.bundleIdentifier
                content.image = app.icon ?? UIImage(systemName: "app")
                content.imageProperties.maximumSize = AppPlatform.applicationIconSize
                content.imageProperties.reservedLayoutSize = AppPlatform.applicationIconSize
                content.imageProperties.cornerRadius = AppPlatform.applicationIconCornerRadius
                let state = AppSwitch()
                state.isOn = configuration[app.bundleIdentifier ?? ""] ?? false
                cell.accessoryView = state
                cell.selectionStyle = .default
            }
            cell.contentConfiguration = content
            return cell
        }

        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            guard !apps.isEmpty else { return }
            onSelect?(apps[indexPath.row])
        }
    }
#endif

final class ApplicationsViewController: UITableViewController, UISearchResultsUpdating,
    UISearchControllerDelegate
{
    private let check: EnvironmentCheck
    private let search: UISearchController
    #if os(tvOS)
        private let searchResults: ApplicationSearchResultsViewController
        private lazy var searchContainer = UISearchContainerViewController(
            searchController: search
        )
    #endif
    private let workQueue = DispatchQueue(
        label: "wiki.qaq.umbra.applications", qos: .userInitiated
    )
    private var apps: [UMBInstalledAppInfo] = []
    private var filtered: [UMBInstalledAppInfo] = []
    private var configuration: [String: Bool] = [:]
    private var unavailableReason: String?
    private var isLoading = false
    private var isWorking = false
    private var pendingChanges: Set<String> = []
    private var saveErrors: [String: String] = [:]
    private var pendingResort: Bool?
    private var didShowCompatibilityWarning = false
    private var operationStatus: String?
    private var showsDeviceStatus = true
    private var applicationsSection: Int {
        #if os(iOS)
            showsDeviceStatus ? 1 : 0
        #else
            2
        #endif
    }

    init(check: EnvironmentCheck) {
        self.check = check
        #if os(iOS)
            search = UISearchController(searchResultsController: nil)
        #else
            let searchResults = ApplicationSearchResultsViewController()
            self.searchResults = searchResults
            search = UISearchController(searchResultsController: searchResults)
        #endif
        super.init(style: AppPlatform.tableStyle)
        #if os(iOS)
            title = localized("Blacklist")
        #else
            searchResults.onSelect = { [weak self] app in
                self?.finishSearch(selecting: app)
            }
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        search.searchResultsUpdater = self
        search.delegate = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = localized("name or identifier")
        #if os(iOS)
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = false
        #endif
        definesPresentationContext = true
        configureRefresh(action: #selector(manualRefresh))
        NotificationCenter.default.addObserver(
            self, selector: #selector(environmentChanged), name: EnvironmentCheck.didChange,
            object: check
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(foregroundRefresh),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        refresh(resort: true, synchronously: true)
    }

    #if os(tvOS)
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    #endif

    @objc private func environmentChanged() {
        guard showsDeviceStatus,
              let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
        else { return }
        UIView.performWithoutAnimation {
            check.configure(cell)
            tableView.performBatchUpdates(nil)
        }
    }

    @objc private func manualRefresh() {
        refresh(resort: true)
    }

    @objc private func foregroundRefresh() {
        refresh(resort: false)
    }

    private func refresh(resort: Bool, synchronously: Bool = false) {
        guard !isLoading, !isWorking, pendingChanges.isEmpty else {
            pendingResort = (pendingResort ?? false) || resort
            endRefreshing()
            return
        }
        isLoading = true
        for cell in tableView.visibleCells {
            (cell.accessoryView as? AppSwitch)?.isEnabled = false
        }
        let load = {
            let apps = UMBBackend.installedApps()
            let configuration =
                UMBBackend.configuration(forKey: "appconfig") as? [String: Bool] ?? [:]
            let reason = UMBBackend.blacklistUnavailableReason()
            let update = {
                self.configuration = configuration
                self.unavailableReason = reason
                if resort {
                    self.apps = apps.sorted {
                        let left = configuration[$0.bundleIdentifier ?? ""] ?? false
                        let right = configuration[$1.bundleIdentifier ?? ""] ?? false
                        if left != right {
                            return left
                        }
                        return ($0.name ?? "").localizedStandardCompare($1.name ?? "")
                            == .orderedAscending
                    }
                } else {
                    let positions = Dictionary(
                        self.apps.enumerated().map {
                            ($0.element.bundleIdentifier ?? "", $0.offset)
                        },
                        uniquingKeysWith: { first, _ in first }
                    )
                    self.apps = apps.sorted {
                        let left = positions[$0.bundleIdentifier ?? ""] ?? Int.max
                        let right = positions[$1.bundleIdentifier ?? ""] ?? Int.max
                        if left != right {
                            return left < right
                        }
                        return ($0.name ?? "").localizedStandardCompare($1.name ?? "")
                            == .orderedAscending
                    }
                }
                self.isLoading = false
                self.endRefreshing()
                self.updateSearchResults(for: self.search)
                self.refreshIfNeeded()
            }
            if synchronously {
                update()
            } else {
                DispatchQueue.main.async(execute: update)
            }
        }
        if synchronously {
            load()
        } else {
            workQueue.async(execute: load)
        }
    }

    private func refreshIfNeeded() {
        guard !isLoading, !isWorking, pendingChanges.isEmpty, let resort = pendingResort else {
            return
        }
        pendingResort = nil
        refresh(resort: resort)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text =
            searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #if os(iOS)
            showsDeviceStatus = !searchController.isActive && text.isEmpty
        #endif
        filtered =
            text.isEmpty
                ? apps
                : apps.filter {
                    ($0.name ?? "").localizedStandardContains(text)
                        || ($0.bundleIdentifier ?? "").localizedStandardContains(text)
                }
        #if os(iOS)
            tableView.reloadData()
        #else
            searchResults.update(
                apps: filtered, configuration: configuration, isLoading: isLoading
            )
            if !searchController.isActive {
                tableView.reloadData()
            }
        #endif
    }

    func willPresentSearchController(_: UISearchController) {
        #if os(iOS)
            showsDeviceStatus = false
            tableView.reloadData()
        #endif
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        searchController.searchBar.text = nil
        updateSearchResults(for: searchController)
    }

    override func numberOfSections(in _: UITableView) -> Int {
        applicationsSection + 1
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == applicationsSection {
            return max(1, filtered.count)
        }
        #if os(tvOS)
            if section == 1 {
                return 1
            }
        #endif
        return operationStatus == nil ? 1 : 2
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        if section == applicationsSection {
            return localized("Applications")
        }
        #if os(tvOS)
            if section == 1 {
                return nil
            }
        #endif
        return localized("Status")
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int)
        -> String?
    {
        section == applicationsSection ? unavailableReason : nil
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = detailCell(
            in: tableView,
            reuseIdentifier: indexPath.section == applicationsSection ? "App" : "Status"
        )
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.accessibilityValue = nil
        #if os(tvOS)
            cell.accessibilityHint = nil
            cell.accessibilityTraits = .button
            cell.isUserInteractionEnabled = true
        #endif
        cell.selectionStyle = .none
        #if os(tvOS)
            if indexPath.section == 1 {
                var content = cell.defaultContentConfiguration()
                content.text = localized("name or identifier")
                content.image = UIImage(systemName: "magnifyingglass")
                content.imageProperties.tintColor = AppTheme.tint
                content.imageProperties.maximumSize = CGSize(
                    width: AppPlatform.listSymbolPointSize,
                    height: AppPlatform.listSymbolPointSize
                )
                content.imageProperties.reservedLayoutSize = AppPlatform.listSymbolReservedSize
                content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                    pointSize: AppPlatform.listSymbolPointSize
                )
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
                cell.accessibilityHint = localized("Show Details")
                return cell
            }
        #endif
        if indexPath.section != applicationsSection {
            if indexPath.row == 0 {
                check.configure(cell)
            } else {
                var content = cell.defaultContentConfiguration()
                content.text = operationStatus
                content.textProperties.numberOfLines = 0
                content.image = UIImage(systemName: isWorking ? "hourglass" : "info.circle")
                content.imageProperties.tintColor = AppTheme.tint
                cell.contentConfiguration = content
                cell.accessibilityHint = nil
            }
            return cell
        }
        var content = cell.defaultContentConfiguration()
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 14, leading: 16, bottom: 14, trailing: 16
        )
        content.imageToTextPadding = 14
        content.textToSecondaryTextVerticalPadding = 4
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = .secondaryLabel
        if filtered.isEmpty {
            content.text =
                isLoading
                    ? localized("Loading…")
                    : apps.isEmpty ? localized("No apps found") : localized("No search results")
            #if os(iOS)
                content.secondaryText =
                    apps.isEmpty && !isLoading ? localized("Pull to refresh") : nil
            #endif
            content.image = UIImage(systemName: "magnifyingglass")
            content.imageProperties.tintColor = .secondaryLabel
        } else {
            let app = filtered[indexPath.row]
            let identifier = app.bundleIdentifier ?? ""
            content.text = app.name ?? app.bundleIdentifier
            content.secondaryText = saveErrors[identifier] ?? app.bundleIdentifier
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            content.secondaryTextProperties.color =
                saveErrors[identifier] == nil ? .secondaryLabel : .systemRed
            content.image = app.icon ?? UIImage(systemName: "app")
            content.imageProperties.maximumSize = AppPlatform.applicationIconSize
            content.imageProperties.reservedLayoutSize = AppPlatform.applicationIconSize
            content.imageProperties.cornerRadius = AppPlatform.applicationIconCornerRadius
            let toggle = AppSwitch()
            toggle.isOn =
                unavailableReason == nil && (configuration[identifier] ?? false)
            toggle.isEnabled = !isWorking && !isLoading && !pendingChanges.contains(identifier)
            toggle.accessibilityLabel = app.name ?? app.bundleIdentifier
            toggle.addAction(
                UIAction { [weak self, weak toggle] _ in
                    guard let self, let toggle else { return }
                    self.toggle(app, enabled: toggle.isOn)
                }, for: .valueChanged
            )
            #if os(tvOS)
                cell.selectionStyle = .default
            #endif
            cell.accessoryView = toggle
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if showsDeviceStatus, indexPath.section == 0, indexPath.row == 0 {
            guard !check.findings.isEmpty else { return }
            navigationController?.pushViewController(
                EnvironmentViewController(check: check), animated: true
            )
            return
        }
        #if os(tvOS)
            if indexPath.section == 1 {
                presentSearch()
                return
            }
            guard indexPath.section == applicationsSection, !filtered.isEmpty,
                  !isLoading, !isWorking, pendingChanges.isEmpty
            else { return }
            let app = filtered[indexPath.row]
            if #unavailable(tvOS 17.0) {
                presentActions(for: app)
                return
            }
            let enabled = configuration[app.bundleIdentifier ?? ""] ?? false
            toggle(app, enabled: !enabled)
        #endif
    }

    #if os(tvOS)
        private func presentActions(for app: UMBInstalledAppInfo) {
            let enabled = configuration[app.bundleIdentifier ?? ""] ?? false
            let alert = UIAlertController(
                title: app.name, message: app.bundleIdentifier, preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: localized(enabled ? "Disable" : "Enable"), style: .default) {
                    [weak self] _ in
                    self?.toggle(app, enabled: !enabled)
                }
            )
            alert.addAction(
                UIAlertAction(title: localized("Clear App Data"), style: .destructive) {
                    [weak self] _ in
                    self?.confirmClear(app)
                }
            )
            alert.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel))
            present(alert, animated: true)
        }

        private func presentSearch() {
            search.searchBar.text = nil
            filtered = apps
            searchResults.update(
                apps: filtered, configuration: configuration, isLoading: isLoading
            )
            searchContainer.modalPresentationStyle = .fullScreen
            present(searchContainer, animated: true) { [weak self] in
                self?.search.isActive = true
            }
        }

        private func finishSearch(selecting app: UMBInstalledAppInfo) {
            search.isActive = false
            search.searchBar.text = nil
            filtered = apps
            tableView.reloadData()
            dismiss(animated: true) { [weak self] in
                guard let self else { return }
                if #available(tvOS 17.0, *) {
                    let enabled = configuration[app.bundleIdentifier ?? ""] ?? false
                    toggle(app, enabled: !enabled)
                } else {
                    presentActions(for: app)
                }
            }
        }
    #endif

    private func toggle(_ app: UMBInstalledAppInfo, enabled: Bool) {
        let identifier = app.bundleIdentifier ?? ""
        guard !isLoading, !isWorking, !pendingChanges.contains(identifier) else {
            updateApp(identifier)
            return
        }
        if let reason = unavailableReason ?? UMBBackend.blacklistRejection(for: app) {
            updateApp(identifier)
            showMessage(reason, title: localized("Blacklist is unavailable"), from: self)
            return
        }
        if enabled, !didShowCompatibilityWarning, UMBBackend.requiresCompatibilityWarning() {
            updateApp(identifier)
            let alert = UIAlertController(
                title: localized("Warning"),
                message: localized(
                    "\nFor iOS15 A12+ devices:\n\nthe blacklisted app will have its app extension disabled, and may cause a spinlock panic when the app is running in the foreground/background.\n\nYou can first try disabling tweak injection for this app in Choicy, and only blacklist the app if it doesn't work."
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel))
            alert.addAction(
                UIAlertAction(title: localized("Continue"), style: .default) { _ in
                    self.didShowCompatibilityWarning = true
                    self.save(app, enabled: enabled)
                }
            )
            present(alert, animated: true)
        } else {
            save(app, enabled: enabled)
        }
    }

    private func save(_ app: UMBInstalledAppInfo, enabled: Bool) {
        let identifier = app.bundleIdentifier ?? ""
        guard !isLoading, !isWorking, pendingChanges.insert(identifier).inserted else { return }
        let previous = configuration[identifier]
        configuration[identifier] = enabled
        saveErrors[identifier] = nil
        updateApp(identifier)
        workQueue.async {
            do {
                try UMBBackend.setBlacklisted(enabled, for: app)
                DispatchQueue.main.async {
                    self.pendingChanges.remove(identifier)
                    self.updateApp(identifier)
                    self.refreshIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    self.pendingChanges.remove(identifier)
                    self.configuration[identifier] = previous
                    self.saveErrors[identifier] =
                        localized("Could not save changes") + "\n" + error.localizedDescription
                    self.updateApp(identifier)
                    UIAccessibility.post(
                        notification: .announcement, argument: self.saveErrors[identifier]
                    )
                    self.refreshIfNeeded()
                }
            }
        }
    }

    private func updateApp(_ identifier: String) {
        guard let row = filtered.firstIndex(where: { $0.bundleIdentifier == identifier }),
              let cell = tableView.cellForRow(at: IndexPath(row: row, section: applicationsSection)),
              let toggle = cell.accessoryView as? AppSwitch
        else { return }
        toggle.setOn(
            unavailableReason == nil && (configuration[identifier] ?? false),
            animated: !UIAccessibility.isReduceMotionEnabled
        )
        toggle.isEnabled = !isLoading && !isWorking && !pendingChanges.contains(identifier)
        guard var content = cell.contentConfiguration as? UIListContentConfiguration else { return }
        let detail = saveErrors[identifier] ?? identifier
        guard content.secondaryText != detail else { return }
        content.secondaryText = detail
        content.secondaryTextProperties.color =
            saveErrors[identifier] == nil ? .secondaryLabel : .systemRed
        cell.contentConfiguration = content
        UIView.performWithoutAnimation { tableView.performBatchUpdates(nil) }
    }

    @available(tvOS 17.0, *)
    override func tableView(
        _: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == applicationsSection, !filtered.isEmpty, !isWorking,
              !isLoading, pendingChanges.isEmpty
        else { return nil }
        let app = filtered[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(
                children: [
                    UIAction(
                        title: localized("Clear App Data"), image: UIImage(systemName: "trash"),
                        attributes: .destructive
                    ) {
                        [weak self] _ in self?.confirmClear(app)
                    },
                ]
            )
        }
    }

    #if os(iOS)
        override func tableView(
            _: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard indexPath.section == applicationsSection, !filtered.isEmpty, !isWorking,
                  !isLoading,
                  pendingChanges.isEmpty
            else { return nil }
            let app = filtered[indexPath.row]
            let action = UIContextualAction(style: .destructive, title: localized("Clear App Data")) {
                [weak self] _, _, done in
                done(false)
                self?.confirmClear(app)
            }
            action.image = UIImage(systemName: "trash")
            let actions = UISwipeActionsConfiguration(actions: [action])
            actions.performsFirstActionWithFullSwipe = false
            return actions
        }

    #endif

    private func confirmClear(_ app: UMBInstalledAppInfo) {
        guard !isWorking, !isLoading, pendingChanges.isEmpty else { return }
        let name = app.name ?? app.bundleIdentifier ?? ""
        let alert = UIAlertController(
            title: String(format: localized("Clear data for %@?"), name),
            message: localized("This permanently removes this app’s data. This cannot be undone."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel))
        alert.addAction(
            UIAlertAction(title: localized("Clear Data"), style: .destructive) { _ in
                self.isWorking = true
                let work = DispatchWorkItem {
                    let error = UMBBackend.clearData(for: app)
                    DispatchQueue.main.async {
                        self.isWorking = false
                        self.operationStatus =
                            error.map {
                                String(format: localized("Could not clear data for %@"), name)
                                    + "\n" + $0
                            } ?? String(format: localized("Data cleared for %@"), name)
                        self.tableView.reloadData()
                        if self.showsDeviceStatus {
                            self.tableView.scrollToRow(
                                at: IndexPath(row: 1, section: 0), at: .top, animated: true
                            )
                        }
                        UIAccessibility.post(
                            notification: .announcement, argument: self.operationStatus
                        )
                        self.refreshIfNeeded()
                    }
                }
                self.workQueue.async(execute: work)
                if work.wait(timeout: .now() + .milliseconds(500)) == .timedOut {
                    self.operationStatus = String(format: localized("Clearing data for %@…"), name)
                    self.tableView.reloadData()
                    if self.showsDeviceStatus {
                        self.tableView.scrollToRow(
                            at: IndexPath(row: 1, section: 0), at: .top, animated: true
                        )
                    }
                }
            }
        )
        present(alert, animated: true)
    }
}
