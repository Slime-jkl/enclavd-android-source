import 'package:audioplayers/audioplayers.dart';

/// Port of the site's EnclavdSounds (components/notifications.js) using the
/// site's own sound files (copied to assets/sounds/, LICENSE included):
/// like_sound.mp3 when a post becomes LIKED (never on unlike, per
/// likes.js) and action_sound.mp3 on feed refresh / post create. Lazy
/// per-sound players; replay restarts from 0. Every call is a defensive
/// no-op on failure - audio must never break the UI.
class SoundService {
  SoundService._() {
    // Mix the UI sounds OVER whatever the user is playing (music, a
    // YouTube video). audioplayers' DEFAULT Android context requests
    // AndroidAudioFocus.gain, so Spotify/YouTube pause when a sound
    // fires; `none` plays over the media stream with zero focus
    // interaction (the site's Web Audio behaves the same). mixWithOthers
    // mirrors it on iOS.
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

  /// Master mute - also the test hook (audioplayers has no platform
  /// channel under `flutter test`, so widget tests set this to avoid
  /// unhandled MissingPluginExceptions).
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
      // Belt and braces on top of the global default: a player created
      // before the context was configured must not fall back to
      // focus-gain behavior.
      await player.setAudioContext(mixOverContext);
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio unavailable (tests, headless): never break the UI.
    }
  }
}
