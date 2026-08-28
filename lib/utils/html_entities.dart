/// HTML entity decoding for post content.
///
/// The backend stores post text through `htmlspecialchars($s, ENT_QUOTES)`
/// (see api/v1/posts.php), so apostrophes arrive in JSON as `&#039;`,
/// ampersands as `&amp;`, etc. The site renders that content as HTML and
/// the BROWSER decodes the entities; a native Text widget does not, so the
/// app must decode exactly once, single pass like the browser's HTML
/// parser - never twice: `&amp;lt;` must become `&lt;`, not `<`.
library;

/// Decodes the entities the backend can produce, in one pass: the named
/// set emitted by htmlspecialchars(ENT_QUOTES) plus the common
/// punctuation/nbsp forms and arbitrary numeric entities (decimal and
/// hex). Unknown named entities are left untouched; invalid code points
/// (surrogates, out-of-range) stay as their original text.
String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;

  final buffer = StringBuffer();
  var index = 0;
  while (index < input.length) {
    final amp = input.indexOf('&', index);
    if (amp == -1) {
      buffer.write(input.substring(index));
      break;
    }
    buffer.write(input.substring(index, amp));

    final semi = input.indexOf(';', amp + 1);
    if (semi == -1) {
      // No closing ';': not an entity, keep the raw '&'.
      buffer.write(input.substring(amp));
      break;
    }

    final entity = input.substring(amp + 1, semi);
    final decoded = _decodeOne(entity);
    if (decoded == null) {
      buffer.write('&'); // unknown/unparseable: keep the leading '&'
      index = amp + 1;
      continue;
    }
    buffer.write(decoded);
    index = semi + 1;
  }
  return buffer.toString();
}

/// Decode one entity body (without the `&`/`;`); null when unrecognized
/// (the caller then keeps the raw text).
String? _decodeOne(String entity) {
  if (entity.startsWith('#x') || entity.startsWith('#X')) {
    final code = int.tryParse(entity.substring(2), radix: 16);
    return code != null ? _fromCodePoint(code) : null;
  }
  if (entity.startsWith('#')) {
    final code = int.tryParse(entity.substring(1));
    return code != null ? _fromCodePoint(code) : null;
  }
  return _named[entity];
}

/// Code point -> string, guarding surrogates and out-of-range values.
String? _fromCodePoint(int code) {
  if (code <= 0 || code > 0x10FFFF) return null;
  if (code >= 0xD800 && code <= 0xDFFF) return null;
  return String.fromCharCode(code);
}

/// The named entities the backend (htmlspecialchars ENT_QUOTES) emits,
/// plus the handful of HTML punctuation forms that legitimately end up
/// stored.
const Map<String, String> _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  // htmlspecialchars emits &#039; for apostrophes, but some legacy content
  // used the named form; both must decode to the same char.
  'nbsp': '\u00A0',
  'hellip': '\u2026',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'rsquo': '\u2019',
  'lsquo': '\u2018',
  'rdquo': '\u201D',
  'ldquo': '\u201C',
  'bull': '\u2022',
  'middot': '\u00B7',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'eacute': '\u00E9',
  'egrave': '\u00E8',
  'agrave': '\u00E0',
  'ccedil': '\u00E7',
  'uuml': '\u00FC',
  'ouml': '\u00F6',
  'auml': '\u00E4',
  'szlig': '\u00DF',
};
