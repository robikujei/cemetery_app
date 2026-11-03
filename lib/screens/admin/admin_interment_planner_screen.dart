import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminIntermentPlannerScreen extends StatefulWidget {
  const AdminIntermentPlannerScreen({super.key});
  @override
  State<AdminIntermentPlannerScreen> createState() => _Planner();
}

class _Planner extends State<AdminIntermentPlannerScreen> {
  DateTime week = DateTime.now();
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  DateTime get monday => DateTime(
    week.year,
    week.month,
    week.day,
  ).subtract(Duration(days: week.weekday - 1));
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final r = await Supabase.instance.client
          .from('interment_schedule')
          .select(
            'schedule_id,lot_id,deceased_name,scheduled_at,cemetery_lot(lot_number,block_number)',
          )
          .gte('scheduled_at', monday.toIso8601String())
          .lt(
            'scheduled_at',
            monday.add(const Duration(days: 7)).toIso8601String(),
          )
          .order('scheduled_at');
      if (mounted) setState(() => items = List<Map<String, dynamic>>.from(r));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> add() async {
    final n = TextEditingController(),
        b = TextEditingController(),
        l = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Schedule interment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: n,
              decoration: const InputDecoration(labelText: 'Deceased name'),
            ),
            TextField(
              controller: b,
              decoration: const InputDecoration(labelText: 'Block'),
            ),
            TextField(
              controller: l,
              decoration: const InputDecoration(labelText: 'Lot number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Schedule today'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final lot = await Supabase.instance.client
        .from('cemetery_lot')
        .select('lot_id')
        .eq('block_number', b.text.trim())
        .eq('lot_number', l.text.trim())
        .maybeSingle();
    if (lot == null) throw Exception('Lot not found');
    await Supabase.instance.client.from('interment_schedule').insert({
      'lot_id': lot['lot_id'],
      'deceased_name': n.text.trim(),
      'scheduled_at': DateTime.now().toUtc().toIso8601String(),
    });
    await load();
  }

  @override
  Widget build(BuildContext c) {
    final ds = List.generate(7, (i) => monday.add(Duration(days: i)));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('Add schedule'),
      ),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(
                    () => week = monday.subtract(const Duration(days: 7)),
                  );
                  load();
                },
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMd().format(monday),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => week = monday.add(const Duration(days: 7)));
                  load();
                },
              ),
            ],
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      for (final d in ds)
                        Expanded(
                          child: Column(
                            children: [
                              Text(DateFormat.E().format(d)),
                              Expanded(
                                child: ListView(
                                  children: items
                                      .where((x) {
                                        final q = DateTime.parse(
                                          x['scheduled_at'],
                                        ).toLocal();
                                        return q.year == d.year &&
                                            q.month == d.month &&
                                            q.day == d.day;
                                      })
                                      .map(
                                        (x) => Card(
                                          child: Text(
                                            '${x['deceased_name']}\n${x['cemetery_lot']}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
