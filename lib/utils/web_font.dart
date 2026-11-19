import 'dart:convert';

import 'package:flutter/services.dart';

class _Face {
  const _Face(this.style, this.asset, this.unicodeRange);

  final String style;
  final String asset;
  final String unicodeRange;
}

/// Montserrat (SIL OFL, `assets/fonts/Montserrat/OFL.txt`) bundled as woff2,
/// split into Google's unicode subsets so every script the family covers
/// renders in the app font.
const List<_Face> _faces = [
  _Face(
    'italic',
    'assets/fonts/Montserrat/web/Montserrat-italic-cyrillic-ext.woff2',
    'U+0460-052F, U+1C80-1C8A, U+20B4, U+2DE0-2DFF, U+A640-A69F, U+FE2E-FE2F',
  ),
  _Face(
    'italic',
    'assets/fonts/Montserrat/web/Montserrat-italic-cyrillic.woff2',
    'U+0301, U+0400-045F, U+0490-0491, U+04B0-04B1, U+2116',
  ),
  _Face(
    'italic',
    'assets/fonts/Montserrat/web/Montserrat-italic-vietnamese.woff2',
    'U+0102-0103, U+0110-0111, U+0128-0129, U+0168-0169, U+01A0-01A1, U+01AF-01B0, U+0300-0301, U+0303-0304, U+0308-0309, U+0323, U+0329, U+1EA0-1EF9, U+20AB',
  ),
  _Face(
    'italic',
    'assets/fonts/Montserrat/web/Montserrat-italic-latin-ext.woff2',
    'U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C4, U+2113, U+2C60-2C7F, U+A720-A7FF',
  ),
  _Face(
    'italic',
    'assets/fonts/Montserrat/web/Montserrat-italic-latin.woff2',
    'U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD',
  ),
  _Face(
    'normal',
    'assets/fonts/Montserrat/web/Montserrat-normal-cyrillic-ext.woff2',
    'U+0460-052F, U+1C80-1C8A, U+20B4, U+2DE0-2DFF, U+A640-A69F, U+FE2E-FE2F',
  ),
  _Face(
    'normal',
    'assets/fonts/Montserrat/web/Montserrat-normal-cyrillic.woff2',
    'U+0301, U+0400-045F, U+0490-0491, U+04B0-04B1, U+2116',
  ),
  _Face(
    'normal',
    'assets/fonts/Montserrat/web/Montserrat-normal-vietnamese.woff2',
    'U+0102-0103, U+0110-0111, U+0128-0129, U+0168-0169, U+01A0-01A1, U+01AF-01B0, U+0300-0301, U+0303-0304, U+0308-0309, U+0323, U+0329, U+1EA0-1EF9, U+20AB',
  ),
  _Face(
    'normal',
    'assets/fonts/Montserrat/web/Montserrat-normal-latin-ext.woff2',
    'U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C4, U+2113, U+2C60-2C7F, U+A720-A7FF',
  ),
  _Face(
    'normal',
    'assets/fonts/Montserrat/web/Montserrat-normal-latin.woff2',
    'U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD',
  ),
];

String? _css;

/// `@font-face` rules for Montserrat with the bundled woff2 files inlined.
///
/// The article WebView gets its document through `loadHtmlString`, whose base
/// URL is the API host, so the WebView cannot fetch `assets/...` URLs. Reading
/// the bundled font bytes and inlining them keeps the app font in the page.
///
/// Only the resolved string is cached, not the [Future]: a future created in
/// one zone (e.g. a widget test) never completes for awaiters in another.
Future<String> montserratWebFontCss() async {
  final cached = _css;
  if (cached != null) return cached;
  return _css = await _buildCss();
}

Future<String> _buildCss() async {
  final buffer = StringBuffer();
  for (final face in _faces) {
    final data = await rootBundle.load(face.asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    buffer.write(
      "@font-face{font-family:'Montserrat';font-style:${face.style};"
      'font-weight:100 900;font-display:swap;'
      'src:url(data:font/woff2;base64,${base64Encode(bytes)}) '
      "format('woff2');unicode-range:${face.unicodeRange};}",
    );
  }
  return buffer.toString();
}
