// Rasterizes LauncherIconPainter into the real launcher-icon assets.
//
// Run explicitly (NOT part of the normal suite — the filename has no _test
// suffix so `flutter test` skips it and never silently overwrites assets):
//
//   flutter test test/tools/render_launcher_icons.dart
//   dart run flutter_launcher_icons
//
// Outputs (1024×1024 PNG):
//   assets/images/app_icon.png            — full icon (iOS + legacy Android)
//   assets/images/app_icon_foreground.png — emblem only (adaptive foreground)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:el_hakem/widgets/launcher_icon.dart';

const _outputSize = 1024;

Future<void> _render({required bool frame, required String path}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(1024, 1024);
  LauncherIconPainter(frame: frame).paint(canvas, size);
  final image =
      await recorder.endRecording().toImage(_outputSize, _outputSize);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  debugPrint('wrote $path (${File(path).lengthSync()} bytes)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rasterize launcher icons to assets/images/', () async {
    await _render(frame: true, path: 'assets/images/app_icon.png');
    await _render(
      frame: false,
      path: 'assets/images/app_icon_foreground.png',
    );
  });
}
