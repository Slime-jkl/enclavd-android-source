import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// The pluggable core of background notifications.
///
/// A [NotificationSource] knows how to check ONE notification domain
/// (messaging today; post likes/comments/mentions tomorrow) and produce
/// candidate notifications. The worker runner, the dedupe and the
/// notification plumbing are all generic — adding a new notification
/// type is: implement [NotificationSource], add one line to
/// `backgroundSources()` in notification_worker.dart, done.
///
/// Every source is read-only (GET only). Marking things read stays the
/// user-facing app's job (opening the thread), exactly like the live
/// path — the worker must never mutate server state with a CSRF-less
/// background session.
abstract class NotificationSource {
  /// Short namespace for this source. Every dedupe key starts with it
  /// ('message', later 'post', ...) so sources never collide.
  String get id;

  /// Check for new things to notify about. Must swallow its own errors
  /// (a dead session or transient failure → return []) — a broken source
  /// must never crash the worker or block the others. The next tick
  /// retries.
  Future<List<NotificationCandidate>> check(SourceContext context);
}

/// What a source hands the runner: everything needed to show one
/// notification. The dedupe identity is [key], NOT the notification id —
/// a conversation's notification id stays fixed so Android replaces the
/// older notification instead of stacking.
class NotificationCandidate {
  const NotificationCandidate({
    required this.key,
    required this.notificationId,
    required this.title,
    required this.body,
    this.payload,
  });

  /// Dedupe identity, e.g. 'message:5:102' or (later) 'post:comment:12'.
  final String key;

  /// Android notification id — stable per grouping (per conversation),
  /// so a new item replaces the previous notification of that group.
  final int notificationId;

  final String title;
  final String body;

  /// App payload on tap/action (e.g. 'c:5' for a drawer reply).
  final String? payload;
}

/// The context every source gets: a session-bearing client (built fresh
/// per worker run; the live path passes its own) and prefs (toggles,
/// dedupe, UI state mirrored for the worker).
class SourceContext {
  SourceContext({required this.api, required this.prefs});

  final ApiClient api;
  final SharedPreferences prefs;
}

/// Cross-path dedupe, persisted to prefs: a bounded FIFO set of seen
/// keys. BOTH the live path (SSE ping → handleUnreadPing) and the
/// background worker (15-min WorkManager) write here, so a message never
/// double-notifies even when both fire — and a notification shown by one
/// path is never repeated by the other.
///
/// Tradeoff, accepted: the list is read-modify-written from two isolates
/// (main + worker). A lost write in a race can only cause a duplicate
/// notification, never a missed one (the live path's own dedupe covers
/// the in-process case; ids only ever advance).
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
/// shared dedupe). Does NOT mark anything — the caller marks a candidate
/// only after it was actually shown, so a failed show is retried next
/// tick instead of being swallowed. Defensive per source: a broken
/// source must never kill the worker or block the others.
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
