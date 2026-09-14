/// Peak existing usage during a proposed padded, half-open recording interval.
int peakRecordingConcurrency(
  Iterable<Map<String, dynamic>> jobs,
  String source,
  int from,
  int until,
) {
  final events = <(int, int)>[];
  for (final job in jobs) {
    if (job['source'] != source ||
        !['scheduled', 'recording'].contains(job['status'])) {
      continue;
    }
    final start = job['start'] as int;
    final end = job['end'] as int;
    if (start >= until || end <= from || end <= start) continue;
    events.add((start < from ? from : start, 1));
    events.add((end > until ? until : end, -1));
  }
  // Ending jobs release their connection before jobs at the same time start.
  events.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  var current = 0;
  var peak = 0;
  for (final event in events) {
    current += event.$2;
    if (current > peak) peak = current;
  }
  return peak;
}
