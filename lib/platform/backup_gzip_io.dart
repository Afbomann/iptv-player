import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Do not use archive's native decodeStream: its callback sink collects the
/// complete expanded archive before forwarding it to the bounded output.
void decodeBackupGzip(List<int> compressed, OutputStream output) {
  final decoder = gzip.decoder.startChunkedConversion(_OutputSink(output));
  // Bound input too: a single native conversion must not inflate an entire
  // high-compression archive before returning control to the output sink.
  for (var offset = 0; offset < compressed.length; offset += 1024) {
    final end = (offset + 1024).clamp(0, compressed.length);
    decoder.add(
      compressed is Uint8List
          ? Uint8List.sublistView(compressed, offset, end)
          : compressed.sublist(offset, end),
    );
  }
  decoder.close();
}

class _OutputSink implements Sink<List<int>> {
  _OutputSink(this.output);
  final OutputStream output;

  @override
  void add(List<int> chunk) => output.writeBytes(chunk);

  @override
  void close() {}
}
