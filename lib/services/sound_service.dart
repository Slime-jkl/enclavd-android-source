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

  AudioPlayer? _like;
  AudioPlayer? _action;

  Future<void> like() =>
      _play(_like ??= AudioPlayer(), 'sounds/like_sound.mp3');

  Future<void> action() =>
      _play(_action ??= AudioPlayer(), 'sounds/action_sound.mp3');

  Future<void> _play(AudioPlayer player, String asset) async {
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio unavailable — never throw into the UI flow.
    }
  }
}
