import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'feed_screen.dart';
import 'login_screen.dart';

/// Startup screen: restores the persisted session and probes /api/v1/me.
///
/// - 200 → session alive → feed.
/// - 401 → session expired/dead → login.
/// - Network error → show a retry screen (no cached session to fall back on
///   for the first native milestone).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // AppServices.create() already restored the jar; build services here so
    // a fresh instance is used after retry.
    final services = await AppServices.create();
    if (!mounted) return;

    if (!services.apiClient.hasSession) {
      _goTo(LoginScreen.routeName);
      return;
    }

    try {
      final user = await services.auth.me();
      if (!mounted) return;
      if (user != null) {
        _goTo(FeedScreen.routeName);
      } else {
        await services.apiClient.clearSession();
        _goTo(LoginScreen.routeName);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Can\'t reach Enclavd right now.');
    }
  }

  void _goTo(String route) {
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/default-logo.png', height: 72),
                  const SizedBox(height: 16),
                  const Text('Enclavd',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Loading…',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FaIcon(FontAwesomeIcons.wifi,
                      color: Color(0xFF9CA3AF), size: 56),
                  const SizedBox(height: 16),
                  const Text('Can\'t reach Enclavd right now.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _error = null);
                      _bootstrap();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
      ),
    );
  }
}
