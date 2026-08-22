import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/services/sound_service.dart';

/// The audio-context contract is the whole point of the sound service:
/// UI sounds must play OVER whatever the user is listening to (music, a
/// YouTube video) WITHOUT pausing it. audioplayers' DEFAULT Android
/// context requests AndroidAudioFocus.gain — the app becomes the sole
/// audio source and the other app PAUSES. The regression (Aug 2026,
/// "sounds pause my music") was exactly that default being left in place.
void main() {
  test('sound context plays OVER other media without pausing it', () {
    // The default the plugin ships — the pause-music behavior:
    final defaultContext = AudioContext();
    expect(defaultContext.android.audioFocus, AndroidAudioFocus.gain,
        reason: 'audioplayers default IS the pause-music behavior');
    // The fix: the service's actual context (exposed read-only) must
    // request NO Android focus and mix on iOS. If a future edit reverts
    // this, the test reds on the service's own value — not a mirror.
    final context = SoundService.instance.mixOverContext;
    expect(context.android.audioFocus, AndroidAudioFocus.none,
        reason: 'request no focus — the sound plays over the media stream');
    expect(context.iOS.options, contains(AVAudioSessionOptions.mixWithOthers),
        reason: 'iOS must mix with other audio, not interrupt it');
  });
}
