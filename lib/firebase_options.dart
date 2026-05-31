// Firebase-Optionen für FCM (nur Push — kein Parallelbackend, vgl. codex.md).
//
// 2026-05-31 (vucko): Manuell aus den bereits vorhandenen Config-Dateien
// erzeugt (android/app/google-services.json + ios/Runner/GoogleService-Info.plist),
// da `flutterfire configure` interaktiv/CLI-Login braucht. Wird ausschließlich
// auf Android + iOS verwendet (Plattform-Guard in main.dart / PushNotificationService).
//
// HINWEIS iOS: iosBundleId ist aktuell der Firebase-Default-Platzhalter
// (com.example.cruiseConnect). Stimmt das nicht mit der echten iOS-Bundle-ID
// überein, muss in der Firebase Console eine iOS-App mit der korrekten Bundle-ID
// angelegt und diese Werte aktualisiert werden (siehe Setup-Doku).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Push/FCM ist auf Web nicht konfiguriert (nur Android/iOS).',
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
    appId: '1:643677007260:ios:f1c5d37b5fca499bb76c59',
    messagingSenderId: '643677007260',
    projectId: 'cruise-connect-a1772',
    storageBucket: 'cruise-connect-a1772.firebasestorage.app',
    iosBundleId: 'com.example.cruiseConnect',
  );
}
