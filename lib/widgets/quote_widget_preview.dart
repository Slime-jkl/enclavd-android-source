import 'package:flutter/material.dart';

/// In-app mirror of the home-screen quote widget. Sizes and colors track
/// applyColors so the settings preview matches the pinned card
class QuoteWidgetPreview extends StatelessWidget {
  const QuoteWidgetPreview({
    super.key,
    required this.text,
    required this.author,
    required this.tags,
    required this.rated,
    required this.showTags,
    required this.light,
  });

  final String? text;
  final String author;
  final List<String> tags;
  final String? rated; // like / dislike / null
  final bool showTags;
  final bool light;

  static const _bgDark = Color(0xFF111827);
  static const _bgLight = Color(0xFFFFFFFF);
  static const _borderLight = Color(0xFFE5E7EB);
  static const _textDark = Color(0xFFE5E7EB);
  static const _textLight = Color(0xFF111827);
  static const _mutedDark = Color(0xFF9CA3AF);
  static const _mutedLight = Color(0xFF6B7280);
  static const _markDark = Color(0xFF3B82F6);
  static const _markLight = Color(0xFF2563EB);
  static const _chipDark = Color(0x1AFFFFFF);
  static const _chipLight = Color(0x14000000);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 360).clamp(0.7, 1.5);
        final muted = light ? _mutedLight : _mutedDark;
        final mark = light ? _markLight : _markDark;
        // Min height mirrors the Widget min 4x2
        final minHeight = constraints.maxWidth * 110 / 250;
        // Height is unbounded inside the settings ListView; size the
        // watermark from the min cell so it stays proportional
        final watermarkBase = constraints.hasBoundedHeight
            ? constraints.biggest.shortestSide
            : minHeight;
        final watermarkSize = (watermarkBase * 0.85).clamp(48.0, 260.0);
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Container(
            decoration: BoxDecoration(
              color: light ? _bgLight : _bgDark,
              borderRadius: BorderRadius.circular(16),
              border: light ? Border.all(color: _borderLight) : null,
            ),
            padding: const EdgeInsets.all(14),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Opacity(
                      opacity: 0.05,
                      child: Image.asset(
                        light
                            ? 'assets/images/quote-widget-logo-dark.png'
                            : 'assets/images/default-logo.png',
                        width: watermarkSize,
                        height: watermarkSize,
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(constraints.maxWidth, scale),
                    if (text == null)
                      Transform.translate(
                        offset: Offset(0, -6 * scale),
                        child: _quoteText(
                            "Open Enclavd to see today's quote", scale),
                      )
                    else ...[
                      Padding(
                        padding: EdgeInsets.only(top: 2 * scale),
                        child: Text(
                          '\u201C',
                          style: TextStyle(
                            color: mark,
                            fontSize: 31 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, -6 * scale),
                        child: _quoteText(text!, scale),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: 6 * scale),
                        child: Text(
                          '- $author',
                          style: TextStyle(
                              color: muted, fontSize: 13 * scale),
                        ),
                      ),
                      if (showTags && tags.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 8 * scale),
                          child: _tags(scale, muted, mark),
                        ),
                      Padding(
                        padding: EdgeInsets.only(top: 10 * scale),
                        child: rated == null
                            ? _actions(scale)
                            : _rated(scale, muted),
                      ),
                    ],
                  ],
                ),
                if (text != null)
                  Positioned(
                    right: 4,
                    bottom: 2,
                    child: Text(
                      '\u201D',
                      style: TextStyle(
                        color: mark,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(double width, double scale) {
    return Row(
      children: [
        if (width >= 260)
          Expanded(
            child: Text(
              'QUOTE OF THE DAY',
              style: TextStyle(
                color: light ? _mutedLight : _mutedDark,
                fontSize: 11 * scale,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.88 * scale,
              ),
            ),
          ),
        Image.asset(
          light
              ? 'assets/images/enclavd-logo-dark.png'
              : 'assets/images/enclavd-logo-white.png',
          height: 16,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _quoteText(String text, double scale) {
    return Text(
      text,
      style: TextStyle(
        color: light ? _textLight : _textDark,
        fontSize: 20 * scale,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _tags(double scale, Color muted, Color mark) {
    final spans = <TextSpan>[];
    for (var i = 0; i < tags.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '  '));
      spans
        ..add(TextSpan(text: '#', style: TextStyle(color: mark)))
        ..add(TextSpan(text: tags[i]));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(color: muted, fontSize: 12 * scale),
    );
  }

  Widget _actions(double scale) {
    return Row(
      children: [
        _chip('\u{1F44D}', scale),
        const SizedBox(width: 8),
        _chip('\u{1F44E}', scale),
      ],
    );
  }

  Widget _chip(String emoji, double scale) {
    return Container(
      width: 44 * scale,
      height: 36 * scale,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: light ? _chipLight : _chipDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(emoji, style: TextStyle(fontSize: 16 * scale)),
    );
  }

  Widget _rated(double scale, Color muted) {
    return Text(
      rated == 'like' ? '\u{1F44D}' : '\u{1F44E}',
      style: TextStyle(
        color: muted,
        fontSize: 18 * scale,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
