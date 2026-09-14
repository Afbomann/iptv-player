import 'package:flutter/material.dart';

/// Covers pointer, keyboard, remote activation, and accessibility input without
/// disposing the navigator or losing the page's state during an operation.
class BackupInputLock extends StatefulWidget {
  const BackupInputLock({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;

  @override
  State<BackupInputLock> createState() => _BackupInputLockState();
}

class _BackupInputLockState extends State<BackupInputLock> {
  final focus = FocusNode(debugLabel: 'Backup input lock');

  @override
  void didUpdateWidget(BackupInputLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) focus.requestFocus();
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    autofocus: widget.busy,
    skipTraversal: true,
    onKeyEvent: (_, _) =>
        widget.busy ? KeyEventResult.handled : KeyEventResult.ignored,
    child: ExcludeFocus(
      excluding: widget.busy,
      child: ExcludeSemantics(
        excluding: widget.busy,
        child: AbsorbPointer(absorbing: widget.busy, child: widget.child),
      ),
    ),
  );
}
