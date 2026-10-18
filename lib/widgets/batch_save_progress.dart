import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BatchSaveProgress extends StatelessWidget {
  const BatchSaveProgress({
    super.key,
    required this.progress,
    required this.minimized,
    required this.onToggleSize,
    required this.onStop,
  });

  final ValueListenable<String> progress;
  final bool minimized;
  final VoidCallback onToggleSize;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: EdgeInsets.all(minimized ? 12 : 24),
          child: ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (context, text, child) => minimized
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Flexible(child: Text(text)),
                      IconButton(
                        tooltip: 'Expand save progress',
                        onPressed: onToggleSize,
                        icon: const Icon(Icons.open_in_full),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(text, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: onToggleSize,
                            icon: const Icon(Icons.minimize),
                            label: const Text('Minimize'),
                          ),
                          TextButton(
                            onPressed: onStop,
                            child: const Text('Stop after current group'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
