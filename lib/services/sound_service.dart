import 'package:audioplayers/audioplayers.dart';

/// Port of the site's EnclavdSounds (components/notifications.js) using the
/// site's own sound files (copied to assets/sounds/, LICENSE included):
///
///   like_sound.mp3    → played when a post becomes LIKED (never on unlike —
///                       matches likes.js: only when action === 'liked')
///   action_sound.mp3  → played on feed refresh and after a post is created
///                       (matches posts.js: "action sound on create")
///
/// Lazy per-sound AudioPlayers (the site's preload pattern); replay restarts
/// from 0. Every call is a defensive no-op on failure — audio must never
/// break the UI (tests, muted devices, headless runs).
class SoundService {
  SoundService._();

  static final SoundService instance = SoundService._();

  /// Master mute — also the test hook (audioplayers has no platform channel
  /// under `flutter test`, so widget tests set this to avoid unhandled
  /// MissingPluginExceptions).
  static bool muted = false;

  AudioPlayer? _like;
  AudioPlayer? _action;

  Future<void> like() async {
    if (muted) return;
    await _play(_player(like: true), 'sounds/like_sound.mp3');
  }

  Future<void> action() async {
    if (muted) return;
    await _play(_player(like: false), 'sounds/action_sound.mp3');
  }

  AudioPlayer _player({required bool like}) {
    if (like) {
      return _like ??= AudioPlayer();
    }
    return _action ??= AudioPlayer();
  }

  Future<void> _play(AudioPlayer player, String asset) async {
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio unavailable (tests, headless) — never break the UI.
    }
  }
}
