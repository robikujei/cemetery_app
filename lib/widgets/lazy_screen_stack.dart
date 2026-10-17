import 'package:flutter/material.dart';

/// Mount screens on first use, preserving forms and map state on return.
class LazyScreenStack extends StatefulWidget {
  const LazyScreenStack({
    super.key,
    required this.index,
    required this.children,
  });
  final int index;
  final List<Widget> children;

  @override
  State<LazyScreenStack> createState() => _LazyScreenStackState();
}

class _LazyScreenStackState extends State<LazyScreenStack> {
  final _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _visited.contains(i)
              ? TickerMode(
                  enabled: i == widget.index,
                  child: RepaintBoundary(child: widget.children[i]),
                )
              : const SizedBox.shrink(),
      ],
    );
  }
}
