// Regression test for the bundled-fonts setup.
//
// google_fonts only picks up a bundled font when the asset path (minus
// extension) case-sensitively ends with the Google Fonts API filename,
// e.g. "DM Sans-Regular". A renamed file silently falls back to a
// runtime download — and with GoogleFonts.config.allowRuntimeFetching
// set to false (see main.dart), to the fallback font. This test pins
// every bundled font asset path in the asset manifest, and loads each
// file to prove it is a real TTF (magic bytes 00 01 00 00).
//
// Run with `flutter test test/bundled_fonts_test.dart`.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every weight/style the app actually uses via GoogleFonts.*:
  // DM Sans 400-900 + the two italics, Poppins 400-700,
  // Space Grotesk 400-700 (w800 uses closest-match to Bold).
  const expectedFonts = <String>[
    'assets/fonts/DM Sans-Regular.ttf',
    'assets/fonts/DM Sans-Medium.ttf',
    'assets/fonts/DM Sans-SemiBold.ttf',
    'assets/fonts/DM Sans-Bold.ttf',
    'assets/fonts/DM Sans-ExtraBold.ttf',
    'assets/fonts/DM Sans-Black.ttf',
    'assets/fonts/DM Sans-Italic.ttf',
    'assets/fonts/DM Sans-MediumItalic.ttf',
    'assets/fonts/Poppins-Regular.ttf',
    'assets/fonts/Poppins-Medium.ttf',
    'assets/fonts/Poppins-SemiBold.ttf',
    'assets/fonts/Poppins-Bold.ttf',
    'assets/fonts/Space Grotesk-Regular.ttf',
    'assets/fonts/Space Grotesk-Medium.ttf',
    'assets/fonts/Space Grotesk-SemiBold.ttf',
    'assets/fonts/Space Grotesk-Bold.ttf',
  ];

  test('bundled font assets exist in the asset manifest', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    for (final path in expectedFonts) {
      expect(
        assets,
        contains(path),
        reason: 'Missing bundled font $path — google_fonts would fetch it at '
            'runtime (or fall back, with allowRuntimeFetching=false).',
      );
    }
  });

  test('bundled font assets load as real TTF files', () async {
    for (final path in expectedFonts) {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, greaterThan(1000), reason: '$path is too small');
      // TrueType magic: 00 01 00 00 (or 'true' / 'OTTO').
      final magic = bytes.sublist(0, 4);
      final isTtf = magic[0] == 0x00 &&
          magic[1] == 0x01 &&
          magic[2] == 0x00 &&
          magic[3] == 0x00;
      final isTrueTypeCollection = String.fromCharCodes(magic) == 'true' ||
          String.fromCharCodes(magic) == 'OTTO';
      expect(
        isTtf || isTrueTypeCollection,
        isTrue,
        reason: '$path is not a TTF/OTF file (bad magic bytes).',
      );
    }
  });
}
