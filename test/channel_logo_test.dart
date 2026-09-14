import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/ui/channel_logo.dart';

void main() {
  testWidgets('Missing or unsupported channel logos use a bounded TV icon', (
    tester,
  ) async {
    for (final url in ['', 'not a URL', 'file:///private/logo.png']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChannelLogo(url: url)),
        ),
      );
      expect(find.byIcon(Icons.live_tv_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(ChannelLogo)), const Size(36, 36));
    }
  });

  testWidgets('Unreachable logo falls back without a layout error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChannelLogo(url: 'https://invalid.test/logo.png')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.live_tv_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ChannelLogo)), const Size(36, 36));
  });
}
