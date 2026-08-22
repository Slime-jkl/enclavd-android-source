import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';

/// Legal — the website footer's legal documentation, opened in the
/// browser (the site opens them in a new tab, target="_blank").
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const routeName = '/legal';

  static const _docs = [
    (name: 'Privacy Policy', path: '/privacy_policy', icon: FontAwesomeIcons.shieldHalved),
    (name: 'Cookie Policy', path: '/cookie_policy', icon: FontAwesomeIcons.cookieBite),
    (name: 'Terms of Service', path: '/terms_of_service', icon: FontAwesomeIcons.fileLines),
    (name: 'Community Guidelines', path: '/guidelines', icon: FontAwesomeIcons.peopleGroup),
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
                color: EnclavdColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EnclavdColors.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FaIcon(FontAwesomeIcons.scaleBalanced,
                      color: EnclavdColors.link, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Legal documentation is published on the website. '
                      'Each document opens in your browser.',
                      style: TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Material (not Container): ListTile ink needs a Material.
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, doc) in _docs.indexed) ...[
                    if (i > 0)
                      const Divider(height: 1, color: EnclavdColors.divider),
                    ListTile(
                      leading: FaIcon(doc.icon,
                          color: EnclavdColors.link, size: 17),
                      title: Text(doc.name),
                      trailing: const FaIcon(
                          FontAwesomeIcons.arrowUpRightFromSquare,
                          color: EnclavdColors.textSecondary,
                          size: 14),
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
