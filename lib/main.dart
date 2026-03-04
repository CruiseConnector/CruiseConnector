import 'package:cruise_connect/presentation/pages/auth_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';

const String _mapboxPublicToken =
  'pk.eyJ1IjoibHVjd3F6IiwiYSI6ImNtbHdnMXFpdjBjZTAzZXF3NDgyYmZ3c2oifQ.upeLKXUnY5z6Pe0JiuznEQ';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(_mapboxPublicToken);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: 'https://tlcfaxvvqzobmzwvfnvb.supabase.co',
    anonKey: 'sb_publishable_rq42MGGjHHy8IApa4dR3Nw_UCEqkZ8M',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cruise Connect',
      home: AuthPage(),
    );
  }
}


