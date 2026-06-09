package com.vucko.cruiserconnect.car

import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.vucko.cruiserconnect.R

/**
 * Karten-Start-Screen für Android Auto.
 *
 * 2026-06-02 (vucko): Zeigt IMMER die Karte (NavigationTemplate + Surface) mit
 * Zoom/Zentrieren. Sobald am Handy eine Navigation startet (status=navigating),
 * springt das Auto-Display **automatisch** in die Navigations-Karte — ohne
 * Knopfdruck, wie bei Apple/Google Maps mit verbundenem System.
 */
class CruiseCarHomeScreen(
    carContext: CarContext,
    private val routeStore: CarRouteSnapshotStore,
    private val renderer: CruiseCarMapSurfaceRenderer,
) : Screen(carContext), DefaultLifecycleObserver {

    private val handler = Handler(Looper.getMainLooper())
    private var lastStatus: String? = null

    private val refreshRunnable = object : Runnable {
        override fun run() {
            routeStore.markCarConnected()
            autoEnterNavigationIfNeeded()
            invalidate()
            handler.postDelayed(this, REFRESH_INTERVAL_MS)
        }
    }

    init {
        lifecycle.addObserver(this)
    }

    override fun onResume(owner: LifecycleOwner) {
        handler.removeCallbacks(refreshRunnable)
        handler.post(refreshRunnable)
    }

    override fun onPause(owner: LifecycleOwner) {
        handler.removeCallbacks(refreshRunnable)
    }

    /**
     * Springt automatisch in die Navigations-Karte, sobald am Handy eine Route
     * gestartet wurde (Übergang zu "navigating") — nur einmal pro Navi und nur,
     * solange der Home-Screen oben liegt (kein erneutes Pushen nach Zurück).
     */
    private fun autoEnterNavigationIfNeeded() {
        val status = routeStore.readSnapshot()?.status
        if (status == "navigating" && lastStatus != "navigating" &&
            screenManager.top === this
        ) {
            screenManager.push(
                CruiseCarNavigationScreen(carContext, routeStore, renderer),
            )
        }
        lastStatus = status
    }

    override fun onGetTemplate(): Template {
        val snapshot = routeStore.readSnapshot()
        val builder = NavigationTemplate.Builder()
            .setMapActionStrip(mapActionStrip())

        when {
            snapshot != null && snapshot.hasRoute &&
                (snapshot.status == "found" || snapshot.status == "navigating") -> {
                builder.setNavigationInfo(
                    MessageInfo.Builder(
                        "${snapshot.title()} • ${formatDistance(snapshot.distanceMeters)} • " +
                            formatDuration(snapshot.durationSeconds),
                    ).build(),
                )
                builder.setActionStrip(
                    ActionStrip.Builder()
                        .addAction(
                            Action.Builder()
                                .setTitle("Navigation starten")
                                .setOnClickListener {
                                    screenManager.push(
                                        CruiseCarNavigationScreen(carContext, routeStore, renderer),
                                    )
                                }
                                .build(),
                        )
                        .addAction(
                            Action.Builder()
                                .setTitle("Neu konfigurieren")
                                .setOnClickListener {
                                    screenManager.push(CruiseCarPlanStyleScreen(carContext))
                                }
                                .build(),
                        )
                        .build(),
                )
            }

            snapshot != null && snapshot.status == "searching" -> {
                builder.setNavigationInfo(
                    MessageInfo.Builder("Route wird berechnet …").build(),
                )
                builder.setActionStrip(refreshStrip())
            }

            snapshot != null && snapshot.status == "failed" -> {
                builder.setNavigationInfo(
                    MessageInfo.Builder("Keine Route gefunden — Stil/Distanz neu wählen.").build(),
                )
                builder.setActionStrip(planStrip())
            }

            else -> {
                builder.setNavigationInfo(
                    MessageInfo.Builder(
                        "Plane eine Route — direkt hier im Auto.",
                    ).build(),
                )
                builder.setActionStrip(planStrip())
            }
        }
        return builder.build()
    }

    private fun refreshStrip(): ActionStrip {
        return ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("Aktualisieren")
                    .setOnClickListener { invalidate() }
                    .build(),
            )
            .build()
    }

    /**
     * 2026-06-09 (vucko): „Route planen" → in-car Stil/Distanz/Autobahn-Picker
     * (1:1 wie CarPlay). + „Aktualisieren" als Zweit-Aktion.
     */
    private fun planStrip(): ActionStrip {
        return ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("Route planen")
                    .setOnClickListener {
                        screenManager.push(CruiseCarPlanStyleScreen(carContext))
                    }
                    .build(),
            )
            .addAction(
                Action.Builder()
                    .setTitle("Aktualisieren")
                    .setOnClickListener { invalidate() }
                    .build(),
            )
            .build()
    }

    /** Karten-Buttons wie bei Google Maps: Zoom rein/raus, Zentrieren, Schieben. */
    private fun mapActionStrip(): ActionStrip {
        return ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setIcon(carIcon(R.drawable.ic_car_zoom_in))
                    .setOnClickListener { renderer.zoomIn() }
                    .build(),
            )
            .addAction(
                Action.Builder()
                    .setIcon(carIcon(R.drawable.ic_car_zoom_out))
                    .setOnClickListener { renderer.zoomOut() }
                    .build(),
            )
            .addAction(
                Action.Builder()
                    .setIcon(carIcon(R.drawable.ic_car_recenter))
                    .setOnClickListener { renderer.recenter() }
                    .build(),
            )
            .addAction(Action.PAN)
            .build()
    }

    private fun carIcon(resId: Int): CarIcon {
        return CarIcon.Builder(IconCompat.createWithResource(carContext, resId))
            .setTint(CarColor.DEFAULT)
            .build()
    }

    companion object {
        private const val REFRESH_INTERVAL_MS = 2000L
    }
}
