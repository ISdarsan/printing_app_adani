import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers the app's real bundled Inter font for widget tests.
///
/// Without this, flutter_test draws every character with a placeholder font in
/// which each glyph is as wide as its font size, so overflow tests would give
/// false alarms (and tell you nothing about real phones). With it, text widths
/// match what staff see on the device.
Future<void> loadInterFont() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Inter-$w.otf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}
