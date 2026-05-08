package com.vucko.cruiserconnect.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import com.vucko.cruiserconnect.R

class CruiseCarHomeScreen(
    carContext: CarContext,
    private val routeStore: CarRouteSnapshotStore,
) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val snapshot = routeStore.readSnapshot()
        return when {
            snapshot == null || snapshot.status == "idle" || snapshot.status == "ended" -> emptyTemplate()
            snapshot.status == "searching" -> searchingTemplate(snapshot)
            snapshot.status == "failed" -> failedTemplate()
            snapshot.hasRoute -> previewTemplate(snapshot)
            else -> emptyTemplate()
        }
    }

    private fun emptyTemplate(): Template {
        return MessageTemplate.Builder("Plane deine Route am Handy und sie erscheint hier.")
            .setTitle("Cruise Connector")
            .setHeaderAction(Action.APP_ICON)
            .addAction(
                Action.Builder()
                    .setTitle("Aktualisieren")
                    .setOnClickListener { invalidate() }
                    .build(),
            )
            .build()
    }

    private fun searchingTemplate(snapshot: CarRouteSnapshot): Template {
        return MessageTemplate.Builder("Wir prüfen Varianten und bereiten die Route vor.")
            .setTitle(snapshot.style ?: "Route wird berechnet")
            .setHeaderAction(Action.APP_ICON)
            .addAction(
                Action.Builder()
                    .setTitle("Aktualisieren")
                    .setOnClickListener { invalidate() }
                    .build(),
            )
            .build()
    }

    private fun failedTemplate(): Template {
        return MessageTemplate.Builder("Die letzte Routensuche konnte nicht abgeschlossen werden.")
            .setTitle("Keine Route verfügbar")
            .setHeaderAction(Action.APP_ICON)
            .addAction(
                Action.Builder()
                    .setTitle("Neu laden")
                    .setOnClickListener { invalidate() }
                    .build(),
            )
            .build()
    }

    private fun previewTemplate(snapshot: CarRouteSnapshot): Template {
        val pane = Pane.Builder()
            .addRow(
                Row.Builder()
                    .setTitle(snapshot.title())
                    .addText("${formatDistance(snapshot.distanceMeters)} • ${formatDuration(snapshot.durationSeconds)}")
                    .addText(snapshot.style ?: "Cruise Route")
                    .build(),
            )
            .addRow(
                Row.Builder()
                    .setTitle("Autobahn")
                    .addText(if (snapshot.avoidHighways) "wird vermieden" else "erlaubt, nicht Pflicht")
                    .build(),
            )
            .build()

        return PaneTemplate.Builder(pane)
            .setTitle("Route bereit")
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Navigation")
                            .setIcon(
                                CarIcon.Builder(
                                    IconCompat.createWithResource(
                                        carContext,
                                        R.drawable.ic_car_compass,
                                    ),
                                ).build(),
                            )
                            .setOnClickListener {
                                screenManager.push(
                                    CruiseCarNavigationScreen(carContext, routeStore),
                                )
                            }
                            .build(),
                    )
                    .addAction(
                        Action.Builder()
                            .setTitle("Neu laden")
                            .setOnClickListener { invalidate() }
                            .build(),
                    )
                    .build(),
            )
            .build()
    }
}
