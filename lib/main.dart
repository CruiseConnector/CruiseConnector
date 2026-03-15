import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/presentation/pages/auth_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MapboxOptions.setAccessToken(AppConstants.mapboxPublicToken);

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      // Bekannter Mapbox-SDK Bug: view wird disposed bevor SDK es erwartet
      if (error is PlatformException && error.code == 'unknown_view') return;
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CruiseConnect',
      home: AuthPage(),
    );
  }
}
