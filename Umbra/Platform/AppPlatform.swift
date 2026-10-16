import UIKit

enum AppPlatform {
    #if os(iOS)
        static let tableStyle = UITableView.Style.insetGrouped
        static let detailAccessory = UITableViewCell.AccessoryType.detailButton
        static let formPresentation = UIModalPresentationStyle.formSheet
    #else
        static let tableStyle = UITableView.Style.grouped
        static let detailAccessory = UITableViewCell.AccessoryType.disclosureIndicator
        static let formPresentation = UIModalPresentationStyle.fullScreen
    #endif
}

#if os(iOS)
    typealias AppSwitch = UISwitch
#else
    /// tvOS displays toggle state here; selecting the row owns the state change.
    final class AppSwitch: UIButton {
        var isOn = false { didSet { updateImage() } }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            updateImage()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setOn(_ value: Bool, animated: Bool) { isOn = value }

        private func updateImage() {
            setImage(UIImage(systemName: isOn ? "checkmark.circle.fill" : "circle"), for: .normal)
            accessibilityValue = localized(isOn ? "Enabled" : "Disabled")
            sizeToFit()
        }
    }
#endif

extension UITableViewController {
    func configureRefresh(action: Selector) {
        #if os(iOS)
            refreshControl = UIRefreshControl()
            refreshControl?.addTarget(self, action: action, for: .valueChanged)
        #else
            let button = UIButton(type: .system)
            button.setTitle(localized("Refresh"), for: .normal)
            button.addTarget(self, action: action, for: .primaryActionTriggered)
            button.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 80)
            tableView.tableFooterView = button
        #endif
    }

    func endRefreshing() {
        #if os(iOS)
            refreshControl?.endRefreshing()
        #endif
    }

    func setRefreshEnabled(_ enabled: Bool) {
        #if os(iOS)
            refreshControl?.isEnabled = enabled
        #else
            (tableView.tableFooterView as? UIButton)?.isEnabled = enabled
        #endif
    }
}
