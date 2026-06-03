import 'package:exif/exif.dart' show readExifFromBytes;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// EXIF 회전 정보를 픽셀에 반영 — 가로 촬영 시 사진이 누워 보이는 문제 수정
///
/// image 4.x의 decodeImage()는 EXIF를 내부 포맷으로 파싱하지 못해
/// bakeOrientation()이 동작하지 않는 경우가 있음.
/// → exif 패키지로 raw bytes에서 Orientation 태그를 직접 읽어 명시적으로 회전.
Future<Uint8List> correctPhotoRotation(XFile xfile) async {
  final bytes = await xfile.readAsBytes();

  // 1. exif 패키지로 Orientation 태그 직접 읽기
  int orientation = 1;
  try {
    final tags = await readExifFromBytes(bytes);
    final orientTag = tags['Image Orientation'];
    if (orientTag != null) {
      final vals = orientTag.values.toList();
      if (vals.isNotEmpty) {
        final raw = vals.first;
        if (raw is int) {
          orientation = raw;
        } else {
          orientation = int.tryParse(raw.toString()) ?? 1;
        }
      }
    }
  } catch (e) {
    debugPrint('EXIF 파싱 실패: $e');
  }

  if (orientation <= 1) return bytes;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  img.Image? corrected;
  switch (orientation) {
    case 3:
      corrected = img.copyRotate(decoded, angle: 180);
    case 6:
      if (decoded.width > decoded.height) {
        corrected = img.copyRotate(decoded, angle: -90);
      }
    case 8:
      if (decoded.width > decoded.height) {
        corrected = img.copyRotate(decoded, angle: 90);
      }
  }

  if (corrected == null) return bytes;
  return Uint8List.fromList(img.encodeJpg(corrected, quality: 92));
}
