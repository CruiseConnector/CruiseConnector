package com.vucko.cruiserconnect.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarText
import androidx.car.app.model.Distance
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import java.time.ZonedDateTime
import kotlin.math.max

class CruiseCarNavigationScreen(
    carContext: CarContext,
    private val routeStore: CarRouteSnapshotStore,
) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val snapshot = routeStore.readSnapshot()
        if (snapshot == null || !snapshot.hasRoute) {
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
            .setManeuver(Maneuver.Builder(Maneuver.TYPE_STRAIGHT).build())
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
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Aktualisieren")
                            .setOnClickListener { invalidate() }
                            .build(),
                    )
                    .addAction(
                        Action.Builder()
                            .setTitle("Zurück")
                            .setOnClickListener { screenManager.pop() }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }
}
