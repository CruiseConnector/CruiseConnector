package com.vucko.cruiserconnect.car

import android.content.Context
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import org.json.JSONObject

/**
 * In-Car-Routenplaner für Android Auto — DESIGN 1:1 wie CarPlay
 * (ios/Runner/CarPlayRouteCoordinator.swift: presentStylePicker → presentDistancePicker
 * → presentHighwayPicker → submitPlan).
 *
 * 2026-06-09 (vucko): Android Auto konnte bisher nur eine am Handy geplante Route
 * anzeigen. Jetzt der gleiche listen-basierte 3-Schritt-Flow wie CarPlay:
 *   Fahrstil → Distanz (25/50/75/100 km) → Autobahn an/aus → planRoute.
 * Der Befehl geht über DENSELBEN Kanal wie iOS: ein JSON-String in
 * FlutterSharedPreferences unter `flutter.car_command` mit monoton steigender
 * requestId. Der CarCommandListener (Flutter) pollt ihn (1,5s) und löst die
 * Rundkurs-Suche aus — identisch zur CarPlay-Seite.
 */

/** Stil-Schlüssel + Anzeigename — exakt wie CarPlay (styleDisplayName). */
private val PLAN_STYLES = listOf(
    "Sport Mode" to "Sport — flüssig & schnell",
    "Kurvenjagd" to "Kurvenjagd — maximale Kurven",
    "Abendrunde" to "Abendrunde — ruhig & entspannt",
    "Entdecker" to "Entdecker — neue Strecken",
)

/** Exakt die App-/CarPlay-Distanzen. */
private val PLAN_DISTANCES = listOf(25, 50, 75, 100)

/**
 * Schreibt den planRoute-Befehl in FlutterSharedPreferences — gleiche Payload +
 * Key wie CarPlays writeCommand(). System.currentTimeMillis() ist monoton steigend
 * → Flutter führt nur neue Befehle aus (requestId > _lastHandledRequestId).
 */
private fun writeCarPlanCommand(
    carContext: CarContext,
    style: String,
    km: Int,
    avoidHighways: Boolean,
) {
    val prefs = carContext.getSharedPreferences(
        "FlutterSharedPreferences",
        Context.MODE_PRIVATE,
    )
    val payload = JSONObject()
        .put("action", "planRoute")
        .put("style", style)
        .put("distanceKm", km)
        .put("avoidHighways", avoidHighways)
        .put("requestId", System.currentTimeMillis())
    prefs.edit().putString("flutter.car_command", payload.toString()).apply()
}

/** Schritt 1: Fahrstil. */
class CruiseCarPlanStyleScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for ((style, label) in PLAN_STYLES) {
            list.addItem(
                Row.Builder()
                    .setTitle(label)
                    .setBrowsable(true)
                    .setOnClickListener {
                        screenManager.push(CruiseCarPlanDistanceScreen(carContext, style))
                    }
                    .build(),
            )
        }
        return ListTemplate.Builder()
            .setHeaderAction(Action.BACK)
            .setTitle("Fahrstil wählen")
            .setSingleList(list.build())
            .build()
    }
}

/** Schritt 2: Distanz (25/50/75/100 km). */
class CruiseCarPlanDistanceScreen(
    carContext: CarContext,
    private val style: String,
) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        for (km in PLAN_DISTANCES) {
            list.addItem(
                Row.Builder()
                    .setTitle("$km km")
                    .setBrowsable(true)
                    .setOnClickListener {
                        screenManager.push(
                            CruiseCarPlanHighwayScreen(carContext, style, km),
                        )
                    }
                    .build(),
            )
        }
        return ListTemplate.Builder()
            .setHeaderAction(Action.BACK)
            .setTitle("Distanz wählen")
            .setSingleList(list.build())
            .build()
    }
}

/** Schritt 3: Autobahn an/aus → planRoute. */
class CruiseCarPlanHighwayScreen(
    carContext: CarContext,
    private val style: String,
    private val km: Int,
) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
            .addItem(
                Row.Builder()
                    .setTitle("Autobahn an")
                    .addText("Autobahn erlaubt")
                    .setOnClickListener { submit(avoidHighways = false) }
                    .build(),
            )
            .addItem(
                Row.Builder()
                    .setTitle("Autobahn aus")
                    .addText("Autobahn vermeiden")
                    .setOnClickListener { submit(avoidHighways = true) }
                    .build(),
            )
        return ListTemplate.Builder()
            .setHeaderAction(Action.BACK)
            .setTitle("Autobahn")
            .setSingleList(list.build())
            .build()
    }

    private fun submit(avoidHighways: Boolean) {
        writeCarPlanCommand(carContext, style, km, avoidHighways)
        // Zurück zur Karte (Root) — der Snapshot wechselt dann searching → found.
        screenManager.popToRoot()
    }
}
