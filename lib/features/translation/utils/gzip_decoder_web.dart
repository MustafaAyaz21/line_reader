import 'dart:js_interop';
import 'dart:typed_data';

@JS('DecompressionStream')
extension type _DecompressionStream._(JSObject _) implements JSObject {
  external factory _DecompressionStream(String format);
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny?> parts);
  external JSObject stream();
}

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSObject body);
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _ReadableStream(JSObject _) implements JSObject {
  external JSObject pipeThrough(JSObject transform);
}

Future<List<int>> decodeGzipBytes(Uint8List compressed) async {
  final blob = _Blob(<JSAny?>[compressed.toJS].toJS);
  final stream = _ReadableStream(blob.stream());
  final decompressedStream = stream.pipeThrough(_DecompressionStream('gzip'));
  final buffer = await _Response(decompressedStream).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
