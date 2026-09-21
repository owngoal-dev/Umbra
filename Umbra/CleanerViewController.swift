import UIKit

private struct CleanFileID: Hashable {
    let directory: String
    let name: String
}

private enum CleanerSection: Hashable {
    case information
    case directory(String)
}

private enum CleanerRow: Hashable {
    case information
    case state
    case file(CleanFileID)
}

private final class CleanerDataSource: UITableViewDiffableDataSource<CleanerSection, CleanerRow> {
    var errors: [String: String] = [:]

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int)
        -> String?
    {
        switch sectionIdentifier(for: section) {
        case .information: return localized("Purpose")
        case .directory(let path): return path
        case nil: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int)
        -> String?
    {
        guard case .directory(let directory) = sectionIdentifier(for: section) else { return nil }
        return errors[directory].map {
            localized("Read access failed") + ": " + $0
        }
    }
}

private final class CleanerCheckbox: UIView {
    private let ring = CAShapeLayer()
    private let checkmark = CAShapeLayer()
    private var checked = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for shape in [ring, checkmark] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        ring.lineWidth = 1.5
        checkmark.lineWidth = 2.2
        checkmark.strokeEnd = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 6, y: 13))
        path.addLine(to: CGPoint(x: 11, y: 18))
        path.addLine(to: CGPoint(x: 21, y: 7))
        checkmark.path = path.cgPath
        ring.strokeColor = (checked ? tintColor : UIColor.tertiaryLabel).cgColor
        checkmark.strokeColor = tintColor.cgColor
        CATransaction.commit()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    func setChecked(_ value: Bool, animated: Bool) {
        let animate = animated && value != checked && !UIAccessibility.isReduceMotionEnabled
        let oldRing = ring.presentation()?.strokeEnd ?? ring.strokeEnd
        let oldCheck = checkmark.presentation()?.strokeEnd ?? checkmark.strokeEnd
        checked = value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = value ? 0 : 1
        checkmark.strokeEnd = value ? 1 : 0
        ring.strokeColor = (value ? tintColor : UIColor.tertiaryLabel).cgColor
        checkmark.strokeColor = tintColor.cgColor
        CATransaction.commit()
        for (shape, previous) in [(ring, oldRing), (checkmark, oldCheck)] {
            shape.removeAnimation(forKey: "selection")
            if animate {
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = previous
                animation.toValue = shape.strokeEnd
                animation.duration = 0.24
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shape.add(animation, forKey: "selection")
            }
        }
    }
}

final class CleanerViewController: UITableViewController {
    private let worker = DispatchQueue(label: "wiki.qaq.umbra.cleanup", qos: .userInitiated)
    private var groups: [RHCleanGroup] = []
    private var files: [CleanFileID: RHCleanItem] = [:]
    private var failures: [String: String] = [:]
    private var dataSource: CleanerDataSource!
    private var operation: String?
    private var scanError: String?
    private var pendingRefresh: Bool?
    private var isConfirmingCleanup = false
    private var isUpdatingList = false
    private var hasLoaded = false
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var removeButton: UIBarButtonItem!
    private var progressButton: UIBarButtonItem!
    private var informationError: String?

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = localized("var Cleanup")
        view.tintColor = AppTheme.tint
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: localized("Select All"), style: .plain, target: self,
            action: #selector(toggleAll))
        removeButton = UIBarButtonItem(
            title: localized("Remove"), style: .done, target: self,
            action: #selector(confirmCleanup))
        spinner.frame = CGRect(x: 0, y: 0, width: 44, height: 32)
        spinner.isAccessibilityElement = true
        progressButton = UIBarButtonItem(customView: spinner)
        navigationItem.rightBarButtonItem = removeButton
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "File")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        dataSource = CleanerDataSource(tableView: tableView) {
            [weak self] table, indexPath, identifier in
            let cell = table.dequeueReusableCell(withIdentifier: "File", for: indexPath)
            guard let self else { return cell }
            switch identifier {
            case .file(let file):
                if let item = self.files[file] { self.configure(cell, item: item, animated: false) }
            case .information, .state:
                self.configureInformation(cell, state: identifier == .state)
            }
            return cell
        }
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(manualRefresh), for: .valueChanged)

        NotificationCenter.default.addObserver(
            self, selector: #selector(autoRefresh),
            name: UIApplication.willEnterForegroundNotification,
            object: nil)
        apply([], animated: false) { self.refresh(keepingSelection: false) }
    }

    private var items: [RHCleanItem] { groups.flatMap(\.items) }
    private var selectedItems: [RHCleanItem] { items.filter(\.checked) }
    private var allEligibleSelected: Bool { !items.contains { !$0.ignored && !$0.checked } }

    @objc private func manualRefresh() { refresh(keepingSelection: false) }
    @objc private func autoRefresh() { refresh(keepingSelection: true) }

    private func refresh(keepingSelection: Bool, afterCleanup: Bool = false) {
        guard operation == nil, !isConfirmingCleanup, !isUpdatingList else {
            pendingRefresh = (pendingRefresh ?? true) && keepingSelection
            refreshControl?.endRefreshing()
            return
        }
        let keepSelection = keepingSelection && (pendingRefresh ?? true)
        pendingRefresh = nil
        let selection =
            keepSelection
            ? Dictionary(
                items.map { ($0.path, NSNumber(value: $0.checked)) },
                uniquingKeysWith: { first, _ in first })
            : [:]
        operation = localized("Scanning…")
        updateInterface()
        worker.async { [weak self] in
            let result = Result { try RHCleaner.scan(selection: selection) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.operation = nil
                self.refreshControl?.endRefreshing()
                let wasLoaded = self.hasLoaded
                self.hasLoaded = true
                switch result {
                case .success(let groups):
                    if afterCleanup,
                        let unreadable = groups.first(where: { $0.errorMessage != nil })
                    {
                        self.scanError = unreadable.path + ": " + (unreadable.errorMessage ?? "")
                        self.apply(self.groups, animated: wasLoaded) { self.refreshIfNeeded() }
                        return
                    }
                    self.scanError = nil
                    if afterCleanup {
                        for item in groups.flatMap(\.items) where self.failures[item.path] != nil {
                            item.checked = selection[item.path]?.boolValue ?? item.checked
                        }
                    }
                    let existingPaths = Set(groups.flatMap(\.items).map(\.path))
                    self.failures = self.failures.filter { existingPaths.contains($0.key) }
                    self.apply(groups, animated: wasLoaded) { self.refreshIfNeeded() }
                case .failure(let error):
                    self.scanError = error.localizedDescription
                    self.apply(self.groups, animated: wasLoaded) { self.refreshIfNeeded() }
                }
            }
        }
    }

    private func apply(
        _ newGroups: [RHCleanGroup], animated: Bool, completion: @escaping () -> Void
    ) {
        let previous = Set(dataSource.snapshot().itemIdentifiers)
        groups = newGroups.filter { !$0.items.isEmpty || $0.errorMessage != nil }
        files = [:]
        dataSource.errors = [:]
        let errorText = groups.isEmpty ? nil : scanError
        let informationChanged = informationError != errorText
        informationError = errorText
        var snapshot = NSDiffableDataSourceSnapshot<CleanerSection, CleanerRow>()
        snapshot.appendSections([.information])
        snapshot.appendItems([.information], toSection: .information)
        if groups.isEmpty { snapshot.appendItems([.state], toSection: .information) }
        for group in groups {
            snapshot.appendSections([.directory(group.path)])
            dataSource.errors[group.path] = group.errorMessage
            let identifiers = group.items.map { item -> CleanerRow in
                let identifier = CleanFileID(directory: group.path, name: item.name)
                files[identifier] = item
                return .file(identifier)
            }
            snapshot.appendItems(identifiers, toSection: .directory(group.path))
        }
        snapshot.reconfigureItems(
            snapshot.itemIdentifiers.filter {
                previous.contains($0) && ($0 != .information || informationChanged)
            })
        isUpdatingList = true
        dataSource.apply(
            snapshot, animatingDifferences: animated && !UIAccessibility.isReduceMotionEnabled
        ) {
            self.isUpdatingList = false
            self.updateInterface()
            completion()
        }
    }

    private func refreshIfNeeded() {
        if let pendingRefresh { refresh(keepingSelection: pendingRefresh) }
    }

    @objc private func toggleAll() {
        guard operation == nil, !isUpdatingList, scanError == nil else { return }
        let deselect = allEligibleSelected
        for item in items where deselect || !item.ignored { item.checked = !deselect }
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            if case .file(let identifier) = dataSource.itemIdentifier(for: indexPath),
                let item = files[identifier],
                let cell = tableView.cellForRow(at: indexPath)
            {
                configure(cell, item: item, animated: true)
            }
        }
        updateInterface()
    }

    @objc private func confirmCleanup() {
        guard operation == nil, !isUpdatingList, scanError == nil, presentedViewController == nil,
            !selectedItems.isEmpty
        else { return }
        let paths = selectedItems.map(\.path)
        let alert = UIAlertController(
            title: localized("Remove Selected Items"),
            message: String(
                format: localized("The %ld selected items will be permanently deleted."),
                locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"),
                paths.count),
            preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(title: localized("Cancel"), style: .cancel) { [weak self] _ in
                self?.isConfirmingCleanup = false
                self?.refreshIfNeeded()
            })
        alert.addAction(
            UIAlertAction(title: localized("Remove"), style: .destructive) { [weak self] _ in
                self?.isConfirmingCleanup = false
                self?.clean(paths: paths)
            })
        isConfirmingCleanup = true
        present(alert, animated: true)
    }

    private func clean(paths: [String]) {
        operation = localized("Removing…")
        updateInterface()
        worker.async { [weak self] in
            let failures = RHCleaner.remove(paths: paths)
            let removed = Set(paths).subtracting(failures.keys)
            DispatchQueue.main.async {
                guard let self else { return }
                self.failures = failures
                for group in self.groups {
                    group.items = group.items.filter { !removed.contains($0.path) }
                }
                self.apply(self.groups, animated: true) {
                    self.operation = nil
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: failures.isEmpty
                            ? localized("Items removed")
                            : localized("Could not delete some items"))
                    self.refresh(keepingSelection: true, afterCleanup: true)
                }
            }
        }
    }

    private func updateInterface() {
        removeButton.accessibilityValue = String(
            format: localized("Selected: %ld"), selectedItems.count)
        spinner.accessibilityLabel = operation
        if operation == nil { spinner.stopAnimating() } else { spinner.startAnimating() }
        let action = operation == nil ? removeButton : progressButton
        if navigationItem.rightBarButtonItem !== action {
            navigationItem.rightBarButtonItem = action
        }
        let canEdit = operation == nil && !isUpdatingList && scanError == nil
        navigationItem.leftBarButtonItem?.title =
            allEligibleSelected
            ? localized("Deselect All") : localized("Select All")
        navigationItem.leftBarButtonItem?.isEnabled =
            canEdit && (!allEligibleSelected || !selectedItems.isEmpty)
        removeButton.isEnabled = canEdit && !selectedItems.isEmpty
        refreshControl?.isEnabled = operation == nil && !isUpdatingList
    }

    private func configureInformation(_ cell: UITableViewCell, state: Bool) {
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.accessibilityTraits = .staticText
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.color = .label
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = .secondaryLabel
        content.directionalLayoutMargins.top = 14
        content.directionalLayoutMargins.bottom = 14
        if !state {
            content.text = localized(
                "Review files in specified paths that apps may use to identify a jailbreak. Remove only items you recognize."
            )
            content.secondaryText = informationError
            content.secondaryTextProperties.color = .systemRed
        } else if !hasLoaded {
            content.text = localized("Scanning…")
            let activity = UIActivityIndicatorView(style: .medium)
            activity.startAnimating()
            cell.accessoryView = activity
        } else {
            content.text =
                scanError == nil ? localized("No Matching Items") : localized("Unable to Scan")
            content.secondaryText =
                scanError
                ?? localized("No files match the current rules. Pull down to check again.")
            content.image = UIImage(
                systemName: scanError == nil ? "checkmark.circle" : "exclamationmark.triangle")
            content.imageProperties.tintColor = scanError == nil ? AppTheme.tint : .systemOrange
        }
        cell.contentConfiguration = content
    }

    private func configure(_ cell: UITableViewCell, item: RHCleanItem, animated: Bool) {
        cell.selectionStyle = .none
        var content = cell.defaultContentConfiguration()
        content.text = item.name
        content.textProperties.numberOfLines = 0
        content.textProperties.color = item.ignored && !item.checked ? .secondaryLabel : .label
        content.image = UIImage(systemName: item.folder ? "folder" : "doc")
        content.imageProperties.tintColor =
            item.ignored && !item.checked ? .secondaryLabel : AppTheme.tint
        content.secondaryText =
            failures[item.path]
            ?? (item.ignored
                ? (item.checked
                    ? localized("Selected Manually") : localized("Protected by a custom rule"))
                : nil)
        content.secondaryTextProperties.color =
            failures[item.path] == nil ? .secondaryLabel : .systemRed
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        let checkbox = (cell.accessoryView as? CleanerCheckbox) ?? CleanerCheckbox()
        cell.accessoryView = checkbox
        checkbox.setChecked(item.checked, animated: animated)
        cell.accessibilityTraits = item.checked ? [.button, .selected] : .button
    }

    override func tableView(
        _ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int
    ) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.text = dataSource.tableView(tableView, titleForHeaderInSection: section)
        header.textLabel?.numberOfLines = 0
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath)
        -> IndexPath?
    {
        guard case .file = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard operation == nil, !isUpdatingList, scanError == nil,
            case .file(let identifier) = dataSource.itemIdentifier(for: indexPath),
            let item = files[identifier]
        else { return }
        item.checked.toggle()
        if let cell = tableView.cellForRow(at: indexPath) {
            configure(cell, item: item, animated: true)
        }
        updateInterface()
    }

    override func tableView(
        _ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard operation == nil, !isUpdatingList,
            case .file(let identifier) = dataSource.itemIdentifier(for: indexPath),
            let path = files[identifier]?.path
        else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: localized("Open in File Manager"), image: UIImage(systemName: "folder")
                ) {
                    _ in
                    guard let self else { return }
                    openInFileManager(path: path, from: self)
                },
                UIAction(title: localized("Copy Path"), image: UIImage(systemName: "doc.on.doc")) {
                    _ in
                    UIPasteboard.general.string = path
                },
            ])
        }
    }
}
