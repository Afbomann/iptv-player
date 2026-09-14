import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/recording_conflicts.dart';

void main() {
  Map<String, dynamic> job(
    int start,
    int end, {
    String source = 'provider',
    String status = 'scheduled',
  }) => {'source': source, 'status': status, 'start': start, 'end': end};

  test('Sequential overlaps consume one existing connection, not two', () {
    expect(
      peakRecordingConcurrency([job(10, 20), job(20, 30)], 'provider', 0, 40),
      1,
    );
  });
  test('Peak detects simultaneous padded intervals', () {
    expect(
      peakRecordingConcurrency([job(8, 22), job(18, 32)], 'provider', 0, 40),
      2,
    );
    expect(
      peakRecordingConcurrency(
        [job(0, 100), job(10, 20), job(30, 40)],
        'provider',
        5,
        50,
      ),
      2,
    );
  });
  test('Ignore boundary-only overlaps, other providers and inactive jobs', () {
    expect(
      peakRecordingConcurrency(
        [
          job(0, 10),
          job(20, 30),
          job(10, 20, source: 'other'),
          job(10, 20, status: 'completed'),
          job(12, 18, status: 'recording'),
        ],
        'provider',
        10,
        20,
      ),
      1,
    );
    expect(peakRecordingConcurrency([], 'provider', 10, 20), 0);
  });
}
