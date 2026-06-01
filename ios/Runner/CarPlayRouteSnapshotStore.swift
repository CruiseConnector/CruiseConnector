import Foundation

struct CarPlayManeuverSnapshot {
    let instruction: String
    let announcement: String
    let routeIndex: Int
    let kind: String
}

struct CarPlayRouteSnapshot {
    let routeId: String?
    let fingerprint: String?
    let routeType: String
    let status: String
    let coordinates: [[Double]]
    let maneuvers: [CarPlayManeuverSnapshot]
    let distanceMeters: Double?
    let durationSeconds: Double?
    let remainingDistanceMeters: Double?
    let remainingDurationSeconds: Double?
    let nextManeuverText: String?
    let nextManeuverDistance: Double?
    let nextManeuverKind: String?
    let style: String?
    let avoidHighways: Bool
    let updatedAt: String?

    var hasRoute: Bool { coordinates.count >= 2 }
}

final class CarPlayRouteSnapshotStore {
    func readSnapshot() -> CarPlayRouteSnapshot? {
        guard
            let raw = readString("flutter.car_route_snapshot") ?? readString("car_route_snapshot"),
            var snapshot = parseSnapshot(raw)
        else {
            return nil
        }
        if let progressRaw = readString("flutter.car_route_progress_snapshot")
            ?? readString("car_route_progress_snapshot") {
            snapshot = mergeProgress(snapshot, progressRaw: progressRaw)
        }
        return snapshot
    }

    private func readString(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    private func mergeProgress(
        _ snapshot: CarPlayRouteSnapshot,
        progressRaw: String
    ) -> CarPlayRouteSnapshot {
        guard
            let data = progressRaw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return snapshot
        }
        return CarPlayRouteSnapshot(
            routeId: snapshot.routeId,
            fingerprint: snapshot.fingerprint,
            routeType: snapshot.routeType,
            status: json["status"] as? String ?? snapshot.status,
            coordinates: snapshot.coordinates,
            maneuvers: snapshot.maneuvers,
            distanceMeters: snapshot.distanceMeters,
            durationSeconds: snapshot.durationSeconds,
            remainingDistanceMeters: json["remainingDistanceMeters"] as? Double
                ?? snapshot.remainingDistanceMeters,
            remainingDurationSeconds: json["remainingDurationSeconds"] as? Double
                ?? snapshot.remainingDurationSeconds,
            nextManeuverText: json["nextManeuverText"] as? String
                ?? snapshot.nextManeuverText,
            nextManeuverDistance: json["nextManeuverDistance"] as? Double
                ?? snapshot.nextManeuverDistance,
            nextManeuverKind: json["nextManeuverKind"] as? String
                ?? snapshot.nextManeuverKind,
            style: snapshot.style,
            avoidHighways: snapshot.avoidHighways,
            updatedAt: json["updatedAt"] as? String ?? snapshot.updatedAt
        )
    }

    private func parseSnapshot(_ raw: String) -> CarPlayRouteSnapshot? {
        guard
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let coordinates = json["coordinates"] as? [[Double]] ?? []
        let maneuverJson = json["maneuvers"] as? [[String: Any]] ?? []
        let maneuvers = maneuverJson.map {
            CarPlayManeuverSnapshot(
                instruction: $0["instruction"] as? String ?? "",
                announcement: $0["announcement"] as? String ?? "",
                routeIndex: $0["routeIndex"] as? Int ?? 0,
                kind: $0["kind"] as? String ?? "straight"
            )
        }
        return CarPlayRouteSnapshot(
            routeId: json["routeId"] as? String,
            fingerprint: json["fingerprint"] as? String,
            routeType: json["routeType"] as? String ?? "roundtrip",
            status: json["status"] as? String ?? "idle",
            coordinates: coordinates,
            maneuvers: maneuvers,
            distanceMeters: json["distanceMeters"] as? Double,
            durationSeconds: json["durationSeconds"] as? Double,
            remainingDistanceMeters: json["remainingDistanceMeters"] as? Double,
            remainingDurationSeconds: json["remainingDurationSeconds"] as? Double,
            nextManeuverText: json["nextManeuverText"] as? String,
            nextManeuverDistance: json["nextManeuverDistance"] as? Double,
            nextManeuverKind: json["nextManeuverKind"] as? String,
            style: json["style"] as? String,
            avoidHighways: json["avoidHighways"] as? Bool ?? false,
            updatedAt: json["updatedAt"] as? String
        )
    }
}
