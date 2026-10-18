import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// ML Kit. Works for both the single-plane NV21 frames produced on Android
class CameraImageConverter {
  CameraImageConverter._();

  static InputImage? fromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    final sensorOrientation = controller.description.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation90deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format != null && image.planes.length == 1) {
      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    // Multi-plane frames (iOS) are concatenated into a single NV21 buffer,
    // which ML Kit accepts.
    final total = image.planes.fold<int>(
      0,
      (sum, plane) => sum + plane.bytes.length,
    );
    final bytes = Uint8List(total);
    var offset = 0;
    for (final plane in image.planes) {
      bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }
}
