import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Pluggable core of background notifications: one [NotificationSource]
/// per notification domain; the runner, dedupe and plumbing are generic
/// (implement a source + one line in `backgroundSources()`). Every source
/// is read-only (GET only) - marking things read stays the user-facing
/// app's job, as the worker's session has no CSRF.
abstract class NotificationSource {
  /// Short namespace for this source; every dedupe key starts with it
  /// ('message', later 'post', ...) so sources never collide.
  String get id;

  /// Check for new things to notify about. Must swallow its own errors
  /// (dead session or transient failure -> return []) - a broken source
  /// must never crash the worker or block the others; the next tick
  /// retries.
  Future<List<NotificationCandidate>> check(SourceContext context);
}

/// Which renderer a candidate needs: message = conversation channel +
/// drawer-reply action; social = plain notifications channel (no reply).
enum CandidateKind { message, social }

/// Everything needed to show one notification. The dedupe identity is
/// [key], NOT the notification id - a conversation's id stays fixed so
/// Android replaces the older notification instead of stacking.
class NotificationCandidate {
  const NotificationCandidate({
    required this.key,
    required this.notificationId,
    required this.title,
    required this.body,
    this.payload,
    this.kind = CandidateKind.message,
    this.avatarPath,
  });

  /// Dedupe identity, e.g. 'message:5:102' or 'post:post-like:12:88'.
  final String key;

  /// Android notification id - stable per grouping (per conversation),
  /// so a new item replaces the previous notification of that group.
  final int notificationId;

  final String title;
  final String body;

  /// App payload on tap/action (e.g. 'c:5' for a drawer reply).
  final String? payload;

  /// Which channel/renderer this candidate is shown through.
  final CandidateKind kind;

  /// Root-relative sender avatar for message bubbles (MessagingStyle
  /// person icons must be local files - resolved+cached at show time).
  final String? avatarPath;
}

/// What every source gets: a session-bearing client (built fresh per
/// worker run; the live path passes its own) and prefs.
class SourceContext {
  SourceContext({required this.api, required this.prefs});

  final ApiClient api;
  final SharedPreferences prefs;
}

/// Cross-path dedupe, persisted to prefs: a bounded FIFO set of seen
/// keys. BOTH the live path (SSE ping) and the background worker
/// (15-min WorkManager) write here, so a message never double-notifies
/// when both fire. A lost write in a race can only cause a duplicate,
/// never a missed one.
class NotifiedTracker {
  NotifiedTracker(this._prefs);

  static const String prefsKey = 'notified_keys';
  static const int maxKeys = 100; // ~100 messages before the oldest prune

  final SharedPreferences _prefs;

  bool contains(String key) =>
      _prefs.getStringList(prefsKey)?.contains(key) ?? false;

  Future<void> add(String key) async {
    final keys = _prefs.getStringList(prefsKey) ?? <String>[];
    keys.remove(key);
    keys.add(key); // newest last
    while (keys.length > maxKeys) {
      keys.removeAt(0);
    }
    await _prefs.setStringList(prefsKey, keys);
  }
}

/// Filters a source run down to genuinely-new candidates (not in the
/// shared dedupe). Does NOT mark anything - the caller marks a candidate
/// only after it was actually shown, so a failed show is retried next
/// tick instead of being swallowed.
Future<List<NotificationCandidate>> freshCandidates(
  List<NotificationSource> sources,
  SourceContext context, {
  NotifiedTracker? tracker,
}) async {
  final t = tracker ?? NotifiedTracker(context.prefs);
  final fresh = <NotificationCandidate>[];
  for (final source in sources) {
    List<NotificationCandidate> candidates;
    try {
      candidates = await source.check(context);
    } catch (e) {
      debugPrint('notification source ${source.id} failed: $e');
      continue;
    }
    for (final c in candidates) {
      if (t.contains(c.key)) continue;
      fresh.add(c);
    }
  }
  return fresh;
}
