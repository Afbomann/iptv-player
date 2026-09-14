import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import '../core/security.dart';
import '../core/backup_limits.dart';

/// Bounded encrypted frames. Uploads are spooled to disk, not accumulated as
/// nested JSON/base64 strings. Only the final password-encrypted archive is read.
class BackupTransport {
  BackupTransport(this.session, this.key, this.origin, this.backup);
  final String session, origin;
  final SecretKey key;
  final String? backup;
  Directory? _temporary;
  RandomAccessFile? _file;
  int _index = 0, _size = 0;
  bool _busy = false, finished = false, _closed = false;

  Future<Map<String, dynamic>?> handle(HttpRequest request) async {
    if (_closed || finished) {
      request.response.statusCode = 410;
      return null;
    }
    if (_busy) {
      request.response.statusCode = 409;
      return null;
    }
    if (request.headers.value('origin') != origin ||
        request.contentLength < 0 ||
        request.contentLength > 600 * 1024) {
      request.response.statusCode = 413;
      return null;
    }
    _busy = true;
    try {
      final body = await utf8.decoder
          .bind(request)
          .join()
          .timeout(const Duration(seconds: 60));
      final envelope = jsonDecode(body);
      if (envelope['session'] != session) {
        request.response.statusCode = 403;
        return null;
      }
      final payload = jsonDecode(await Security.open(body, key));
      if (payload['index'] != _index) {
        request.response.statusCode = 409;
        return null;
      }
      if (request.uri.path == '/backup/download' && backup != null) {
        if (backup!.length > backupTransferLimit) {
          throw const FormatException('Backup exceeds 256 MB.');
        }
        final start = _index * backupChunkSize;
        final end = (start + backupChunkSize).clamp(0, backup!.length);
        final chunk = backup!.substring(start, end);
        final done = end == backup!.length;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          await Security.seal(
            jsonEncode({
              'index': _index,
              'bytes': base64Encode(utf8.encode(chunk)),
              'done': done,
              'total': backup!.length,
            }),
            key,
          ),
        );
        _index++;
        finished = done;
        return null;
      }
      if (request.uri.path != '/backup/upload' ||
          backup != null ||
          payload['done'] is! bool ||
          payload['bytes'] is! String) {
        request.response.statusCode = 400;
        return null;
      }
      final bytes = base64Decode(payload['bytes']);
      if (bytes.length > backupChunkSize ||
          (bytes.isEmpty && payload['done'] != true) ||
          _size + bytes.length > backupTransferLimit) {
        request.response.statusCode = 413;
        return null;
      }
      if (_file == null) {
        _temporary = await Directory.systemTemp.createTemp('lumen-transfer-');
        _file = await File(
          '${_temporary!.path}/backup.lumen',
        ).open(mode: FileMode.write);
      }
      await _file!.writeFrom(bytes);
      _size += bytes.length;
      _index++;
      request.response.statusCode = 202;
      if (payload['done'] != true) return null;
      await _file!.close();
      _file = null;
      final value = await File(
        '${_temporary!.path}/backup.lumen',
      ).readAsString();
      finished = true;
      await _temporary!.delete(recursive: true);
      _temporary = null;
      return {'backup': value};
    } finally {
      _busy = false;
      if (_closed) await close();
    }
  }

  Future<void> close() async {
    _closed = true;
    if (_busy) return;
    await _file?.close();
    _file = null;
    if (_temporary != null && await _temporary!.exists()) {
      await _temporary!.delete(recursive: true);
    }
    _temporary = null;
  }
}
