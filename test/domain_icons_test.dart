import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:enclavd/api/domains_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/utils/domain_icons.dart';

void main() {
  group('domainIconFor', () {
    test('renders a server codepoint (alias name not in the FA7 map)', () {
      // fa-arrow-alt-circle-up: FA5 alias, FA7 dropped the name but keeps
      // the glyph at 0xF35B (circle-up). The server sends the codepoint.
      final icon = domainIconFor('fa-arrow-alt-circle-up', codePoint: 0xF35B);
      expect(icon.codePoint, 0xF35B);
      expect(icon.fontFamily, 'FontAwesomeSolid');
    });

    test('falls back to the name map when no codepoint is sent', () {
      final icon = domainIconFor('fa-lightbulb');
      expect(icon.codePoint, isNot(FontAwesomeIcons.globe.codePoint));
    });

    test('maps FA7-dropped codepoints to a nearest equivalent', () {
      expect(domainIconFor('fa-user-large').codePoint,
          FontAwesomeIcons.user.codePoint);
      expect(domainIconFor('fa-headphones-alt').codePoint,
          FontAwesomeIcons.headphones.codePoint);
      expect(domainIconFor('fa-handshake-simple-slash').codePoint,
          FontAwesomeIcons.handshakeSlash.codePoint);
    });

    test('globe is the final fallback', () {
      expect(domainIconFor('fa-definitely-not-real').codePoint,
          FontAwesomeIcons.globe.codePoint);
      expect(domainIconFor('fa-definitely-not-real', codePoint: 0).codePoint,
          FontAwesomeIcons.globe.codePoint);
    });
  });

  group('domain model parses codepoints', () {
    test('DomainCategory reads icon_code', () {
      final c = DomainCategory.fromJson(const {
        'id': 1,
        'name': 'test',
        'slug': 'test',
        'display_order': 0,
        'icon': 'fa-arrow-alt-circle-up',
        'icon_code': 0xF35B,
        'color': '#60a5fa',
        'post_count': 0,
      });
      expect(c.iconCode, 0xF35B);
    });

    test('DomainThread reads domain_icon_code', () {
      final t = DomainThread.fromJson(const {
        'id': 1,
        'content': 'x',
        'created_at': '2026-01-01 00:00:00',
        'domain_slug': 'test',
        'domain_name': 'test',
        'domain_icon': 'fa-angry',
        'domain_icon_code': 0xF556,
      });
      expect(t.domainIconCode, 0xF556);
      expect(domainIconFor(t.domainIcon, codePoint: t.domainIconCode).codePoint,
          0xF556);
    });
  });

  group('accentGlyph (server hex vs theme)', () {
    // Server accents are tuned for the dark site; light glyphs must
    // darken pale grays or they wash out on light cards.
    const gray400 = Color(0xFF9CA3AF); // the invisible-on-light case

    test('dark passes server colors through untouched', () {
      expect(EnclavdPalette.dark.accentGlyph(gray400), gray400);
      expect(EnclavdPalette.dark.isLight, isFalse);
    });

    test('light washes pale grays toward the ink', () {
      final flipped = EnclavdPalette.light.accentGlyph(gray400);
      expect(flipped.computeLuminance(), lessThan(gray400.computeLuminance()));
      expect(EnclavdPalette.light.isLight, isTrue);
    });

    test('light leaves already-deep accents alone', () {
      const deep = Color(0xFF4B5563); // gray-600
      expect(EnclavdPalette.light.accentGlyph(deep), deep);
      expect(
          EnclavdPalette.light
              .accentGlyph(const Color(0xFF7E22CE)), // purple-700
          const Color(0xFF7E22CE));
    });
  });
}
