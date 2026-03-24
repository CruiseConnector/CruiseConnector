import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    /// Shared Flutter engine – used by both the phone scene and CarPlay.
    static let shared = AppDelegate()
    var flutterEngine: FlutterEngine?
    var carPlayChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Setup CarPlay MethodChannel
        if let controller = window?.rootViewController as? FlutterViewController {
            carPlayChannel = FlutterMethodChannel(
                name: "com.cruiseconnect/carplay",
                binaryMessenger: controller.binaryMessenger
            )

            // Listen for results from Flutter
            carPlayChannel?.setMethodCallHandler { [weak self] call, result in
                switch call.method {
                case "routeGenerated":
                    if let args = call.arguments as? [String: Any] {
                        CarPlaySceneDelegate.instance?.onRouteGenerated(args)
                    }
                    result(nil)
                case "routeError":
                    let msg = call.arguments as? String ?? "Unbekannter Fehler"
                    CarPlaySceneDelegate.instance?.onRouteError(msg)
                    result(nil)
                case "updateSavedRoutes":
                    if let routes = call.arguments as? [[String: Any]] {
                        CarPlaySceneDelegate.instance?.updateSavedRoutes(routes)
                    }
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Scene Configuration
    override func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == UISceneSession.Role(rawValue: "CPTemplateApplicationSceneSessionRoleApplication") {
            let config = UISceneConfiguration(
                name: "CarPlay Configuration",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }

        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = PhoneSceneDelegate.self
        config.storyboard = UIStoryboard(name: "Main", bundle: nil)
        return config
    }
}
