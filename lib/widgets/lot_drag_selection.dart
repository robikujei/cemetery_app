import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Coordinates are local to the map-sized overlay. Works in any drag direction.
class LotDragSelection extends StatefulWidget {
  const LotDragSelection({super.key, required this.onSelected});
  final ValueChanged<Rect> onSelected;

  @override
  State<LotDragSelection> createState() => _LotDragSelectionState();
}

class _LotDragSelectionState extends State<LotDragSelection> {
  Offset? _start;
  Offset? _end;

  @override
  Widget build(BuildContext context) {
    final rect = _start == null || _end == null
        ? null
        : Rect.fromPoints(_start!, _end!);
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => setState(() {
          _start = details.localPosition;
          _end = _start;
        }),
        onPanUpdate: (details) => setState(() => _end = details.localPosition),
        onPanCancel: () => setState(() {
          _start = null;
          _end = null;
        }),
        onPanEnd: (_) {
          if (_start != null && _end != null) {
            final area = Rect.fromPoints(_start!, _end!);
            if (area.width >= 4 && area.height >= 4) widget.onSelected(area);
          }
          setState(() {
            _start = null;
            _end = null;
          });
        },
        child: Stack(
          children: [
            const Positioned.fill(child: SizedBox.expand()),
            if (rect != null)
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x3388CCFF),
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
