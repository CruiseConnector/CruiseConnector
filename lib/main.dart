import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/application/providers/auth_provider.dart';
import 'package:cruise_connect/application/providers/community_provider.dart';
import 'package:cruise_connect/application/providers/route_provider.dart';
import 'package:cruise_connect/application/providers/saved_routes_provider.dart';
import 'package:cruise_connect/core/constants.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/auth_page.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  runZonedGuarded(() => runApp(const MyApp()), (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);
    } catch (e) {
      debugPrint('[DeepLink] initial link Fehler: $e');
    }
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (e) => debugPrint('[DeepLink] stream Fehler: $e'),
    );
  }

  Future<void> _handleDeepLink(Uri uri) async {
    debugPrint('[DeepLink] $uri');
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'post') {
      final postId = segments[1];
      await Future.delayed(const Duration(milliseconds: 400));
      final post = await SocialService.getPostById(postId);
      final nav = rootNavigatorKey.currentState;
      if (post == null || nav == null) return;
      final profile = post['profiles'] as Map<String, dynamic>?;
      final name =
          profile?['username'] ?? profile?['email']?.split('@')[0] ?? 'User';
      final handle = '@${profile?['email']?.split('@')[0] ?? 'user'}';
      nav.push(
        MaterialPageRoute(
          builder: (_) => PostDetailPage(
            postId: postId,
            name: name as String,
            handle: handle,
            content: (post['content'] ?? '') as String,
            time: '',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RouteProvider()),
        ChangeNotifierProvider(create: (_) => CommunityProvider()),
        ChangeNotifierProvider(create: (_) => SavedRoutesProvider()),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'CruiseConnect',
        home: const AuthPage(),
      ),
    );
  }
}
