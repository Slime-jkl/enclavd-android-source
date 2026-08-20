import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'api/auth_service.dart';
import 'api/feed_service.dart';
import 'api/social_service.dart';
import 'config/app_config.dart';
import 'screens/feed_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/enclavd_theme.dart';

/// Enclavd — native app (Flutter).
///
/// Cross-platform from day one (android/ + ios/ runners committed), but only
/// the Android APK is built by CI for now. All networking goes through the
/// api/v1 JSON endpoints + the legacy auth flows, exactly like the website.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EnclavdApp());
}

/// Simple service container — no DI framework, constructor injection only.
/// Everything the screens need is created here once and passed down.
class AppServices {
  AppServices._(this.apiClient, this.auth, this.feed, this.social);

  final ApiClient apiClient;
  final AuthService auth;
  final FeedService feed;
  final SocialService social;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    final store = PrefsSessionStore(prefs);
    final api = ApiClient(store: store);
    await api.restoreSession();
    final auth = AuthService(api, apiBaseUrl: AppConfig.apiBaseUrl);
    return AppServices._(api, auth, FeedService(api), SocialService(api));
  }
}

class EnclavdApp extends StatelessWidget {
  const EnclavdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enclavd',
      debugShowCheckedModeBanner: false,
      theme: buildEnclavdTheme(),
      home: const SplashScreen(),
      routes: {
        LoginScreen.routeName: (_) => const LoginScreen(),
        RegisterScreen.routeName: (_) => const RegisterScreen(),
        FeedScreen.routeName: (_) => const FeedScreen(),
      },
    );
  }
}
