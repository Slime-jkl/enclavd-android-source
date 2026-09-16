import 'package:audioplayers/audioplayers.dart';

/// The site's own sound files, played lazily. Every call is a no-op on
/// failure: audio never breaks the UI.
class SoundService {
  SoundService._() {
    // Play OVER the user's media: the default context would ask for audio
    // focus and pause Spotify/YouTube, where the site's Web Audio does not.
    mixOverContext = AudioContext(
      android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    );
  }

  static final SoundService instance = SoundService._();

  /// Read-only for tests: they assert the mix-over contract.
  late final AudioContext mixOverContext;

  /// Test hook: audioplayers has no platform channel under `flutter test`.
  static bool muted = false;

  AudioPlayer? _like;
  AudioPlayer? _action;
  AudioPlayer? _ignite;

  Future<void> like() async {
    if (muted) return;
    await _play(_player(like: true), 'sounds/like_sound.mp3');
  }

  Future<void> action() async {
    if (muted) return;
    await _play(_player(like: false), 'sounds/action_sound.mp3');
  }

  /// The site's flame recording, on a grant and on a re-press.
  Future<void> ignite() async {
    if (muted) return;
    await _play(_ignite ??= AudioPlayer(), 'sounds/flame-vortex-SFAW.wav');
  }

  AudioPlayer _player({required bool like}) {
    if (like) {
      return _like ??= AudioPlayer();
    }
    return _action ??= AudioPlayer();
  }

  Future<void> _play(AudioPlayer player, String asset) async {
    try {
      await player.setAudioContext(mixOverContext);
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio unavailable (tests, headless): never break the UI.
    }
  }
}
