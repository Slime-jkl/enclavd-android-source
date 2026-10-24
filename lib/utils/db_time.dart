// Shared DB time helpers
// every client-side datetime on a bare db string goes through here.

DateTime? parseDbTime(String input) {
  if (input.isEmpty) return null;
  final s = input.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$').hasMatch(s)) {
    return DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z')?.toUtc();
  }
  return DateTime.tryParse(s)?.toUtc();
}

/// Port of format_date(): now / Xm / Xh / Xd / Xmo / Xy.
String relativeTime(String dbDateTime) {
  final parsed = parseDbTime(dbDateTime);
  if (parsed == null) {
    final s = dbDateTime.trim();
    if (RegExp(r'^now$|^\d+[ymhd]$').hasMatch(s)) return s;
    return '';
  }
  final now = DateTime.now();
  final diff = now.difference(parsed);
  if (diff.inSeconds < 0) return 'now';
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  // Approximate months as 30 days
  final days = diff.inDays;
  if (days < 30) return '${days}d';
  if (days < 365) return '${days ~/ 30}m';
  return '${days ~/ 365}y';
}

/// Absolute stamp for the post drawer: "22 Oct 2026, 07:16" in the device's
/// zone. DB times are UTC, same as everywhere else in this file.
String absoluteTime(String dbDateTime) {
  final parsed = parseDbTime(dbDateTime);
  if (parsed == null) return dbDateTime.trim();
  final local = parsed.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
}
