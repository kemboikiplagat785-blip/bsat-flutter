import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

/// Decodes a QR code from an 8-bit luminance (greyscale) image, such as the
/// Y plane of a camera frame. [rowStride] is the number of bytes per row in
/// [luminance] (at least [width]; camera planes are often padded). Returns
/// null when no readable QR code is found. Pure Dart, no platform access:
/// decoding is testable without a camera.
///
/// The returned text is untrusted input; validate it with
/// `PairingInvitation.parseScanned` before use.
String? decodeQrFromLuminance(
  Uint8List luminance, {
  required int width,
  required int height,
  required int rowStride,
}) {
  if (width <= 0 ||
      height <= 0 ||
      rowStride < width ||
      luminance.length < rowStride * (height - 1) + width) {
    return null;
  }
  final source = _LuminancePlane(luminance, rowStride, width, height);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  for (final binarizer in [
    HybridBinarizer(source),
    GlobalHistogramBinarizer(source),
  ]) {
    try {
      return QRCodeReader().decode(BinaryBitmap(binarizer), hints: hints).text;
    } on ReaderException {
      // Not found or unreadable with this binarizer; try the next.
    }
  }
  return null;
}

/// A padded 8-bit luminance plane as a zxing [LuminanceSource].
class _LuminancePlane extends LuminanceSource {
  final Int8List _data;
  final int _stride;

  _LuminancePlane(Uint8List data, this._stride, int width, int height)
    : _data = Int8List.sublistView(data),
      super(width, height);

  @override
  Int8List getRow(int y, Int8List? row) {
    final out = row != null && row.length >= width ? row : Int8List(width);
    out.setRange(0, width, _data, y * _stride);
    return out;
  }

  @override
  Int8List getMatrix() {
    final matrix = Int8List(width * height);
    for (var y = 0; y < height; y++) {
      matrix.setRange(y * width, (y + 1) * width, _data, y * _stride);
    }
    return matrix;
  }
}
