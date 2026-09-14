import 'dart:io';
import '../core/backup_limits.dart';

Future<String> readBackupPath(String path) async {
  final file = File(path);
  if (await file.length() > backupTransferLimit) {
    throw const FormatException('Backup exceeds the 256 MB limit.');
  }
  return file.readAsString();
}
