// Do not expose raw engine logs: they may contain provider URLs or credentials.
String playbackFailure(String detail) {
  final text = detail.toLowerCase();
  if (RegExp(r'\b(401|403)\b|unauthori[sz]ed|forbidden').hasMatch(text)) {
    return 'The provider denied playback (401/403). Check account status, connection limits and required stream headers.';
  }
  if (RegExp(r'\b404\b|not found').hasMatch(text)) {
    return 'The stream was not found. Refresh the playlist and try again.';
  }
  if (RegExp(r'tls|ssl|certificate').hasMatch(text)) {
    return 'The secure connection failed. Check the device clock and provider certificate.';
  }
  if (RegExp(
    r'd3d|dxva|gpu|hwdec|hardware|video output|decoder',
  ).hasMatch(text)) {
    return 'Video decoding failed. Try MPV (software decoding) in the player menu.';
  }
  if (RegExp(r'timed? ?out|resolve|connection|network|tcp:').hasMatch(text)) {
    return 'The stream could not be reached. Check the provider connection and device network.';
  }
  return 'MPV could not open this stream. Try software decoding; if that also fails, refresh the playlist and check provider access.';
}
