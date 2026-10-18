import UIKit

enum AppPlatform {
    #if os(iOS)
        static let tableStyle = UITableView.Style.insetGrouped
        static let detailAccessory = UITableViewCell.AccessoryType.detailButton
        static let formPresentation = UIModalPresentationStyle.formSheet
        static let applicationIconSize = CGSize(width: 44, height: 44)
        static let applicationIconCornerRadius: CGFloat = 10
        static let listSymbolPointSize: CGFloat = 26
        static let listSymbolReservedSize = CGSize(width: 32, height: 26)
        static let selectionIndicatorSize: CGFloat = 26
    #else
        static let tableStyle = UITableView.Style.grouped
        static let detailAccessory = UITableViewCell.AccessoryType.disclosureIndicator
        static let formPresentation = UIModalPresentationStyle.fullScreen
        static let applicationIconSize = CGSize(width: 64, height: 64)
        static let applicationIconCornerRadius: CGFloat = 14
        static let listSymbolPointSize: CGFloat = 34
        static let listSymbolReservedSize = CGSize(width: 44, height: 36)
        static let selectionIndicatorSize: CGFloat = 38
    #endif
}

#if os(iOS)
    typealias AppSwitch = UISwitch
#else
    /// tvOS exposes state as a readable badge; selecting the focused row changes it.
    final class AppSwitch: UIControl {
        private let label = UILabel()
        var isOn = false { didSet { updateAppearance() } }

        override var isEnabled: Bool {
            didSet { updateAppearance() }
        }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            label.font = .preferredFont(forTextStyle: .callout)
            label.adjustsFontForContentSizeCategory = true
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            ])
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            updateAppearance()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: CGSize {
            let font = label.font ?? .preferredFont(forTextStyle: .callout)
            let enabledWidth = (localized("Enabled") as NSString).size(withAttributes: [.font: font]
            ).width
            let disabledWidth = (localized("Disabled") as NSString).size(withAttributes: [
                .font: font
            ]).width
            return CGSize(
                width: ceil(max(enabledWidth, disabledWidth)) + 36,
                height: ceil(font.lineHeight) + 16
            )
        }

        func setOn(_ value: Bool, animated: Bool) {
            guard value != isOn else { return }
            isOn = value
            guard animated, !UIAccessibility.isReduceMotionEnabled else { return }
            transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            UIView.animate(
                withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .curveEaseOut]
            ) {
                self.transform = .identity
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = bounds.height / 2
        }

        private func updateAppearance() {
            let title = localized(isOn ? "Enabled" : "Disabled")
            label.text = title
            label.textColor = isOn ? .white : .secondaryLabel
            backgroundColor = isOn ? AppTheme.tint : .clear
            layer.borderColor = (isOn ? AppTheme.tint : UIColor.tertiaryLabel).cgColor
            alpha = isEnabled ? 1 : 0.45
            accessibilityValue = title
            invalidateIntrinsicContentSize()
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
