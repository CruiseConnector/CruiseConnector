package com.vucko.cruiserconnect.car

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class CarManeuverSnapshot(
    val instruction: String,
    val announcement: String,
    val routeIndex: Int,
    val kind: String,
)

data class CarRouteSnapshot(
    val routeId: String?,
    val fingerprint: String?,
    val routeType: String,
    val status: String,
    val coordinates: List<Pair<Double, Double>>,
    val maneuvers: List<CarManeuverSnapshot>,
    val distanceMeters: Double?,
    val durationSeconds: Double?,
    val remainingDistanceMeters: Double?,
    val remainingDurationSeconds: Double?,
    val nextManeuverText: String?,
    val nextManeuverDistance: Double?,
    val nextManeuverKind: String?,
    val style: String?,
    val avoidHighways: Boolean,
    val updatedAt: String?,
) {
    val hasRoute: Boolean
        get() = coordinates.size >= 2
}

class CarRouteSnapshotStore(private val context: Context) {
    fun readSnapshot(): CarRouteSnapshot? {
        val raw = readString("flutter.car_route_snapshot")
            ?: readString("car_route_snapshot")
            ?: return null
        val base = parseSnapshot(raw) ?: return null
        val progress = readString("flutter.car_route_progress_snapshot")
            ?: readString("car_route_progress_snapshot")
        if (progress.isNullOrBlank()) return base
        return mergeProgress(base, progress)
    }

    private fun readString(key: String): String? {
        val flutterPrefs = context.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return flutterPrefs.getString(key, null)
    }

    private fun mergeProgress(
        snapshot: CarRouteSnapshot,
        rawProgress: String,
    ): CarRouteSnapshot {
        return try {
            val json = JSONObject(rawProgress)
            snapshot.copy(
                status = json.optString("status", snapshot.status),
                remainingDistanceMeters = json.optNullableDouble(
                    "remainingDistanceMeters",
                    snapshot.remainingDistanceMeters,
                ),
                remainingDurationSeconds = json.optNullableDouble(
                    "remainingDurationSeconds",
                    snapshot.remainingDurationSeconds,
                ),
                nextManeuverText = json.optNullableString(
                    "nextManeuverText",
                    snapshot.nextManeuverText,
                ),
                nextManeuverDistance = json.optNullableDouble(
                    "nextManeuverDistance",
                    snapshot.nextManeuverDistance,
                ),
                nextManeuverKind = json.optNullableString(
                    "nextManeuverKind",
                    snapshot.nextManeuverKind,
                ),
                updatedAt = json.optNullableString("updatedAt", snapshot.updatedAt),
            )
        } catch (_: Exception) {
            snapshot
        }
    }

    private fun parseSnapshot(raw: String): CarRouteSnapshot? {
        return try {
            val json = JSONObject(raw)
            CarRouteSnapshot(
                routeId = json.optNullableString("routeId"),
                fingerprint = json.optNullableString("fingerprint"),
                routeType = json.optString("routeType", "roundtrip"),
                status = json.optString("status", "idle"),
                coordinates = json.optJSONArray("coordinates").toCoordinatePairs(),
                maneuvers = json.optJSONArray("maneuvers").toManeuvers(),
                distanceMeters = json.optNullableDouble("distanceMeters"),
                durationSeconds = json.optNullableDouble("durationSeconds"),
                remainingDistanceMeters = json.optNullableDouble(
                    "remainingDistanceMeters",
                ),
                remainingDurationSeconds = json.optNullableDouble(
                    "remainingDurationSeconds",
                ),
                nextManeuverText = json.optNullableString("nextManeuverText"),
                nextManeuverDistance = json.optNullableDouble("nextManeuverDistance"),
                nextManeuverKind = json.optNullableString("nextManeuverKind"),
                style = json.optNullableString("style"),
                avoidHighways = json.optBoolean("avoidHighways", false),
                updatedAt = json.optNullableString("updatedAt"),
            )
        } catch (_: Exception) {
            null
        }
    }
}

private fun JSONArray?.toCoordinatePairs(): List<Pair<Double, Double>> {
    if (this == null) return emptyList()
    val output = ArrayList<Pair<Double, Double>>(length())
    for (index in 0 until length()) {
        val item = optJSONArray(index) ?: continue
        if (item.length() < 2) continue
        output.add(item.optDouble(0) to item.optDouble(1))
    }
    return output
}

private fun JSONArray?.toManeuvers(): List<CarManeuverSnapshot> {
    if (this == null) return emptyList()
    val output = ArrayList<CarManeuverSnapshot>(length())
    for (index in 0 until length()) {
        val item = optJSONObject(index) ?: continue
        output.add(
            CarManeuverSnapshot(
                instruction = item.optString("instruction"),
                announcement = item.optString("announcement"),
                routeIndex = item.optInt("routeIndex"),
                kind = item.optString("kind", "straight"),
            ),
        )
    }
    return output
}

private fun JSONObject.optNullableString(
    key: String,
    fallback: String? = null,
): String? {
    if (!has(key) || isNull(key)) return fallback
    val value = optString(key, "")
    return value.takeIf { it.isNotBlank() } ?: fallback
}

private fun JSONObject.optNullableDouble(
    key: String,
    fallback: Double? = null,
): Double? {
    if (!has(key) || isNull(key)) return fallback
    val value = optDouble(key, Double.NaN)
    return if (value.isNaN()) fallback else value
}
