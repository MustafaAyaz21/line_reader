import 'dart:io';
import 'dart:typed_data';

Future<List<int>> decodeGzipBytes(Uint8List compressed) async {
  return gzip.decode(compressed);
}
