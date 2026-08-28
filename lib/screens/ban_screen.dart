import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../main.dart';
import 'login_screen.dart';

class BanScreen extends StatefulWidget {
  const BanScreen({super.key, this.auth});

  static const routeName = '/ban';

  /// Test seam: bypasses AppServices when provided.
  final AuthService? auth;

  @override
  State<BanScreen> createState() => _BanScreenState();
}

class _BanScreenState extends State<BanScreen> {
  String _reason = 'No reason provided.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<AuthService> _services() async =>
      widget.auth ?? (await AppServices.create()).auth;

  Future<void> _load() async {
    try {
      final user = await (await _services()).me();
      if (!mounted) return;
      final reason = user?.blockReason ?? '';
      if (reason.isNotEmpty) setState(() => _reason = reason);
    } catch (_) {
      // Keep the fallback reason.
    }
  }

  Future<void> _exit() async {
    setState(() => _busy = true);
    await (await _services()).logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFF87171);
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
                      const Center(
                        child: FaIcon(FontAwesomeIcons.ban,
                            color: Color(0xFFF87171), size: 44),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Your account has been banned',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your account has been banned for the following reason:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF000000).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _reason,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'If you think this is an error, or wish to appeal, '
                        'please contact us at contact@enclavd.com',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _exit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: danger,
                          side: BorderSide(
                              color: danger.withValues(alpha: 0.6)),
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFFF87171)),
                              )
                            : const FaIcon(FontAwesomeIcons.arrowRightFromBracket,
                                size: 14),
                        label: const Text('Exit'),
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
