class PairingServer {
  String get url => '';
  Future<void> start(
    void Function(Map<String, dynamic>) onSubmit, {
    bool transfer = false,
    String? backup,
  }) async => throw UnsupportedError(
    'Pairing is hosted by a native TV or desktop app.',
  );
  Future<void> close() async {}
}
