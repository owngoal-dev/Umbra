import SwiftUI

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct TVNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Presentation state only. All reads and mutations go through the shared core.
final class TVModel: ObservableObject {
    @Published var ready = false
    @Published var startupError: String?
    @Published var activity: String?
    @Published var notice: TVNotice?
    @Published var apps: [UMBInstalledAppInfo] = []
    @Published var configuration: [String: Bool] = [:]
    @Published var unavailableReason: String?
    @Published var findings: [[String: String]] = []
    @Published var groups: [UMBCleanGroup] = []
    @Published var scanError: String?
    @Published var hasScanned = false
    @Published var failures: [String: String] = [:]
    private let worker = DispatchQueue(label: "wiki.qaq.umbra.tv", qos: .userInitiated)
    private var refreshPending = false

    var busy: Bool {
        activity != nil
    }

    var items: [UMBCleanItem] {
        groups.flatMap(\.items)
    }

    var selectedPaths: [String] {
        items.filter(\.checked).map(\.path)
    }

    var allSelected: Bool {
        !items.contains { !$0.ignored && !$0.checked }
    }

    func perform<Value>(
        _ title: String, work: @escaping () throws -> Value,
        completion: @escaping (Value) -> Void,
        failure: ((Error) -> Void)? = nil
    ) {
        guard !busy else { return }
        activity = localized(title)
        worker.async {
            let result = Result { try work() }
            DispatchQueue.main.async {
                self.activity = nil
                switch result {
                case let .success(value): completion(value)
                case let .failure(error):
                    if let failure {
                        failure(error)
                    } else {
                        self.show(error.localizedDescription, title: "Warning")
                    }
                }
                if self.refreshPending, !self.busy {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
    }

    func show(_ message: String, title: String) {
        notice = TVNotice(title: localized(title), message: message)
    }

    func start() {
        startupError = nil
        perform("Loading…", work: { try UMBBackend.prepare() }, completion: { _ in
            self.ready = true
            self.refresh()
        }, failure: { self.startupError = $0.localizedDescription })
    }

    func refresh() {
        guard ready else { return }
        guard !busy else { refreshPending = true; return }
        let selection = Dictionary(
            items.map { ($0.path, NSNumber(value: $0.checked)) },
            uniquingKeysWith: { first, _ in first }
        )
        let shouldScan = hasScanned
        perform("Loading…", work: {
            (
                UMBBackend.installedApps(),
                UMBBackend.configuration(forKey: "appconfig") as? [String: Bool] ?? [:],
                UMBBackend.blacklistUnavailableReason(), UMBBackend.startupWarnings(),
                shouldScan ? Result { try UMBCleaner.scan(selection: selection) } : nil
            )
        }, completion: { apps, configuration, reason, findings, scan in
            self.apps = apps.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }.sorted {
                ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending
            }
            self.configuration = configuration
            self.unavailableReason = reason
            self.findings = findings
            if let scan {
                self.applyScan(scan)
            }
        })
    }

    func isBlacklisted(_ app: UMBInstalledAppInfo) -> Bool {
        unavailableReason == nil && (configuration[app.bundleIdentifier ?? ""] ?? false)
    }

    func setBlacklisted(_ enabled: Bool, app: UMBInstalledAppInfo) {
        perform("Saving…", work: {
            if let reason = UMBBackend.blacklistUnavailableReason() ?? UMBBackend.blacklistRejection(for: app) {
                throw NSError(domain: "wiki.qaq.umbra", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
            }
            try UMBBackend.setBlacklisted(enabled, for: app)
        }, completion: { _ in self.configuration[app.bundleIdentifier ?? ""] = enabled })
    }

    func clear(_ app: UMBInstalledAppInfo) {
        perform("Clear App Data", work: { UMBBackend.clearData(for: app) }, completion: { error in
            let name = app.name ?? app.bundleIdentifier ?? ""
            self.show(
                error ?? String(format: localized("Data cleared for %@"), name),
                title: error == nil ? "Done" : "Warning"
            )
        })
    }

    func scan() {
        let selection = Dictionary(
            items.map { ($0.path, NSNumber(value: $0.checked)) },
            uniquingKeysWith: { first, _ in first }
        )
        perform("Scanning…", work: { try UMBCleaner.scan(selection: selection) }, completion: {
            self.applyScan(.success($0))
        }, failure: { self.applyScan(.failure($0)) })
    }

    private func applyScan(_ result: Result<[UMBCleanGroup], Error>) {
        hasScanned = true
        switch result {
        case let .success(groups):
            self.groups = groups
            scanError = nil
            let paths = Set(groups.flatMap(\.items).map(\.path))
            failures = failures.filter { paths.contains($0.key) }
        case let .failure(error):
            scanError = error.localizedDescription
        }
    }

    func select(_ item: UMBCleanItem, value: Bool) {
        guard !busy, scanError == nil else { return }
        objectWillChange.send()
        item.checked = value
    }

    func selectAll() {
        guard !busy, scanError == nil else { return }
        let deselect = allSelected
        objectWillChange.send()
        for item in items where deselect || !item.ignored {
            item.checked = !deselect
        }
    }

    func remove(_ paths: [String]) {
        guard scanError == nil, !paths.isEmpty else { return }
        perform("Removing…", work: { UMBCleaner.remove(paths: paths) }, completion: { failures in
            self.failures = failures
            let removed = Set(paths).subtracting(failures.keys)
            for group in self.groups {
                group.items.removeAll { removed.contains($0.path) }
            }
            self.groups = self.groups.filter { !$0.items.isEmpty || $0.errorMessage != nil }
            self.show(
                localized(failures.isEmpty ? "Items removed" : "Could not delete some items"),
                title: failures.isEmpty ? "Done" : "Warning"
            )
        })
    }
}
