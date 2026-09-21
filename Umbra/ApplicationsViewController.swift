import UIKit

final class ApplicationsViewController: UITableViewController, UISearchResultsUpdating,
    UISearchControllerDelegate
{
    private let check: EnvironmentCheck
    private let search = UISearchController(searchResultsController: nil)
    private let workQueue = DispatchQueue(
        label: "wiki.qaq.umbra.applications", qos: .userInitiated)
    private var apps: [AppInfo] = []
    private var filtered: [AppInfo] = []
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
    private var applicationsSection: Int { showsDeviceStatus ? 1 : 0 }

    init(check: EnvironmentCheck) {
        self.check = check
        super.init(style: .insetGrouped)
        title = localized("Blacklist")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        search.searchResultsUpdater = self
        search.delegate = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = localized("name or identifier")
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(manualRefresh), for: .valueChanged)
        NotificationCenter.default.addObserver(
            self, selector: #selector(environmentChanged), name: EnvironmentCheck.didChange,
            object: check)
        NotificationCenter.default.addObserver(
            self, selector: #selector(foregroundRefresh),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
        refresh(resort: true, synchronously: true)
    }

    @objc private func environmentChanged() {
        guard showsDeviceStatus,
            let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
        else { return }
        UIView.performWithoutAnimation {
            check.configure(cell)
            tableView.performBatchUpdates(nil)
        }
    }

    @objc private func manualRefresh() { refresh(resort: true) }
    @objc private func foregroundRefresh() { refresh(resort: false) }

    private func refresh(resort: Bool, synchronously: Bool = false) {
        guard !isLoading, !isWorking, pendingChanges.isEmpty else {
            pendingResort = (pendingResort ?? false) || resort
            refreshControl?.endRefreshing()
            return
        }
        isLoading = true
        for cell in tableView.visibleCells {
            (cell.accessoryView as? UISwitch)?.isEnabled = false
        }
        let load = {
            let apps = RHBackend.installedApps()
            let configuration =
                RHBackend.configuration(forKey: "appconfig") as? [String: Bool] ?? [:]
            let reason = RHBackend.blacklistUnavailableReason()
            let update = {
                self.configuration = configuration
                self.unavailableReason = reason
                if resort {
                    self.apps = apps.sorted {
                        let left = configuration[$0.bundleIdentifier ?? ""] ?? false
                        let right = configuration[$1.bundleIdentifier ?? ""] ?? false
                        if left != right { return left }
                        return ($0.name ?? "").localizedStandardCompare($1.name ?? "")
                            == .orderedAscending
                    }
                } else {
                    let positions = Dictionary(
                        self.apps.enumerated().map {
                            ($0.element.bundleIdentifier ?? "", $0.offset)
                        },
                        uniquingKeysWith: { first, _ in first })
                    self.apps = apps.sorted {
                        let left = positions[$0.bundleIdentifier ?? ""] ?? Int.max
                        let right = positions[$1.bundleIdentifier ?? ""] ?? Int.max
                        if left != right { return left < right }
                        return ($0.name ?? "").localizedStandardCompare($1.name ?? "")
                            == .orderedAscending
                    }
                }
                self.isLoading = false
                self.refreshControl?.endRefreshing()
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
        showsDeviceStatus = !searchController.isActive && text.isEmpty
        filtered =
            text.isEmpty
            ? apps
            : apps.filter {
                ($0.name ?? "").localizedStandardContains(text)
                    || ($0.bundleIdentifier ?? "").localizedStandardContains(text)
            }
        tableView.reloadData()
    }

    func willPresentSearchController(_ searchController: UISearchController) {
        showsDeviceStatus = false
        tableView.reloadData()
    }

    func didDismissSearchController(_ searchController: UISearchController) {
        searchController.searchBar.text = nil
        updateSearchResults(for: searchController)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { applicationsSection + 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == applicationsSection ? max(1, filtered.count) : (operationStatus == nil ? 1 : 2)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        section == applicationsSection ? localized("Applications") : localized("Status")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int)
        -> String?
    {
        section == applicationsSection ? unavailableReason : nil
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = detailCell(
            in: tableView,
            reuseIdentifier: indexPath.section == applicationsSection ? "App" : "Status")
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.accessibilityValue = nil
        cell.selectionStyle = .none
        if indexPath.section != applicationsSection {
            if indexPath.row == 0 {
                check.configure(cell)
                cell.selectionStyle = .default
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
            top: 14, leading: 16, bottom: 14, trailing: 16)
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
            content.secondaryText =
                apps.isEmpty && !isLoading ? localized("Pull to refresh") : nil
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
            content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
            content.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
            content.imageProperties.cornerRadius = 10
            let toggle = UISwitch()
            toggle.isOn =
                unavailableReason == nil && (configuration[identifier] ?? false)
            toggle.isEnabled = !isWorking && !isLoading && !pendingChanges.contains(identifier)
            toggle.accessibilityLabel = app.name ?? app.bundleIdentifier
            toggle.addAction(
                UIAction { [weak self, weak toggle] _ in
                    guard let self, let toggle else { return }
                    self.toggle(app, enabled: toggle.isOn)
                }, for: .valueChanged)
            cell.accessoryView = toggle
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if showsDeviceStatus && indexPath.section == 0 && indexPath.row == 0 {
            navigationController?.pushViewController(
                EnvironmentViewController(check: check), animated: true)
        }
    }

    private func toggle(_ app: AppInfo, enabled: Bool) {
        let identifier = app.bundleIdentifier ?? ""
        guard !isLoading, !isWorking, !pendingChanges.contains(identifier) else {
            updateApp(identifier)
            return
        }
        if let reason = unavailableReason ?? RHBackend.blacklistRejection(for: app) {
            updateApp(identifier)
            showMessage(reason, title: localized("Blacklist is unavailable"), from: self)
            return
        }
        if enabled && !didShowCompatibilityWarning && RHBackend.requiresCompatibilityWarning() {
            updateApp(identifier)
            let alert = UIAlertController(
                title: localized("Warning"),
                message: localized(
                    "\nFor iOS15 A12+ devices:\n\nthe blacklisted app will have its app extension disabled, and may cause a spinlock panic when the app is running in the foreground/background.\n\nYou can first try disabling tweak injection for this app in Choicy, and only blacklist the app if it doesn't work."
                ),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel))
            alert.addAction(
                UIAlertAction(title: localized("Continue"), style: .default) { _ in
                    self.didShowCompatibilityWarning = true
                    self.save(app, enabled: enabled)
                })
            present(alert, animated: true)
        } else {
            save(app, enabled: enabled)
        }
    }

    private func save(_ app: AppInfo, enabled: Bool) {
        let identifier = app.bundleIdentifier ?? ""
        guard !isLoading, !isWorking, pendingChanges.insert(identifier).inserted else { return }
        let previous = configuration[identifier]
        configuration[identifier] = enabled
        saveErrors[identifier] = nil
        updateApp(identifier)
        workQueue.async {
            do {
                try RHBackend.setBlacklisted(enabled, for: app)
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
                        notification: .announcement, argument: self.saveErrors[identifier])
                    self.refreshIfNeeded()
                }
            }
        }
    }

    private func updateApp(_ identifier: String) {
        guard let row = filtered.firstIndex(where: { $0.bundleIdentifier == identifier }),
            let cell = tableView.cellForRow(at: IndexPath(row: row, section: applicationsSection)),
            let toggle = cell.accessoryView as? UISwitch
        else { return }
        toggle.setOn(
            unavailableReason == nil && (configuration[identifier] ?? false),
            animated: !UIAccessibility.isReduceMotionEnabled)
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

    override func tableView(
        _ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == applicationsSection, !filtered.isEmpty, !isWorking, !isLoading,
            pendingChanges.isEmpty
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
                    }
                ])
        }
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == applicationsSection, !filtered.isEmpty, !isWorking, !isLoading,
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

    private func confirmClear(_ app: AppInfo) {
        guard !isWorking, !isLoading, pendingChanges.isEmpty else { return }
        let name = app.name ?? app.bundleIdentifier ?? ""
        let alert = UIAlertController(
            title: String(format: localized("Clear data for %@?"), name),
            message: localized("This permanently removes this app’s data. This cannot be undone."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel))
        alert.addAction(
            UIAlertAction(title: localized("Clear Data"), style: .destructive) { _ in
                self.isWorking = true
                let work = DispatchWorkItem {
                    let error = RHBackend.clearData(for: app)
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
                                at: IndexPath(row: 1, section: 0), at: .top, animated: true)
                        }
                        UIAccessibility.post(
                            notification: .announcement, argument: self.operationStatus)
                        self.refreshIfNeeded()
                    }
                }
                self.workQueue.async(execute: work)
                if work.wait(timeout: .now() + .milliseconds(500)) == .timedOut {
                    self.operationStatus = String(format: localized("Clearing data for %@…"), name)
                    self.tableView.reloadData()
                    if self.showsDeviceStatus {
                        self.tableView.scrollToRow(
                            at: IndexPath(row: 1, section: 0), at: .top, animated: true)
                    }
                }
            })
        present(alert, animated: true)
    }
}
