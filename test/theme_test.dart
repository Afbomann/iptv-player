import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/ui/common.dart';

void main() {
  testWidgets('Accent changes propagate to labels, fields and buttons', (
    tester,
  ) async {
    for (final accent in [const Color(0xffba93fa), const Color(0xff2471a3)]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: lumenTheme(accent: accent),
          home: Scaffold(
            body: Column(
              children: [
                const Eyebrow('Featured'),
                const TextField(),
                FilledButton(onPressed: () {}, child: const Text('Play')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Eyebrow));
      expect(tester.widget<Text>(find.text('FEATURED')).style!.color, accent);
      expect(Theme.of(context).colorScheme.primary, accent);
      expect(
        Theme.of(context).inputDecorationTheme.focusedBorder!.borderSide.color,
        accent,
      );
      expect(
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Theme.of(context).colorScheme.onPrimary == Colors.white
            : Theme.of(context).colorScheme.onPrimary != Colors.white,
        isTrue,
      );
    }
  });
}
