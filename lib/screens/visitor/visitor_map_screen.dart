import 'package:flutter/material.dart';

import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

class VisitorMapScreen extends StatelessWidget {
  const VisitorMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Cemetery Map',
            subtitle: 'PNG overlay + tappable lots + route drawing (next).',
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.15,
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Map canvas placeholder',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black54),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: FilledButton.tonalIcon(
                      onPressed: () {},
                      icon: const Icon(Icons.layers_outlined),
                      label: const Text('Legend'),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.alt_route_rounded),
                      label: const Text('Route'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Lot status colors'),
                SizedBox(height: 10),
                _LegendRow(color: Color(0xFF2E7D32), label: 'Available'),
                SizedBox(height: 8),
                _LegendRow(color: Color(0xFFC62828), label: 'Occupied'),
                SizedBox(height: 8),
                _LegendRow(color: Color(0xFFEF6C00), label: 'High Demand'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

