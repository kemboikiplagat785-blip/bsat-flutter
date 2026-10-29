// Ported from the BSAT Local Lab prototype (lib/ui/qr_view.dart).
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Renders text as a QR code (package:qr encodes; this only paints).
class LanQrView extends StatelessWidget {
  final String data;
  final double size;

  const LanQrView({super.key, required this.data, this.size = 220});

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ));
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;

  _QrPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / image.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRect(
              Rect.fromLTWH(col * cell, row * cell, cell + 0.5, cell + 0.5),
              paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
