import SwiftUI
import UIKit

/// Keep main.m as the entry point: it also dispatches the existing privileged helpers.
@objc(UMBAppDelegate)
final class TVAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let model = TVModel()
    private var cleanupTimer: Timer?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: TVRootView().environmentObject(model))
        self.window = window
        window.makeKeyAndVisible()
        model.start()
        return true
    }

    func applicationDidEnterBackground(_: UIApplication) {
        cleanupTimer?.invalidate()
        var count = 0
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            UMBBackend.cleanOwnApplicationFiles()
            count += 1
            if count > 40 {
                timer.invalidate()
            }
        }
    }

    func applicationWillEnterForeground(_: UIApplication) {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        model.refresh()
    }
}
