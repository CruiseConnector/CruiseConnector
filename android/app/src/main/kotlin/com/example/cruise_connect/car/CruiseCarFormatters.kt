package com.example.cruise_connect.car

import java.util.Locale
import kotlin.math.roundToInt

fun formatDistance(meters: Double?): String {
    if (meters == null || meters <= 0.0) return "--"
    if (meters < 1000.0) return "${meters.roundToInt()} m"
    return String.format(Locale.GERMAN, "%.1f km", meters / 1000.0)
}

fun formatDuration(seconds: Double?): String {
    if (seconds == null || seconds <= 0.0) return "--"
    val minutes = (seconds / 60.0).roundToInt()
    if (minutes < 60) return "${minutes} min"
    val hours = minutes / 60
    val rest = minutes % 60
    return if (rest == 0) "${hours} h" else "${hours} h ${rest} min"
}

fun CarRouteSnapshot.title(): String {
    return when (routeType) {
        "point_to_point" -> "A nach B"
        "waypoints" -> "Wegpunkte"
        else -> "Rundkurs"
    }
}
