package com.vucko.cruiserconnect.car

import android.os.Handler
import android.os.Looper
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.Distance
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.Destination
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.navigation.model.Trip
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.vucko.cruiserconnect.R
import java.time.ZonedDateTime
import kotlin.math.max

/**
 * Maps-Stil-Navigation auf Android Auto: gezeichnete Karte (Surface) mit
 * Route + Zoom/Zentrieren-Buttons + Abbiege-Banner + Live-ETA.
 *
 * 2026-06-02 (vucko): Map-Steuerung ([setMapActionStrip]) verbindet die
 * Zoom-/Recenter-Buttons mit dem geteilten [CruiseCarMapSurfaceRenderer].
 * Plus echtes Manöver-Mapping, periodisches Live-Update und NavigationManager.
 */
class CruiseCarNavigationScreen(
    carContext: CarContext,
    private val routeStore: CarRouteSnapshotStore,
    private val renderer: CruiseCarMapSurfaceRenderer,
) : Screen(carContext), DefaultLifecycleObserver {

    private val handler = Handler(Looper.getMainLooper())
    private var navigationActive = false

    private val refreshRunnable = object : Runnable {
        override fun run() {
            routeStore.markCarConnected()
            val snapshot = routeStore.readSnapshot()
            if (snapshot != null && snapshot.hasRoute && snapshot.status == "navigating") {
                startNavigationManagerIfNeeded(snapshot)
                pushTripUpdate(snapshot)
            }
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

    override fun onDestroy(owner: LifecycleOwner) {
        handler.removeCallbacks(refreshRunnable)
        stopNavigationManager()
    }

    override fun onGetTemplate(): Template {
        val snapshot = routeStore.readSnapshot()
        if (snapshot == null || !snapshot.hasRoute) {
            stopNavigationManager()
            return MessageTemplate.Builder("Keine aktive Route gefunden.")
                .setTitle("Cruise Connector")
                .setHeaderAction(Action.BACK)
                .build()
        }

        val remainingMeters = snapshot.remainingDistanceMeters
            ?: snapshot.distanceMeters
            ?: 0.0
        val remainingSeconds = snapshot.remainingDurationSeconds
            ?: snapshot.durationSeconds
            ?: 0.0
        val maneuverText = snapshot.nextManeuverText ?: "Route folgen"
        val maneuverDistance = snapshot.nextManeuverDistance ?: remainingMeters
        val travelEstimate = TravelEstimate.Builder(
            Distance.create(max(0.0, remainingMeters), Distance.UNIT_METERS),
            ZonedDateTime.now().plusSeconds(max(0.0, remainingSeconds).toLong()),
        ).build()
        val step = Step.Builder(CarText.create(maneuverText))
            .setManeuver(maneuverFor(snapshot.nextManeuverKind))
            .build()
        val routingInfo = RoutingInfo.Builder()
            .setCurrentStep(
                step,
                Distance.create(max(0.0, maneuverDistance), Distance.UNIT_METERS),
            )
            .build()

        return NavigationTemplate.Builder()
            .setNavigationInfo(routingInfo)
            .setDestinationTravelEstimate(travelEstimate)
            .setMapActionStrip(mapActionStrip())
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Beenden")
                            .setOnClickListener {
                                stopNavigationManager()
                                screenManager.pop()
                            }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }

    /** Karten-Steuerung wie bei Google Maps: Zoom rein/raus, Zentrieren, Schieben. */
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

    private fun startNavigationManagerIfNeeded(snapshot: CarRouteSnapshot) {
        if (navigationActive) return
        if (!snapshot.hasRoute || snapshot.status != "navigating") return
        try {
            val manager = carContext.getCarService(NavigationManager::class.java)
            manager.setNavigationManagerCallback(object : NavigationManagerCallback {
                override fun onStopNavigation() {
                    stopNavigationManager()
                    invalidate()
                }

                override fun onAutoDriveEnabled() {
                    // Host-Simulationsmodus — keine eigene Reaktion nötig.
                }
            })
            manager.navigationStarted()
            navigationActive = true
        } catch (_: Exception) {
            navigationActive = false
        }
    }

    private fun stopNavigationManager() {
        if (!navigationActive) return
        try {
            val manager = carContext.getCarService(NavigationManager::class.java)
            manager.navigationEnded()
            manager.clearNavigationManagerCallback()
        } catch (_: Exception) {
            // Host bereits getrennt.
        }
        navigationActive = false
    }

    private fun pushTripUpdate(snapshot: CarRouteSnapshot) {
        if (!navigationActive) return
        try {
            val manager = carContext.getCarService(NavigationManager::class.java)
            val remainingMeters = snapshot.remainingDistanceMeters
                ?: snapshot.distanceMeters
                ?: return
            val remainingSeconds = snapshot.remainingDurationSeconds
                ?: snapshot.durationSeconds
                ?: 0.0
            val maneuverDistance = snapshot.nextManeuverDistance ?: remainingMeters
            val eta = ZonedDateTime.now().plusSeconds(max(0.0, remainingSeconds).toLong())
            val step = Step.Builder(CarText.create(snapshot.nextManeuverText ?: "Route folgen"))
                .setManeuver(maneuverFor(snapshot.nextManeuverKind))
                .build()
            val stepEstimate = TravelEstimate.Builder(
                Distance.create(max(0.0, maneuverDistance), Distance.UNIT_METERS),
                eta,
            ).build()
            val destination = Destination.Builder()
                .setName(snapshot.title())
                .build()
            val destinationEstimate = TravelEstimate.Builder(
                Distance.create(max(0.0, remainingMeters), Distance.UNIT_METERS),
                eta,
            ).build()
            val trip = Trip.Builder()
                .addStep(step, stepEstimate)
                .addDestination(destination, destinationEstimate)
                .setLoading(false)
                .build()
            manager.updateTrip(trip)
        } catch (_: Exception) {
            // Trip-Update ist Best-Effort; Anzeige läuft über das Template weiter.
        }
    }

    private fun maneuverFor(kind: String?): Maneuver {
        return try {
            when (kind) {
                "turnLeft" -> Maneuver.Builder(Maneuver.TYPE_TURN_NORMAL_LEFT).build()
                "turnRight" -> Maneuver.Builder(Maneuver.TYPE_TURN_NORMAL_RIGHT).build()
                "slightLeft" -> Maneuver.Builder(Maneuver.TYPE_TURN_SLIGHT_LEFT).build()
                "slightRight" -> Maneuver.Builder(Maneuver.TYPE_TURN_SLIGHT_RIGHT).build()
                "sharpLeft" -> Maneuver.Builder(Maneuver.TYPE_TURN_SHARP_LEFT).build()
                "sharpRight" -> Maneuver.Builder(Maneuver.TYPE_TURN_SHARP_RIGHT).build()
                "uturn" -> Maneuver.Builder(Maneuver.TYPE_U_TURN_LEFT).build()
                "rampLeft" -> Maneuver.Builder(Maneuver.TYPE_ON_RAMP_NORMAL_LEFT).build()
                "rampRight" -> Maneuver.Builder(Maneuver.TYPE_ON_RAMP_NORMAL_RIGHT).build()
                "forkLeft" -> Maneuver.Builder(Maneuver.TYPE_FORK_LEFT).build()
                "forkRight" -> Maneuver.Builder(Maneuver.TYPE_FORK_RIGHT).build()
                "merge" -> Maneuver.Builder(Maneuver.TYPE_MERGE_LEFT).build()
                "arrive" -> Maneuver.Builder(Maneuver.TYPE_DESTINATION).build()
                "roundabout" -> Maneuver.Builder(Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CW)
                    .setRoundaboutExitNumber(1)
                    .build()
                else -> Maneuver.Builder(Maneuver.TYPE_STRAIGHT).build()
            }
        } catch (_: Exception) {
            Maneuver.Builder(Maneuver.TYPE_STRAIGHT).build()
        }
    }

    companion object {
        private const val REFRESH_INTERVAL_MS = 1000L // K7: 2000→1000
    }
}
