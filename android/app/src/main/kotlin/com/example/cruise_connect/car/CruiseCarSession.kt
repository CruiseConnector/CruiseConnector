package com.vucko.cruiserconnect.car

import android.content.Intent
import androidx.car.app.AppManager
import androidx.car.app.Screen
import androidx.car.app.Session

class CruiseCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        val routeStore = CarRouteSnapshotStore(carContext)
        // Eine geteilte Renderer-Instanz: die Map-Buttons im NavigationScreen
        // steuern damit dieselbe Karte, die als Surface gezeichnet wird.
        val renderer = CruiseCarMapSurfaceRenderer(routeStore)
        carContext
            .getCarService(AppManager::class.java)
            .setSurfaceCallback(renderer)
        return CruiseCarHomeScreen(carContext, routeStore, renderer)
    }
}
