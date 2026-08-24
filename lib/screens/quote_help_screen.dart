import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme/enclavd_theme.dart';

/// How daily quotes work — the pick, the tags, the widget and the buttons.
/// A plain-language page (no internals) reachable from App settings.
class QuoteHelpScreen extends StatelessWidget {
  const QuoteHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How daily quotes work')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            _Section(
              icon: FontAwesomeIcons.quoteLeft,
              title: 'One quote every day',
              body:
                  'Every day you get one quote, chosen for you. It appears '
                  'on your home screen (the widget), as a notification, and '
                  'on the website — a fresh one every day, and you will '
                  'never see the same one twice until the whole collection '
                  'has been shown.',
            ),
            SizedBox(height: 10),
            _Section(
              icon: FontAwesomeIcons.tags,
              title: 'The tags',
              body:
                  'Every quote carries 1–3 themes — wisdom, courage, '
                  'happiness, strategy and more. Your likes and dislikes '
                  'build a personal score for each theme: liking a quote '
                  'pushes its themes up, disliking one pushes them down. '
                  'The better a theme scores for you, the more often quotes '
                  'about it get picked.',
            ),
            SizedBox(height: 10),
            _Section(
              icon: FontAwesomeIcons.thumbsUp,
              title: 'Like and dislike',
              body:
                  'Rate the quote with the 👍/👎 buttons — on the widget '
                  'without even opening the app, or on the website. Each '
                  'quote can be rated once, and every rating nudges '
                  'tomorrow\u2019s pick toward (or away from) its themes. '
                  'Rate a few and the daily quote starts feeling like it '
                  'was chosen for you.',
            ),
            SizedBox(height: 10),
            _Section(
              icon: FontAwesomeIcons.solidSun,
              title: 'The widget',
              body:
                  'Add \u201CEnclavd \u2014 Daily quote\u201D from your '
                  'launcher\u2019s widget picker. It shows today\u2019s '
                  'quote, resizes freely, and its text scales with the '
                  'size. Tap the card to open the app. In App settings you '
                  'can show or hide the tags and the logo, or switch to a '
                  'light card.',
            ),
            SizedBox(height: 10),
            _Section(
              icon: FontAwesomeIcons.bell,
              title: 'The notification',
              body:
                  'Once a day, at a random time between 6 am and 8 pm your '
                  'time, a notification brings the quote. While the widget '
                  'is on your home screen the notification is skipped — '
                  'the quote is already in front of you. You can turn the '
                  'whole feature off in App settings.',
            ),
            SizedBox(height: 10),
            _Section(
              icon: FontAwesomeIcons.arrowRotateRight,
              title: 'A new pick every day',
              body:
                  'The pick renews at midnight. No preferences yet? The '
                  'first quotes are a random sample — each rating makes the '
                  'next one smarter. After 1,600+ quotes you will have seen '
                  'them all, and the cycle restarts.',
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// One explainer card: icon + heading + plain-language body.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.body,
  });

  final FaIconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, color: EnclavdColors.link, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
