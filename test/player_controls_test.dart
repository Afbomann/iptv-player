import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/core/models.dart';
import 'package:lumen_iptv/playback/engine.dart';
import 'package:lumen_iptv/ui/video_stage.dart';

class TestEngine extends PlaybackEngine {
  @override
  EngineKind get kind => EngineKind.browser;
  @override
  Widget surface() => const ColoredBox(color: Colors.black);
  @override
  Future<void> open(
    MediaItem item, {
    String? url,
    Duration start = Duration.zero,
  }) async {}
  @override
  Future<void> toggle() async {
    playing = !playing;
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
  }

  @override
  Future<void> volume(double value) async {}
  @override
  Future<void> close() async {}
}

void main() {
  Future<TestEngine> mount(WidgetTester tester, {bool live = false}) async {
    final engine = TestEngine()
      ..duration = const Duration(seconds: 100)
      ..playing = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoStage(
            item: MediaItem(
              id: 'test',
              sourceId: 's',
              name: 'Test',
              url: '',
              kind: live ? MediaKind.live : MediaKind.movie,
            ),
            engine: engine,
            opening: false,
            problem: null,
            multi: false,
            frameRate: false,
            onRetry: () {},
            onFavorite: () {},
            onEngine: (_) async {},
            onFrameRate: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    return engine;
  }

  testWidgets(
    'Video click toggles, arrows seek, digits jump, and forward button works',
    (tester) async {
      final engine = await mount(tester);
      await tester.tapAt(const Offset(400, 250));
      expect(engine.playing, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      expect(engine.position.inSeconds, 50);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.position.inSeconds, 60);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(engine.position.inSeconds, 50);
      await tester.tap(find.byTooltip('Forward 10 seconds'));
      expect(engine.position.inSeconds, 60);
      expect(engine.playing, false); // button click must not also toggle video
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(engine.position, Duration.zero);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.position, engine.duration);
      await tester.pumpWidget(const SizedBox());
      engine.dispose();
    },
  );
  testWidgets(
    'Live video can pause but seek shortcuts do not jump the stream',
    (tester) async {
      final engine = await mount(tester, live: true);
      await tester.tapAt(const Offset(400, 250));
      expect(engine.playing, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(engine.position, Duration.zero);
      expect(find.byTooltip('Forward 10 seconds'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      engine.dispose();
    },
  );
}
