package com.vucko.cruiserconnect.car

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class CruiseCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // Android Auto hosts vary by device, DHU and OEM. Tighten this before
        // public production rollout once the validated host list is known.
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session = CruiseCarSession()
}
