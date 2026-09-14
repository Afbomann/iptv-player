class SessionPool {
  static final shared = SessionPool();
  final Map<String, String> _leases = {};
  bool acquire(String owner, String source, int maximum) {
    if (_leases.containsKey(owner)) return true;
    if (_leases.values.where((v) => v == source).length >= maximum) {
      return false;
    }
    _leases[owner] = source;
    return true;
  }

  void release(String owner) => _leases.remove(owner);
  int count(String source) => _leases.values.where((v) => v == source).length;
}
