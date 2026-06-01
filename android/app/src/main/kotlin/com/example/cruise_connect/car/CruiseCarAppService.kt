package com.vucko.cruiserconnect.car

import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class CruiseCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        // 2026-06-01 (vucko): Vorher ALLOW_ALL_HOSTS für jeden Build — vor einem
        // Play-Store-Release ein Sicherheitsloch (jede App dürfte sich als Host
        // ausgeben). Jetzt: Debug-Builds (Emulator/DHU/lokale Tests) bleiben offen,
        // Release-Builds akzeptieren nur die von der Car-App-Library gepflegte
        // Allowlist der echten Hosts (Android Auto, Automotive OS, DHU). Die Liste
        // wird von androidx mitgeliefert — keine manuell gepflegten SHA-Hashes.
        val debuggable =
            applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        return if (debuggable) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }
    }

    override fun onCreateSession(): Session = CruiseCarSession()
}
