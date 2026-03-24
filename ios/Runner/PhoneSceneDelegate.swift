import Flutter
import UIKit

/// Scene delegate for the phone (main) window.
/// Keeps the existing Flutter view controller lifecycle working with the new
/// scene-based app configuration required by CarPlay.
class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Re-use the FlutterViewController from the AppDelegate's storyboard
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        if let existingWindow = appDelegate.window {
            existingWindow.windowScene = windowScene
            self.window = existingWindow
        } else {
            let window = UIWindow(windowScene: windowScene)
            let flutterVC = FlutterViewController(
                engine: FlutterEngine(name: "io.flutter", project: nil),
                nibName: nil,
                bundle: nil
            )
            window.rootViewController = flutterVC
            window.makeKeyAndVisible()
            self.window = window
            appDelegate.window = window
        }
    }
}
