import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

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

@main
struct CruiseNavigationLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CruiseNavigationLiveActivity()
    }
}

struct CruiseNavigationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CruiseNavigationAttributes.self) { context in
            NavigationLiveActivityView(state: context.state)
                .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ManeuverBadge(state: context.state, compact: false)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.isRerouting ? "Neuberechnung" : context.state.instruction)
                            .font(.headline.weight(.heavy))
                            .lineLimit(2)
                        Text(formatRemaining(context.state.remainingDistanceMeters))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatDistance(context.state.distanceToManeuverMeters))
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                }
            } compactLeading: {
                ManeuverBadge(state: context.state, compact: true)
            } compactTrailing: {
                Text(formatDistance(context.state.distanceToManeuverMeters))
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: iconName(for: context.state))
            }
        }
    }
}

struct NavigationLiveActivityView: View {
    let state: CruiseNavigationAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ManeuverBadge(state: state, compact: false)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.isRerouting ? "Route wird neu berechnet" : state.instruction)
                    .font(.headline.weight(.heavy))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                HStack(spacing: 10) {
                    Label(formatDistance(state.distanceToManeuverMeters), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    Label(formatRemaining(state.remainingDistanceMeters), systemImage: "road.lanes")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.70))
            }
            Spacer(minLength: 4)
            if let seconds = state.remainingDurationSeconds {
                Text(formatDuration(seconds))
                    .font(.subheadline.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

struct ManeuverBadge: View {
    let state: CruiseNavigationAttributes.ContentState
    let compact: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 9 : 16, style: .continuous)
                .fill(state.isRerouting ? Color.orange.opacity(0.22) : Color.red.opacity(0.22))
            Image(systemName: iconName(for: state))
                .font(.system(size: compact ? 14 : 25, weight: .heavy))
                .foregroundStyle(state.isRerouting ? .orange : .red)
        }
        .frame(width: compact ? 28 : 52, height: compact ? 28 : 52)
    }
}

private func iconName(for state: CruiseNavigationAttributes.ContentState) -> String {
    if state.isRerouting { return "arrow.triangle.2.circlepath" }
    if state.maneuverType.hasPrefix("roundabout") { return "arrow.clockwise.circle.fill" }
    switch state.maneuverType {
    case "left":
        return "arrow.turn.up.left"
    case "right":
        return "arrow.turn.up.right"
    case "uturn":
        return "arrow.uturn.backward"
    case "arrival":
        return "flag.checkered"
    default:
        return "arrow.up"
    }
}

private func formatDistance(_ meters: Double?) -> String {
    guard let meters else { return "--" }
    let m = max(0.0, meters)
    if m < 10 {
        return "Jetzt"
    }
    if m < 1000 {
        let step = m <= 200 ? 10.0 : (m <= 500 ? 20.0 : 50.0)
        let rounded = min(990, max(0, Int((m / step).rounded() * step)))
        return "\(rounded) m"
    }
    let km = m / 1000.0
    return String(format: "%.1f km", km)
}

private func formatRemaining(_ meters: Double?) -> String {
    guard let meters else { return "Route aktiv" }
    if meters < 1000 {
        return "\(max(0, Int(meters.rounded()))) m verbleibend"
    }
    return String(format: "%.1f km verbleibend", meters / 1000.0)
}

private func formatDuration(_ seconds: Int) -> String {
    let minutes = max(0, seconds / 60)
    if minutes < 60 {
        return "\(minutes) min"
    }
    return "\(minutes / 60) h \(minutes % 60) min"
}
