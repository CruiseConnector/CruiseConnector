package com.example.cruise_connect.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class CruiseCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return CruiseCarHomeScreen(carContext, CarRouteSnapshotStore(carContext))
    }
}
