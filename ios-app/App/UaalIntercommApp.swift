import SwiftUI
import UIKit
import UaalIntercomm

final class UaalAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UnityHost.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        UnityHost.shared.applicationWillResignActive(application)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        UnityHost.shared.applicationDidEnterBackground(application)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        UnityHost.shared.applicationWillEnterForeground(application)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        UnityHost.shared.applicationDidBecomeActive(application)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        UnityHost.shared.applicationWillTerminate(application)
    }
}

@main
struct UaalIntercommApp: App {
    @UIApplicationDelegateAdaptor(UaalAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
