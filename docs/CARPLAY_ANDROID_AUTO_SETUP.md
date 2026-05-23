# CarPlay & Android Auto — Setup-Plan

**Status (2026-05-24)**: Flutter-Bridge ist da, native Targets fehlen.

## Was bereits funktioniert (Flutter-Side)

[CarRouteBridgeService](../lib/data/services/car_route_bridge_service.dart) schreibt
strukturierte Snapshots der aktuellen Route + Navigation-State in
SharedPreferences. Diese können von einem native CarPlay/Android-Auto
Target gelesen werden.

Published States:
- `publishSearching()` — Route wird gesucht
- `publishFound()` — Route gefunden, mit Distanz/Dauer/Manöver
- `publishNavigationStarted()` — Navigation aktiv
- `publishProgress()` — Live-Updates während Fahrt (gedrosselt 3s)

## Was fehlt für echtes CarPlay (iOS)

1. **App-Group** in Apple Developer Portal anlegen:
   - Identifier: `group.com.cruiseconnect.shared`
   - In Xcode beiden Targets (App + CarPlay) hinzufügen

2. **CarPlay-Entitlement** in Apple Developer Portal:
   - "CarPlay Navigation App" beantragen (Apple-Review nötig, 2-4 Wochen)
   - Bis dahin: Development-Mode mit `com.apple.developer.carplay-maps`

3. **CarPlay-Target** in Xcode:
   - File → New → Target → CarPlay App Extension
   - Implementiere `CPMapTemplate` mit Route + nächstem Manöver
   - Lese aus shared App-Group `car_route_snapshot`

4. **App Sandbox** Migration:
   - SharedPreferences zu `UserDefaults(suiteName: "group.com.cruiseconnect.shared")`
   - In Flutter: `flutter_shared_preferences` mit suite-Name

5. **Info.plist** Eintrag:
   ```xml
   <key>UIApplicationSceneManifest</key>
   <dict>
     <key>UISceneConfigurations</key>
     <dict>
       <key>CPTemplateApplicationSceneSessionRoleApplication</key>
       <array>
         <dict>
           <key>UISceneClassName</key>
           <string>CPTemplateApplicationScene</string>
           <key>UISceneDelegateClassName</key>
           <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
         </dict>
       </array>
     </dict>
   </dict>
   ```

**Aufwand**: 1 Woche iOS-Native + 2-4 Wochen Apple-Review.

## Was fehlt für Android Auto

1. **DesktopHead Unit** (DHU) Emulator installieren:
   ```
   sdkmanager "extras;google;auto"
   ```

2. **AndroidManifest.xml** ergänzen:
   ```xml
   <meta-data android:name="com.google.android.gms.car.application"
              android:resource="@xml/automotive_app_desc" />

   <service android:name=".CruiseAutoService"
            android:exported="true">
     <intent-filter>
       <action android:name="androidx.car.app.CarAppService" />
       <category android:name="androidx.car.app.category.NAVIGATION" />
     </intent-filter>
   </service>
   ```

3. **res/xml/automotive_app_desc.xml**:
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <automotiveApp>
     <uses name="template" />
   </automotiveApp>
   ```

4. **CruiseAutoService.kt** in `android/app/src/main/kotlin/...`:
   - Extends `androidx.car.app.CarAppService`
   - `onCreateSession()` → CarPlaySceneController
   - Liest aus shared_preferences (gleicher Mechanismus wie iOS)

5. **Google-Review** für Auto-Listing (Production):
   - DevConsole → Google Play Console → Submit Auto-Tests

**Aufwand**: 3-5 Tage Android-Native + 1-2 Wochen Google-Review.

## MVP-Schritt 1 — was wir jetzt gemacht haben

- `CarRouteBridgeService` publishes already alle nötigen Daten
- Doku für native Setup angelegt
- Foundation-Status-Eintrag in Settings

## Nächste konkrete Schritte (wenn Native-Dev startet)

1. iOS-Person: App-Group + CarPlay-Entitlement beantragen
2. Android-Person: CarAppService Skelett + Manifest-Updates
3. Test mit DesktopHead Unit / CarPlay Simulator (Xcode)
4. Bridge erweitern um:
   - `isCarConnected` getter (wird vom native gesetzt)
   - Voice-Toggle-Sync (CarPlay-Audio-Routing)
