import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import '../core/backup_limits.dart';
import 'backup_file_stub.dart' if (dart.library.io) 'backup_file_io.dart';

Future<String> readBackupFile(PlatformFile file) async {
  if (file.size > backupTransferLimit) {
    throw const FormatException('Backup exceeds the 256 MB limit.');
  }
  if (file.bytes != null) return utf8.decode(file.bytes!);
  if (file.path != null) return readBackupPath(file.path!);
  throw const FormatException('The selected backup could not be read.');
}
