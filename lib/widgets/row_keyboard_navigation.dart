import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RowKeyboardNavigation extends StatelessWidget {
  const RowKeyboardNavigation({
    super.key,
    required this.focusNode,
    required this.enabled,
    required this.onDirection,
    required this.child,
  });
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<Offset> onDirection;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focusNode,
    onKeyEvent: (node, event) {
      // Text fields and other controls keep their own arrow-key behavior.
      if (!enabled ||
          !node.hasPrimaryFocus ||
          (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
        return KeyEventResult.ignored;
      }
      final direction = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
        LogicalKeyboardKey.arrowRight => const Offset(1, 0),
        LogicalKeyboardKey.arrowUp => const Offset(0, -1),
        LogicalKeyboardKey.arrowDown => const Offset(0, 1),
        _ => null,
      };
      if (direction == null) return KeyEventResult.ignored;
      onDirection(direction);
      return KeyEventResult.handled;
    },
    child: child,
  );
}
