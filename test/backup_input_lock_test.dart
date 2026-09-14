import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen_iptv/ui/backup_input_lock.dart';

void main() {
  testWidgets('Backup lock blocks focused controls and restores interaction', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var busy = false;
    var activations = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, set) {
            update = set;
            return Scaffold(
              body: BackupInputLock(
                busy: busy,
                child: TextButton(
                  focusNode: focus,
                  onPressed: () => activations++,
                  child: const Text('Change library'),
                ),
              ),
            );
          },
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, true);
    update(() => busy = true);
    await tester.pump();
    expect(focus.hasFocus, false);
    for (final key in [
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.goBack,
    ]) {
      await tester.sendKeyEvent(
        key,
        physicalKey: key == LogicalKeyboardKey.goBack
              ? PhysicalKeyboardKey.escape
            : null,
      );
      await tester.pump();
    }
    await tester.tap(find.text('Change library'), warnIfMissed: false);
    expect(activations, 0);
    expect(focus.hasFocus, false);
    update(() => busy = false);
    await tester.pump();
    await tester.tap(find.text('Change library'));
    expect(activations, 1);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, true);
  });
}
