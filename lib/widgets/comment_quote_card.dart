import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import '../utils/content_spans.dart';

/// Styled quote block for the app's quote-on-reply prefix: a left-accent
/// card with the target's name + the quoted text, above the reply's own
/// content. Mirrors the composer's quote banner so the quoted context
/// reads as a quote everywhere.
class CommentQuoteCard extends StatelessWidget {
  const CommentQuoteCard({super.key, required this.quote});

  final CommentQuote quote;

  @override
  Widget build(BuildContext context) {
    final collapsed = quote.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
            left: BorderSide(color: EnclavdColors.link, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Replying to @${quote.target}',
            style: const TextStyle(
              color: EnclavdColors.link,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            collapsed,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
