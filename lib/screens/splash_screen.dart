import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart';
import '../main.dart';
import '../widgets/error_view.dart';
import 'ban_screen.dart';
import 'feed_screen.dart';
import 'login_screen.dart';
import 'maintenance_screen.dart';
import 'quote_settings_screen.dart';

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
        // Post-login gate: banned -> ban screen, maintenance without an
        // allowed rank -> maintenance screen, otherwise the feed.
        switch (await resolveGate(user, services.siteConfig)) {
          case Gate.ban:
            _goTo(BanScreen.routeName);
            return;
          case Gate.maintenance:
            _goTo(MaintenanceScreen.routeName);
            return;
          case Gate.feed:
            _goTo(FeedScreen.routeName);
            await _maybeOpenQuoteSettings();
            return;
        }
      } else {
        await services.apiClient.clearSession();
        _goTo(LoginScreen.routeName);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorText(e));
    }
  }

  Future<void> _maybeOpenQuoteSettings() async {
    var wantsQuote = QuoteDeepLink.pending;
    if (!wantsQuote) {
      try {
        final launch = await HomeWidget.initiallyLaunchedFromHomeWidget();
        wantsQuote =
            launch != null && launch.toString().contains('quote-settings');
      } catch (_) {
        // home_widget unavailable (tests): nothing to resolve.
      }
    }
    if (!wantsQuote) return;
    QuoteDeepLink.consume();
    final nav = navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      nav.push(MaterialPageRoute<void>(
          builder: (_) => const QuoteSettingsScreen()));
    }
  }

  void _goTo(String route) {
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _error == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/default-logo.png', height: 72),
                  const SizedBox(height: 16),
                  const Text('Enclavd',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Loading...',
                      style: TextStyle(color: Color(0xFF9CA3AF))),
                ],
              ),
            )
          : ErrorView(
              message: _error!,
              onRetry: () {
                setState(() => _error = null);
                _bootstrap();
              },
            ),
    );
  }
}
