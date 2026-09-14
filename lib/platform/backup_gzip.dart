import 'package:archive/archive.dart';

/// The browser decoder writes directly to the bounded output stream.
void decodeBackupGzip(List<int> compressed, OutputStream output) {
  GZipDecoder().decodeStream(InputMemoryStream(compressed), output);
}
