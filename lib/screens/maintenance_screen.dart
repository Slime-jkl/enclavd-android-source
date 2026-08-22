import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/site_config_service.dart';
import '../main.dart';
import 'feed_screen.dart';
import 'login_screen.dart';

/// Maintenance screen — the post-login gate while the site is in
/// maintenance mode and the user's rank is not in the allowed list.
///
/// Mirrors the web's header.php maintenance lockout: reason + estimated end
/// + allowed ranks. "Check again" re-runs the gate (maintenance may have
/// ended); "Sign out" leaves for the login screen.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.auth, this.siteConfig});

  static const routeName = '/maintenance';

  /// Test seams — bypass AppServices when provided.
  final AuthService? auth;
  final SiteConfigService? siteConfig;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  MaintenanceConfig? _config;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<(AuthService, SiteConfigService)> _services() async {
    final services = (widget.auth == null || widget.siteConfig == null)
        ? await AppServices.create()
        : null;
    return (
      widget.auth ?? services!.auth,
      widget.siteConfig ?? services!.siteConfig,
    );
  }

  Future<void> _load() async {
    try {
      final (_, config) = await _services();
      final cfg = await config.fetch();
      if (!mounted) return;
      setState(() => _config = cfg.maintenance);
    } catch (_) {
      // Config unreachable — the screen shows its fallback text.
    }
  }

  Future<void> _checkAgain() async {
    setState(() => _busy = true);
    try {
      final (auth, config) = await _services();
      final user = await auth.me();
      if (!mounted) return;
      if (user == null) {
        await (await AppServices.create()).apiClient.clearSession();
        if (!mounted) return;
        Navigator.of(context)
            .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
        return;
      }
      final gate = await resolveGate(user, config);
      if (!mounted) return;
      if (gate == Gate.feed) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(FeedScreen.routeName, (_) => false);
        return;
      }
      // Still locked out — refresh what's displayed.
      final cfg = await config.fetch();
      if (!mounted) return;
      setState(() {
        _config = cfg.maintenance;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      final (auth, _) = await _services();
      await auth.logout();
    } catch (_) {
      // Local sign-out below regardless.
    }
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final allowed = config?.allowedRanks ?? const <String>[];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FaIcon(FontAwesomeIcons.screwdriverWrench,
                          color: Color(0xFFFCD34D), size: 44),
                      const SizedBox(height: 16),
                      const Text(
                        'Maintenance',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The site is currently undergoing maintenance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 20),
                      _InfoRow(
                        icon: FontAwesomeIcons.userShield,
                        label: 'Allowed ranks',
                        value: allowed.isEmpty ? '—' : allowed.join(', '),
                      ),
                      _InfoRow(
                        icon: FontAwesomeIcons.circleInfo,
                        label: 'Reason',
                        value: config?.reason ?? 'Standard Maintenance.',
                      ),
                      _InfoRow(
                        icon: FontAwesomeIcons.clock,
                        label: 'Estimated end',
                        value: config?.estTime ?? 'Not provided.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Please check back soon or contact an administrator '
                        'if you have questions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _checkAgain,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const FaIcon(FontAwesomeIcons.rotate, size: 14),
                        label: const Text('Check again'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _signOut,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final FaIconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFCD34D);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, size: 14, color: accent.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade300),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
