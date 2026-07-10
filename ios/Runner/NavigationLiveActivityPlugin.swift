import Flutter
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct CruiseNavigationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var instruction: String
        var maneuverType: String
        var distanceToManeuverMeters: Double?
        var remainingDistanceMeters: Double?
        var remainingDurationSeconds: Int?
        var isRerouting: Bool
        var updatedAt: Date
    }

    var routeName: String
}

@available(iOS 16.1, *)
final class CruiseNavigationLiveActivityStore {
    static var current: Activity<CruiseNavigationAttributes>?
}
#endif

final class NavigationLiveActivityPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "cruise_connect/navigation_live_activity",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(NavigationLiveActivityPlugin(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            guard let payload = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_args", message: "Missing payload", details: nil))
                return
            }
            start(payload: payload, result: result)
        case "update":
            guard let payload = call.arguments as? [String: Any] else {
                result(FlutterError(code: "bad_args", message: "Missing payload", details: nil))
                return
            }
            update(payload: payload, result: result)
        case "end":
            end(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func start(payload: [String: Any], result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else {
            result(FlutterError(code: "unsupported", message: "Live Activities require iOS 16.1+", details: nil))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            result(FlutterError(code: "disabled", message: "Live Activities are disabled", details: nil))
            return
        }

        let state = makeState(payload)
        Task {
            do {
                if let current = CruiseNavigationLiveActivityStore.current {
                    await updateActivity(current, state: state)
                    result(nil)
                    return
                }
                let attributes = CruiseNavigationAttributes(routeName: "Cruise läuft")
                let activity: Activity<CruiseNavigationAttributes>
                if #available(iOS 16.2, *) {
                    // staleDate: bleibt ein Update aus (z. B. weil iOS das
                    // Update-Budget drosselt), markiert das System den Inhalt
                    // als veraltet, statt ihn als frisch anzuzeigen.
                    activity = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)),
                        pushType: nil
                    )
                } else {
                    activity = try Activity.request(
                        attributes: attributes,
                        contentState: state,
                        pushType: nil
                    )
                }
                CruiseNavigationLiveActivityStore.current = activity
                result(nil)
            } catch {
                result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
            }
        }
        #else
        result(FlutterError(code: "unsupported", message: "ActivityKit unavailable", details: nil))
        #endif
    }

    private func update(payload: [String: Any], result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else {
            result(FlutterError(code: "unsupported", message: "Live Activities require iOS 16.1+", details: nil))
            return
        }
        guard let activity = CruiseNavigationLiveActivityStore.current else {
            result(nil)
            return
        }
        let state = makeState(payload)
        Task {
            await updateActivity(activity, state: state)
            result(nil)
        }
        #else
        result(FlutterError(code: "unsupported", message: "ActivityKit unavailable", details: nil))
        #endif
    }

    private func end(result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else {
            result(nil)
            return
        }
        guard let activity = CruiseNavigationLiveActivityStore.current else {
            result(nil)
            return
        }
        CruiseNavigationLiveActivityStore.current = nil
        Task {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
            result(nil)
        }
        #else
        result(nil)
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func makeState(_ payload: [String: Any]) -> CruiseNavigationAttributes.ContentState {
        CruiseNavigationAttributes.ContentState(
            instruction: string(payload["instruction"], fallback: "Der Route folgen"),
            maneuverType: string(payload["maneuverType"], fallback: "continue"),
            distanceToManeuverMeters: double(payload["distanceToManeuverMeters"]),
            remainingDistanceMeters: double(payload["remainingDistanceMeters"]),
            remainingDurationSeconds: int(payload["remainingDurationSeconds"]),
            isRerouting: bool(payload["isRerouting"]),
            updatedAt: Date()
        )
    }

    @available(iOS 16.1, *)
    private func updateActivity(
        _ activity: Activity<CruiseNavigationAttributes>,
        state: CruiseNavigationAttributes.ContentState
    ) async {
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)))
        } else {
            await activity.update(using: state)
        }
    }
    #endif

    private func string(_ value: Any?, fallback: String) -> String {
        let raw = value as? String ?? fallback
        return raw.isEmpty ? fallback : raw
    }

    private func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }
}
