import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/ui/episode_picker.dart';

void main() {
  const first = MediaItem(
    id: '1',
    sourceId: 's',
    name: 'First episode',
    url: '',
    kind: MediaKind.episode,
    season: 2,
    episode: 1,
  );
  const second = MediaItem(
    id: '2',
    sourceId: 's',
    name: 'Second episode',
    url: '',
    kind: MediaKind.episode,
    season: 2,
    episode: 2,
  );
  testWidgets('Picker marks current episode and sorts the season numerically', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePicker(current: first, load: () async => [second, first]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('First episode')).dy,
      lessThan(tester.getTopLeft(find.text('Second episode')).dy),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Failed episode loading offers retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePicker(
          current: first,
          load: () async {
            if (++calls == 1) throw StateError('Offline');
            return [first];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Could not load episodes. Retry'));
    await tester.pumpAndSettle();
    expect(find.text('First episode'), findsOneWidget);
  });
}
