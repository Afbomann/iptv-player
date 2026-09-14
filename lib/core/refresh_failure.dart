/// Classify failures without exposing provider URLs, response bodies or SQL values.
String refreshFailure(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('quota') ||
      text.contains('disk is full') ||
      text.contains('sqlite_full')) {
    return 'Local storage is full. Free browser/device storage and retry.';
  }
  if (text.contains('locked') || text.contains('sqlite_busy')) {
    return 'Local storage is busy. Close other Lumen tabs and retry.';
  }
  if (text.contains('no such table') || text.contains('no such column')) {
    return 'Local database schema mismatch. Reload the app; do not clear its data.';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'The provider request timed out.';
  }
  final status = RegExp(r'provider returned http (\d{3})').firstMatch(text);
  if (status != null) return 'Provider returned HTTP ${status[1]}.';
  if (text.contains('could not be reached')) {
    return 'Provider unreachable. Check network, CORS and HTTPS/mixed-content restrictions.';
  }
  if (text.contains('size limit') ||
      text.contains('too large') ||
      text.contains('memory limit')) {
    return 'The feed exceeds the supported size limit.';
  }
  if (text.contains('credentials') || text.contains('not active')) {
    return 'Provider rejected the account or it is inactive.';
  }
  if (error is FormatException) {
    return 'The provider feed has invalid or unsupported data.';
  }
  return 'Local processing/storage failed. Close other Lumen tabs and retry.';
}
