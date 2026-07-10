import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/firebase_options.dart';

/// Top-Level Background-Handler (Pflicht: muss top-level + vm:entry-point sein).
///
/// Wenn die App im Hintergrund/beendet ist, zeigt FCM die `notification`-Payload
/// automatisch im System-Tray an — hier ist also kein Extra-Display nötig.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Bewusst leer: kein Zugriff auf UI/Provider im Background-Isolate.
  // Das System zeigt die Notification selbst. Für reine Data-Messages könnte
  // hier später eine lokale Notification erzeugt werden.
}

/// Echte Handy-Push via FCM.
///
/// 2026-05-31 (vucko): Firebase wird AUSSCHLIESSLICH als Push-Kanal genutzt
/// (kein Parallelbackend, vgl. codex.md). Token → Supabase (user_device_tokens),
/// Versand → Supabase Edge-Function send-push → FCM. Deckt alle Notification-
/// Typen ab (likes, kommentare, reposts, empfehlungen, wetter …).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _firebaseReady = false;

  /// Android-Channel-ID — muss zur channel_id in der Edge-Function (send-push)
  /// passen, sonst landet die Notification im Default-Channel.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'cruise_default',
    'CruiseConnect',
    description: 'Likes, Kommentare, Reposts, Empfehlungen & Wetter',
    importance: Importance.high,
  );

  bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Firebase einmalig initialisieren (idempotent). Wird auch im
  /// Background-Handler in main.dart benötigt.
  Future<void> ensureFirebaseInitialized() async {
    if (_firebaseReady || !_supportedPlatform) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[Push] Firebase init failed: $e');
    }
  }

  /// Nach Login aufrufen: Permission anfragen, Token registrieren, Listener
  /// verkabeln, ggf. Initial-Message (App aus Push gestartet) verarbeiten.
  Future<void> initForUser() async {
    if (!_supportedPlatform) return;
    await ensureFirebaseInitialized();
    if (!_firebaseReady) return;
    if (!_initialized) {
      await _initLocalNotifications();
      _wireListeners();
      _initialized = true;
    }
    await _requestPermission();
    await _registerToken();
    await _handleInitialMessage();
  }

  Future<void> _initLocalNotifications() async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (resp) {
          final payload = resp.payload;
          if (payload != null) _handleTapPayload(payload);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (e) {
      debugPrint('[Push] local-notifications init failed: $e');
    }
  }

  Future<void> _requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      debugPrint('[Push] FCM auth status: ${settings.authorizationStatus}');

      // Android 13+ (API 33): POST_NOTIFICATIONS ist eine LAUFZEIT-Permission.
      // FirebaseMessaging.requestPermission() löst den System-Dialog je nach
      // Plugin-Version NICHT zuverlässig aus — wird er nie gewährt, unterdrückt
      // das OS ALLE Notifications still (genau das Android-Symptom: Token da,
      // Server schickt, aber nichts erscheint). Darum hier explizit über den
      // Local-Notifications-Kanal anfragen.
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImpl = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidImpl?.requestNotificationsPermission();
        debugPrint('[Push] POST_NOTIFICATIONS granted: $granted');
      }

      // Foreground zeigen WIR selbst (lokale Notification + In-App-Toast),
      // damit es auf iOS nicht doppelt erscheint.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } catch (e) {
      debugPrint('[Push] requestPermission failed: $e');
    }
  }

  Future<void> _registerToken() async {
    try {
      // iOS: FirebaseMessaging.getToken() liefert null, solange Apple den
      // APNS-Token noch nicht gesetzt hat (die Registrierung läuft async nach
      // App-Start). Ohne dieses Warten registriert sich das Gerät beim ersten
      // Start gar nicht — der FCM-Token käme erst verzögert über onTokenRefresh.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _awaitApnsToken();
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(token);
      }
    } catch (e) {
      debugPrint('[Push] getToken failed: $e');
    }
  }

  /// iOS: bis zu ~5s auf den APNS-Token warten (Apples Registrierung ist async).
  /// Solange er null ist, gibt [FirebaseMessaging.getToken] auf iOS null zurück.
  Future<void> _awaitApnsToken() async {
    for (var i = 0; i < 10; i++) {
      try {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null && apns.isNotEmpty) return;
      } catch (_) {
        // noch nicht bereit → erneut versuchen
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('[Push] APNS-Token nach Wartezeit noch null — '
        'getToken() könnte null liefern (Registrierung evtl. verzögert)');
  }

  Future<void> _saveToken(String token) async {
    final supa = Supabase.instance.client;
    if (supa.auth.currentUser == null) return;
    try {
      await supa.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('[Push] saveToken failed: $e');
    }
  }

  void _wireListeners() {
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTapData(m.data));
  }

  /// Foreground: FCM zeigt von sich aus nichts → wir rendern eine echte
  /// System-Notification (zusätzlich zum bestehenden In-App-TopToast).
  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    final title =
        n?.title ?? (message.data['title']?.toString()) ?? 'Benachrichtigung';
    final body = n?.body ?? (message.data['body']?.toString()) ?? '';
    if (title.isEmpty && body.isEmpty) return;
    try {
      _local.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('[Push] foreground show failed: $e');
    }
  }

  Future<void> _handleInitialMessage() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleTapData(initial.data);
    } catch (e) {
      debugPrint('[Push] initial message failed: $e');
    }
  }

  void _handleTapPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _handleTapData(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {
      // ignore malformed payload
    }
  }

  /// Deep-Link aus einer getippten Push.
  ///
  /// TODO (vucko): Zentralen Notification-Router andocken (Post/Profil/Gruppe),
  /// analog zum Deep-Link-Handling in main.dart / notifications_page.
  void _handleTapData(Map<String, dynamic> data) {
    if (kDebugMode) {
      debugPrint('[Push] opened from notification: $data');
    }
  }

  /// Bei Logout aufrufen: Token aus Supabase entfernen + FCM-Token löschen,
  /// damit der nächste User auf dem Gerät keine fremden Pushes bekommt.
  Future<void> clearTokenOnLogout() async {
    if (!_supportedPlatform || !_firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final supa = Supabase.instance.client;
      if (token != null && token.isNotEmpty) {
        await supa.from('user_device_tokens').delete().eq('token', token);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[Push] clearToken failed: $e');
    }
  }
}
