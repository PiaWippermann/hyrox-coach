import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo: ein „H“ aus zwei Säulen, der Querbalken ist eine ansteigende Pulslinie (Fortschritt + Herzschlag).
/// Gezeichnet statt als Bild, damit es in jeder Größe scharf ist; dieselbe Grafik erzeugt das App-Icon
/// (tool/render_app_icon_test.dart).
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40, this.background = true});

  final double size;
  final bool background; // false: nur das Zeichen, z. B. auf farbigem Grund

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: LogoPainter(background: background)));
}

class LogoPainter extends CustomPainter {
  const LogoPainter({this.background = true, this.cornerRadius = 0.24});

  final bool background;
  final double cornerRadius; // Anteil der Kantenlänge; 0 für das iOS-Icon (iOS rundet selbst)

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100; // Zeichnung im 100er-Raster
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * cornerRadius)),
        Paint()..color = AppColors.espresso,
      );
    }

    // Säulen
    Paint pillar(Color c) => Paint()..color = c;
    canvas.drawRRect(
      RRect.fromLTRBR(24 * u, 22 * u, 37 * u, 78 * u, Radius.circular(6.5 * u)),
      pillar(AppColors.greige),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(63 * u, 22 * u, 76 * u, 78 * u, Radius.circular(6.5 * u)),
      pillar(AppColors.dusk),
    );

    // Pulslinie als Querbalken: flach, Ausschlag nach oben, Abfall, steiler Anstieg nach rechts oben
    final pulse = Path()
      ..moveTo(30 * u, 57 * u)
      ..lineTo(42 * u, 57 * u)
      ..lineTo(49 * u, 41 * u)
      ..lineTo(56 * u, 59 * u)
      ..lineTo(70 * u, 40 * u);
    // Kontur in Grundfarbe trennt die Linie optisch von den Säulen
    canvas.drawPath(
      pulse,
      Paint()
        ..color = AppColors.espresso
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15 * u
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      pulse,
      Paint()
        ..shader = const LinearGradient(colors: [AppColors.blue, AppColors.sky])
            .createShader(Rect.fromLTRB(30 * u, 40 * u, 70 * u, 60 * u))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * u
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant LogoPainter old) => old.background != background || old.cornerRadius != cornerRadius;
}
