import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/playback/sessions.dart';

void main() {
  const safe = MediaItem(
    id: 'one:safe',
    sourceId: 'one',
    name: 'Safe',
    url: 'https://test/safe',
    group: 'Family',
    rating: 6,
  );
  const adult = MediaItem(
    id: 'one:adult',
    sourceId: 'one',
    name: 'Adult',
    url: 'https://test/adult',
    group: 'Adults',
    rating: 18,
  );
  test('Profile restrictions combine source, group, channel, and age', () {
    const child = Profile(
      id: 'child',
      name: 'Child',
      passwordHash: 'hash',
      allowedSources: ['one'],
      blockedGroups: ['Adults'],
      maxRating: 12,
      allowUnrated: false,
    );
    expect(child.allows(safe), isTrue);
    expect(child.allows(adult), isFalse);
    expect(
      child.allows(
        const MediaItem(
          id: 'two:x',
          sourceId: 'two',
          name: 'Other',
          url: 'https://test/other',
          rating: 6,
        ),
      ),
      isFalse,
    );
    expect(
      child.allows(
        const MediaItem(
          id: 'one:unrated',
          sourceId: 'one',
          name: 'Unknown',
          url: 'https://test/unknown',
        ),
      ),
      isFalse,
    );
  });
  test('Connection pool shares limits between viewing and recording', () {
    final pool = SessionPool();
    expect(pool.acquire('view', 'one', 2), isTrue);
    expect(pool.acquire('record', 'one', 2), isTrue);
    expect(pool.acquire('extra', 'one', 2), isFalse);
    expect(pool.acquire('view', 'one', 2), isTrue);
    pool.release('view');
    expect(pool.acquire('extra', 'one', 2), isTrue);
    expect(pool.acquire('other', 'two', 1), isTrue);
  });
}
