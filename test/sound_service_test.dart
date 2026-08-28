import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/services/sound_service.dart';

/// UI sounds must play over other audio without pausing it; the plugin's
/// default Android context requests AndroidAudioFocus.gain, which pauses
/// the other app (the Aug 2026 "sounds pause my music" regression).
void main() {
  test('sound context plays OVER other media without pausing it', () {
    // The plugin's shipped default (the pause-music behavior):
    final defaultContext = AudioContext();
    expect(defaultContext.android.audioFocus, AndroidAudioFocus.gain,
        reason: 'audioplayers default IS the pause-music behavior');
    // The fix: the service's own context must request NO Android focus and
    // mix on iOS. A revert reds this test on the service's value, not a mirror.
    final context = SoundService.instance.mixOverContext;
    expect(context.android.audioFocus, AndroidAudioFocus.none,
        reason: 'request no focus - the sound plays over the media stream');
    expect(context.iOS.options, contains(AVAudioSessionOptions.mixWithOthers),
        reason: 'iOS must mix with other audio, not interrupt it');
  });
}
