import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';

/// The website footer's legal documentation, opened in the browser.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const routeName = '/legal';

  static const _docs = [
    (
      name: 'Privacy Policy',
      path: '/privacy_policy',
      icon: FontAwesomeIcons.shieldHalved
    ),
    (
      name: 'Cookie Policy',
      path: '/cookie_policy',
      icon: FontAwesomeIcons.cookieBite
    ),
    (
      name: 'Terms of Service',
      path: '/terms_of_service',
      icon: FontAwesomeIcons.fileLines
    ),
    (
      name: 'Community Guidelines',
      path: '/guidelines',
      icon: FontAwesomeIcons.peopleGroup
    ),
    (name: 'CSAE', path: '/csae', icon: FontAwesomeIcons.scaleBalanced),
    (name: 'F.A.Q', path: '/faq', icon: FontAwesomeIcons.circleQuestion),
  ];

  Future<void> _open(BuildContext context, String path) async {
    try {
      await launchUrl(
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Defensive, like every other launcher call.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.enclavd.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.enclavd.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FaIcon(FontAwesomeIcons.scaleBalanced,
                      color: context.enclavd.link, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Legal documentation is published on the website. '
                      'Each document opens in your browser.',
                      style: TextStyle(
                          color: context.enclavd.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Material (not Container): ListTile ink needs a Material.
            Material(
              color: context.enclavd.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.enclavd.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, doc) in _docs.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, color: context.enclavd.divider),
                    ListTile(
                      leading: FaIcon(doc.icon,
                          color: context.enclavd.link, size: 17),
                      title: Text(doc.name),
                      trailing: FaIcon(FontAwesomeIcons.arrowUpRightFromSquare,
                          color: context.enclavd.textSecondary, size: 14),
                      onTap: () => _open(context, doc.path),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
