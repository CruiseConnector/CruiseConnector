package com.example.cruise_connect.car

import android.content.Intent
import androidx.car.app.AppManager
import androidx.car.app.Screen
import androidx.car.app.Session

class CruiseCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        val routeStore = CarRouteSnapshotStore(carContext)
        carContext
            .getCarService(AppManager::class.java)
            .setSurfaceCallback(CruiseCarMapSurfaceRenderer(routeStore))
        return CruiseCarHomeScreen(carContext, routeStore)
    }
}
