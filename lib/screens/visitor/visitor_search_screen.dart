import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/grave_record.dart';
import '../../providers/mock_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/section_header.dart';

class VisitorSearchScreen extends ConsumerStatefulWidget {
  const VisitorSearchScreen({super.key, this.initialQuery});

  /// Prefills search when opened from the home search bar (Stitch behavior).
  final String? initialQuery;

  @override
  ConsumerState<VisitorSearchScreen> createState() => _VisitorSearchScreenState();
}

class _VisitorSearchScreenState extends ConsumerState<VisitorSearchScreen> {
  late final TextEditingController _queryCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    _queryCtrl = TextEditingController(text: initial);
    _query = initial;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(gravesProvider);
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? all
        : all
            .where(
              (g) =>
                  g.deceasedName.toLowerCase().contains(q) ||
                  g.lotNumber.toLowerCase().contains(q) ||
                  g.sectionName.toLowerCase().contains(q),
            )
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Grave Search',
            subtitle: 'Search by name, lot number, or section.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryCtrl,
            decoration: InputDecoration(
              labelText: 'Search',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => setState(() {
                        _queryCtrl.clear();
                        _query = '';
                      }),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ...results.map((g) => _GraveTile(grave: g)),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                'No matches found.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

class _GraveTile extends StatelessWidget {
  const _GraveTile({required this.grave});

  final GraveRecord grave;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, y');
    final dates = [
      if (grave.birthDate != null) 'Born ${fmt.format(grave.birthDate!)}',
      if (grave.deathDate != null) 'Died ${fmt.format(grave.deathDate!)}',
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.person_outline,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(grave.deceasedName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${grave.sectionName} • Lot ${grave.lotNumber}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                  if (dates.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(dates, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Open details for ${grave.lotNumber} (next).')),
                );
              },
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

