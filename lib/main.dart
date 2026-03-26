import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/presentation/pages/auth_page.dart';
import 'package:cruise_connect/application/providers/auth_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // flutter_map benötigt keinen globalen Token-Setup —
  // der Mapbox-Token wird direkt in der TileLayer-URL übergeben.
  // AppConstants.mapboxPublicToken wird in cruise_mode_page.dart genutzt.

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Auth-State: Login / Logout überall verfügbar
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // Routen-State: aktive Route, Generierungs-Status
        ChangeNotifierProvider(create: (_) => RouteProvider()),
        // Community-Posts und Likes zentral (überall synchron)
        ChangeNotifierProvider(create: (_) => CommunityProvider()),
        // Gespeicherte Routen mit Offline-Cache
        ChangeNotifierProvider(create: (_) => SavedRoutesProvider()),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CruiseConnect',
        home: AuthPage(),
      ),
    );
  }
}
