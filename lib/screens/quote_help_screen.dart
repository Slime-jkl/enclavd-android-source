import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme/enclavd_theme.dart';

/// How daily quotes work — TLDR. Short, direct, no filler: one quote a
/// day, rate it with 👍/👎, the pick learns your taste. Each feature gets
/// a single compact card.
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
            _Tldr(
              icon: FontAwesomeIcons.quoteLeft,
              title: 'One quote a day',
              body:
                  'A new quote every morning — on the widget, the '
                  'notification, and the website. No repeats until you\u2019ve '
                  'seen them all.',
            ),
            SizedBox(height: 8),
            _Tldr(
              icon: FontAwesomeIcons.thumbsUp,
              title: 'Rate it',
              body:
                  'Tap 👍 or 👎. One vote per quote. The buttons disappear '
                  'after you vote, so you always know it counted.',
            ),
            SizedBox(height: 8),
            _Tldr(
              icon: FontAwesomeIcons.tags,
              title: 'It learns',
              body:
                  'Every quote has themes. Liking one pushes its themes up; '
                  'disliking pushes them down. Rate a few and the picks get '
                  'smarter.',
            ),
            SizedBox(height: 8),
            _Tldr(
              icon: FontAwesomeIcons.houseChimney,
              title: 'The widget',
              body:
                  'Add it from your launcher. Tap the card to open these '
                  'settings. Resize it — the quote grows with it.',
            ),
            SizedBox(height: 8),
            _Tldr(
              icon: FontAwesomeIcons.bell,
              title: 'The notification',
              body:
                  'Once a day, random time between 6 am and 8 pm. Skipped '
                  'while the widget is on your home screen.',
            ),
            SizedBox(height: 8),
            _Tldr(
              icon: FontAwesomeIcons.arrowRotateRight,
              title: 'Turn it off',
              body:
                  'Master switch at the top of the Quote of the day screen.',
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// One TLDR card: icon + heading + one or two short lines.
class _Tldr extends StatelessWidget {
  const _Tldr({
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, color: EnclavdColors.link, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                      fontSize: 13, height: 1.4, color: EnclavdColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
