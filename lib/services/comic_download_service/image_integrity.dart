import 'dart:typed_data';
import 'dart:ui' as ui;

/// Checks common truncation markers before asking Flutter to decode the image.
Future<bool> isCompleteImage(Uint8List bytes) async {
  if (!_hasCompleteContainer(bytes)) return false;
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1,
      targetHeight: 1,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final bool valid = frame.image.width > 0 && frame.image.height > 0;
    frame.image.dispose();
    return valid;
  } catch (_) {
    return false;
  } finally {
    codec?.dispose();
  }
}

bool _hasCompleteContainer(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final ByteData data = ByteData.sublistView(bytes);
  if (bytes[0] == 0xff && bytes[1] == 0xd8) {
    return bytes[bytes.length - 2] == 0xff && bytes.last == 0xd9;
  }
  if (data.getUint32(0) == 0x89504e47 && data.getUint32(4) == 0x0d0a1a0a) {
    return data.getUint32(bytes.length - 12) == 0 &&
        data.getUint32(bytes.length - 8) == 0x49454e44 &&
        data.getUint32(bytes.length - 4) == 0xae426082;
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return bytes.last == 0x3b;
  }
  if (data.getUint32(0) == 0x52494646 && data.getUint32(8) == 0x57454250) {
    return data.getUint32(4, Endian.little) + 8 == bytes.length;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4d) {
    return data.getUint32(2, Endian.little) <= bytes.length;
  }
  // Other platform-supported formats, including AVIF, use the native decoder.
  return true;
}
