import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'package:enclavd/utils/emoji.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dotLottie assets unpack into compositions', () async {
    for (final name in ['smile', 'phoenix', '8-ball']) {
      final data = await rootBundle.load('assets/gifs/emojis/$name.lottie');
      final composition = await LottieComposition.fromByteData(data);
      expect(composition.layers, isNotEmpty, reason: name);
      expect(emojiCatalog, contains(name));
    }
  });
}
