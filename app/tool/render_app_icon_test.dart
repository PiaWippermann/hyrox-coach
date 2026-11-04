// Erzeugt das App-Icon (1024 × 1024 PNG) aus dem LogoPainter.
// Aufruf: flutter test tool/render_app_icon_test.dart  → schreibt build/app_icon_1024.png
// Die einzelnen iOS-Größen erzeugt tool/make_ios_icons.sh daraus.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyrox_coach/widgets/logo.dart';

void main() {
  test('App-Icon rendern', () async {
    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    // iOS rundet die Ecken selbst und verlangt ein Icon ohne Transparenz
    const LogoPainter(cornerRadius: 0).paint(ui.Canvas(recorder), const ui.Size(size, size));
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/app_icon_1024.png')..createSync(recursive: true);
    out.writeAsBytesSync(png!.buffer.asUint8List());
  });
}
