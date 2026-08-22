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
  SoundService._() {
    // Mix the UI sounds OVER whatever the user is playing (music, a
    // YouTube video) instead of pausing it. audioplayers' DEFAULT Android
    // audio context requests AndroidAudioFocus.gain — the app becomes the
    // sole audio source, so Spotify/YouTube pause when a like or action
    // sound fires. gainTransientMayDuck would also pause-then-resume on
    // some devices; `none` makes the sound play over the media stream
    // with zero focus interaction (the site's Web Audio behaves the same:
    // sounds mix over, never interrupt). Also mirrors the iOS side with
    // mixWithOthers so the same rule holds there.
    mixOverContext = AudioContext(
      android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    );
  }

  static final SoundService instance = SoundService._();

  /// The non-focus audio context applied to every player. [AudioPlayer]
  /// copies the global context at creation, so setting it once here covers
  /// both lazily-created players. Exposed read-only so tests can assert
  /// the mix-over contract without touching the platform.
  late final AudioContext mixOverContext;

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
      // Apply the mix-over context to THIS player (belt and braces on top
      // of the global default — a player created before the context was
      // configured must not fall back to focus-gain behavior).
      await player.setAudioContext(mixOverContext);
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio unavailable (tests, headless) — never break the UI.
    }
  }
}
