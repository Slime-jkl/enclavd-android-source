import 'api_client.dart';

/// One selectable mood on the 1-5 scale.
///
/// Mirrors config/diary.php DIARY_MOODS — the site's single source of
/// truth for the mood set. The API always returns mood_emoji/mood_label
/// on every entry, so this list is only needed where the app builds the
/// picker and the 30-day strip itself. Keep it in step with the config
/// (changing the set is a product decision; old entries re-map by their
/// 1-5 key).
class DiaryMood {
  const DiaryMood(this.value, this.emoji, this.label, this.hint);

  final int value; // 1 (worst) → 5 (best)
  final String emoji;
  final String label;
  final String hint;
}

const List<DiaryMood> kDiaryMoods = [
  DiaryMood(1, '😞', 'Rough', 'The day got the better of you.'),
  DiaryMood(2, '😐', 'Flat', 'Went through the motions.'),
  DiaryMood(3, '😌', 'Steady', 'Held the line.'),
  DiaryMood(4, '😤', 'Grinding', 'Locked in and pushing.'),
  DiaryMood(5, '🔥', 'Unstoppable', 'Everything clicked.'),
];

/// One locked diary entry (the API's entry shape). One per user per day;
/// once locked it never changes (no edits, no take-backs).
class DiaryEntry {
  const DiaryEntry({
    required this.date,
    required this.mood,
    required this.moodEmoji,
    required this.moodLabel,
    required this.win,
    required this.avoided,
    required this.tomorrow,
    required this.thought,
    required this.createdAt,
    required this.updatedAt,
  });

  final String date; // 'Y-m-d' (DB clock, same boundary as the daily quote)
  final int mood; // 1-5
  final String moodEmoji;
  final String moodLabel;
  final String win; // required: one small win
  final String avoided; // optional
  final String tomorrow; // optional
  final String thought; // optional
  final String createdAt;
  final String updatedAt;

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
        date: json['date'] as String? ?? '',
        mood: (json['mood'] as num?)?.toInt() ?? 0,
        moodEmoji: json['mood_emoji'] as String? ?? '❓',
        moodLabel: json['mood_label'] as String? ?? 'Unknown',
        win: json['win'] as String? ?? '',
        avoided: json['avoided'] as String? ?? '',
        tomorrow: json['tomorrow'] as String? ?? '',
        thought: json['thought'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

/// Streak + volume stats backing the stat cards and the 30-day mood strip.
class DiaryStats {
  const DiaryStats({
    required this.streak,
    required this.longestStreak,
    required this.totalEntries,
    required this.moods30d,
  });

  /// Consecutive days ending today; if today isn't logged yet the run
  /// counts from yesterday so it stays alive until midnight.
  final int streak;
  final int longestStreak;
  final int totalEntries;

  /// Per-mood counts over the last 30 days, keyed 1-5 (zero-filled).
  final Map<int, int> moods30d;

  factory DiaryStats.fromJson(Map<String, dynamic> json) {
    final raw = json['moods_30d'];
    final moods = <int, int>{};
    if (raw is Map<String, dynamic>) {
      for (final e in raw.entries) {
        final key = int.tryParse(e.key);
        if (key != null) moods[key] = (e.value as num?)?.toInt() ?? 0;
      }
    }
    return DiaryStats(
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
      totalEntries: (json['total_entries'] as num?)?.toInt() ?? 0,
      moods30d: moods,
    );
  }
}

/// The full GET response: today's entry (or null), the lock state, stats
/// and the recent-entries list.
class DiarySnapshot {
  const DiarySnapshot({
    required this.date,
    required this.entry,
    required this.locked,
    required this.stats,
    required this.recent,
  });

  final String date; // today, 'Y-m-d' (DB clock)
  final DiaryEntry? entry; // null until today is locked in
  final bool locked;
  final DiaryStats stats;
  final List<DiaryEntry> recent; // newest first

  factory DiarySnapshot.fromJson(Map<String, dynamic> json) {
    final rawEntry = json['entry'];
    return DiarySnapshot(
      date: json['date'] as String? ?? '',
      entry: rawEntry is Map<String, dynamic>
          ? DiaryEntry.fromJson(rawEntry)
          : null,
      locked: json['locked'] as bool? ?? false,
      stats: DiaryStats.fromJson(
          json['stats'] as Map<String, dynamic>? ?? const {}),
      recent: [
        for (final e in json['recent'] as List? ?? const [])
          if (e is Map<String, dynamic>) DiaryEntry.fromJson(e),
      ],
    );
  }
}

/// The prestige math returned by a successful save: points for the entry,
/// minus points for every day skipped since the previous entry.
class DiaryPrestige {
  const DiaryPrestige({
    required this.awarded,
    required this.penalty,
    required this.missedDays,
    required this.net,
  });

  final int awarded;
  final int penalty;
  final int missedDays;
  final int net;

  factory DiaryPrestige.fromJson(Map<String, dynamic> json) => DiaryPrestige(
        awarded: (json['awarded'] as num?)?.toInt() ?? 0,
        penalty: (json['penalty'] as num?)?.toInt() ?? 0,
        missedDays: (json['missed_days'] as num?)?.toInt() ?? 0,
        net: (json['net'] as num?)?.toInt() ?? 0,
      );
}

/// A save's outcome: today's (new) entry, fresh stats and the prestige
/// breakdown. A second save the same day is an idempotent no-op — the
/// entry comes back untouched and the prestige math is all zeros.
class DiarySaveResult {
  const DiarySaveResult({
    required this.date,
    required this.entry,
    required this.locked,
    required this.stats,
    required this.prestige,
  });

  final String date;
  final DiaryEntry entry;
  final bool locked;
  final DiaryStats stats;
  final DiaryPrestige prestige;

  factory DiarySaveResult.fromJson(Map<String, dynamic> json) {
    final rawEntry = json['entry'];
    return DiarySaveResult(
      date: json['date'] as String? ?? '',
      entry: rawEntry is Map<String, dynamic>
          ? DiaryEntry.fromJson(rawEntry)
          : DiaryEntry.fromJson(const {}),
      locked: json['locked'] as bool? ?? false,
      stats: DiaryStats.fromJson(
          json['stats'] as Map<String, dynamic>? ?? const {}),
      prestige: DiaryPrestige.fromJson(
          json['prestige'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

/// The Diary feature over api/v1/diary (POST-only — even the read rides
/// JSON + CSRF, exactly like the site's diary.js).
///
/// Contracts (verified against api/v1/diary.php):
///   POST {action:'get'}  → {success, date, entry|null, locked, stats,
///                          recent:[...]}
///   POST {action:'save', mood:1-5, win, avoided?, tomorrow?, thought?}
///                        → {success, date, entry, locked, stats,
///                           prestige:{awarded, penalty, missed_days, net}}
///   400 {error} for validation ("Pick a mood for today.", "Name one
///   small win. Even a tiny one counts.", length caps 500/1000) — shown
///   verbatim per the app's user-facing error contract.
class DiaryService {
  DiaryService(this._api);

  final ApiClient _api;

  /// Today's entry (or null) + stats + recent. Read-only after auth.
  Future<DiarySnapshot> fetchToday() async {
    final json = await _api.postJson('/api/v1/diary', {'action': 'get'});
    return DiarySnapshot.fromJson(json);
  }

  /// Locks in today's entry. One per user per day; the server treats a
  /// second save the same day as an idempotent no-op.
  Future<DiarySaveResult> saveToday({
    required int mood,
    required String win,
    String avoided = '',
    String tomorrow = '',
    String thought = '',
  }) async {
    final json = await _api.postJson('/api/v1/diary', {
      'action': 'save',
      'mood': mood,
      'win': win,
      'avoided': avoided,
      'tomorrow': tomorrow,
      'thought': thought,
    });
    return DiarySaveResult.fromJson(json);
  }
}
