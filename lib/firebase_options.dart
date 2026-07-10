// Firebase-Optionen für FCM (nur Push — kein Parallelbackend, vgl. codex.md).
//
// 2026-05-31 (vucko): Manuell aus den bereits vorhandenen Config-Dateien
// erzeugt (android/app/google-services.json + ios/Runner/GoogleService-Info.plist),
// da `flutterfire configure` interaktiv/CLI-Login braucht. Wird ausschließlich
// auf Android + iOS verwendet (Plattform-Guard in main.dart / PushNotificationService).
//
// 2026-06-17 (vucko): iOS-App auf die ECHTE Bundle-ID umgestellt
// (com.vucko.cruiserconnect, GOOGLE_APP_ID …ios:805b15ff…). Vorher stand hier
// noch der Firebase-Default-Platzhalter com.example.cruiseConnect — dadurch
// registrierte sich das Gerät unter der falschen iOS-App und APNs wies jeden
// Push wegen falschem apns-topic ab. Werte synchron zur neuen
// ios/Runner/GoogleService-Info.plist.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Push/FCM ist auf Web nicht konfiguriert.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Push/FCM ist für $defaultTargetPlatform nicht konfiguriert.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBEanuPYPcaiTHwZZGvbb5qDgoTTHajMP4',
    appId: '1:643677007260:android:c761b830cf08b63fb76c59',
    messagingSenderId: '643677007260',
    projectId: 'cruise-connect-a1772',
    storageBucket: 'cruise-connect-a1772.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBnG4JDcppSoWYZd35Wdvf8ESGSeB18vJs',
    appId: '1:643677007260:ios:805b15ff4dde7131b76c59',
    messagingSenderId: '643677007260',
    projectId: 'cruise-connect-a1772',
    storageBucket: 'cruise-connect-a1772.firebasestorage.app',
    iosBundleId: 'com.vucko.cruiserconnect',
  );
}
