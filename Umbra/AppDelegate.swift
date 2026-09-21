import UIKit

@objc(AppDelegate)
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var cleanupTimer: Timer?
    private var environmentCheck: EnvironmentCheck?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.tintColor = AppTheme.tint
        self.window = window
        prepareApplication()
        window.makeKeyAndVisible()
        return true
    }

    private func prepareApplication() {
        do {
            try RHBackend.prepare()
            let check = EnvironmentCheck()
            environmentCheck = check
            let applications = ApplicationsViewController(check: check)
            let cleaner = CleanerViewController()
            let controllers: [(UIViewController, String, String)] = [
                (applications, localized("Blacklist"), "shield"),
                (cleaner, localized("var Cleanup"), "folder"),
                (SettingsViewController(check: check), localized("Settings"), "gearshape"),
            ]
            let tabs = UITabBarController()
            tabs.viewControllers = controllers.enumerated().map { index, item in
                let navigation = UINavigationController(rootViewController: item.0)
                navigation.navigationBar.prefersLargeTitles = true
                navigation.tabBarItem = UITabBarItem(
                    title: item.1, image: UIImage(systemName: item.2), tag: index)
                return navigation
            }
            applications.loadViewIfNeeded()
            cleaner.loadViewIfNeeded()
            window?.rootViewController = tabs
        } catch {
            window?.rootViewController = StartupErrorViewController(error: error) { [weak self] in
                self?.prepareApplication()
            }
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        cleanupTimer?.invalidate()
        var count = 0
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            RHBackend.cleanOwnApplicationFiles()
            count += 1
            if count > 40 { timer.invalidate() }
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        environmentCheck?.refresh()
    }
}

private final class StartupErrorViewController: UIViewController {
    private let error: Error
    private let onRetry: () -> Void

    init(error: Error, onRetry: @escaping () -> Void) {
        self.error = error
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let message = UILabel()
        message.text = localized("Startup failed") + "\n\n" + error.localizedDescription
        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        let retry = UIButton(type: .system)
        retry.setTitle(localized("Try Again"), for: .normal)
        retry.addAction(UIAction { [weak self] _ in self?.onRetry() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [message, retry])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
        ])
    }
}
