import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/platform/backup_gzip.dart' as portable;
import 'package:lumen_iptv/platform/backup_gzip_io.dart' as native;

class LimitedOutput extends OutputMemoryStream {
  LimitedOutput(this.limit);
  final int limit;
  int largestChunk = 0;

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count > largestChunk) largestChunk = count;
    if (this.length + count > limit) {
      throw const FormatException('Expansion limit exceeded');
    }
    super.writeBytes(bytes, length: length);
  }
}

void main() {
  test('Native gzip rejects expansion before accumulating full output', () {
    final compressed = GZipEncoder().encode(Uint8List(16 * 1024 * 1024));
    final output = LimitedOutput(64 * 1024);
    expect(
      () => native.decodeBackupGzip(compressed, output),
      throwsFormatException,
    );
    expect(output.length, lessThanOrEqualTo(output.limit));
    // The old callback implementation forwards a single 16 MiB allocation.
    expect(output.largestChunk, lessThan(2 * 1024 * 1024));
  });

  test(
    'Native and portable decoding preserve valid gzip data at the limit',
    () {
      final payload = Uint8List.fromList(List.generate(65536, (i) => i % 251));
      final compressed = GZipEncoder().encode(payload);
      for (final decode in [
        native.decodeBackupGzip,
        portable.decodeBackupGzip,
      ]) {
        final output = LimitedOutput(payload.length);
        decode(compressed, output);
        expect(output.getBytes(), payload);
      }
    },
  );

  test('Native decoding rejects an invalid gzip header', () {
    final compressed = GZipEncoder().encode(Uint8List(1024));
    compressed[0] = 0;
    expect(
      () => native.decodeBackupGzip(
        compressed,
        LimitedOutput(2048),
      ),
      throwsFormatException,
    );
  });
}
