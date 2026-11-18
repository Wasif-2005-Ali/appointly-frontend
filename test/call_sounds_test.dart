// Regression test for the bundled call sounds (FIX 3).
//
// The incoming ringtone and outgoing ringback are real MP3 assets
// at assets/ root (declared via the `assets/` entry in pubspec.yaml
// — no per-file entry needed). They live at the root deliberately:
// Flutter directory asset entries are NOT recursive (the tool's
// `_parseAssetsFromFolder` lists direct children only), so files
// under assets/sounds/ would silently NOT be bundled. If either
// file goes missing or is not a real MP3, audioplayers fails
// silently and the call rings silently. This test pins both asset
// paths in the asset manifest and proves each file is a real MP3
// (ID3 header or MPEG frame sync).
//
// Run with `flutter test test/call_sounds_test.dart`.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const expectedSounds = <String>[
    'assets/ringtone.mp3',
    'assets/ringback.mp3',
  ];

  test('call sound assets exist in the asset manifest', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    for (final path in expectedSounds) {
      expect(
        assets,
        contains(path),
        reason: 'Missing call sound $path — the call would ring silently.',
      );
    }
  });

  test('call sound assets load as real MP3 files', () async {
    for (final path in expectedSounds) {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, greaterThan(1000), reason: '$path is too small');
      // MP3 magic: an ID3 tag ("ID3" — I=0x49, D=0x44, 3=0x33) or
      // an MPEG audio frame sync (0xFF followed by 0xF0-0xFF, i.e.
      // 11 sync bits set).
      final isId3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
      final isFrameSync =
          bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      expect(
        isId3 || isFrameSync,
        isTrue,
        reason: '$path is not an MP3 file (bad magic bytes).',
      );
    }
  });
}
