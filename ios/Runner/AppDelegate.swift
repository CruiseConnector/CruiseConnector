import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        if let registrar = registrar(forPlugin: "NavigationLiveActivityPlugin") {
            NavigationLiveActivityPlugin.register(with: registrar)
        }

        // 2026-06-25 (vucko): Instagram-Stories-Sticker-Brücke. Legt den
        // transparenten Sticker aufs Pasteboard und öffnet instagram-stories://
        // — Instagram öffnet die Story mit dem Sticker obenauf (Nutzer macht
        // sein Selfie als Hintergrund + verschiebt/skaliert den Sticker in IG).
        // Fail-safe: false → Dart fällt aufs normale Teilen zurück.
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "cruise/instagram_story",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { call, result in
                switch call.method {
                case "isInstagramAvailable":
                    result(AppDelegate.canOpenInstagramStories())
                case "shareStorySticker":
                    let args = call.arguments as? [String: Any]
                    let path = args?["stickerPath"] as? String
                    let appId = (args?["appId"] as? String) ?? ""
                    result(AppDelegate.shareSticker(path: path, appId: appId))
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private static func canOpenInstagramStories() -> Bool {
        guard let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private static func shareSticker(path: String?, appId: String) -> Bool {
        guard let path = path,
              let image = UIImage(contentsOfFile: path),
              let data = image.pngData() else { return false }
        let urlStr = appId.isEmpty
            ? "instagram-stories://share"
            : "instagram-stories://share?source_application=\(appId)"
        guard let url = URL(string: urlStr),
              UIApplication.shared.canOpenURL(url) else { return false }
        let items: [[String: Any]] = [
            ["com.instagram.sharedSticker.stickerImage": data]
        ]
        let options: [UIPasteboard.OptionsKey: Any] = [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ]
        UIPasteboard.general.setItems(items, options: options)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
}
