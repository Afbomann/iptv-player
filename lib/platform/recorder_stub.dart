class StreamRecorder {
  Future<String> record({
    required String id,
    required String url,
    required DateTime end,
    Map<String, String> headers = const {},
    int maxBytes = 4294967296,
  }) async =>
      throw UnsupportedError('Local recording is unavailable in this browser.');
  void stop(String id) {}
  Future<void> close() async {}
}
