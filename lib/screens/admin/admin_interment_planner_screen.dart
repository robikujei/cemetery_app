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
      final client = Supabase.instance.client;
      final r = await client
          .from('interment_schedule')
          .select(
            'schedule_id,burial_id,lot_id,deceased_name,scheduled_at,status,cemetery_lot(lot_number,block_number)',
          )
          .gte('scheduled_at', monday.toIso8601String())
          .lt(
            'scheduled_at',
            monday.add(const Duration(days: 7)).toIso8601String(),
          )
          .order('scheduled_at');
      // Retain cancelled/completed items just long enough to stop the
      // burial-record fallback from recreating them in this view.
      final allScheduleItems = List<Map<String, dynamic>>.from(r);
      final scheduled = allScheduleItems
          .where((item) => item['status']?.toString() == 'scheduled')
          .toList();

      // Existing burial records are also a source of truth for planned future
      // interments. Include them automatically so the planner stays in sync
      // even when the record was created outside this screen.
      final burialRows = await client
          .from('burial_record')
          .select(
            'burial_id,name_of_deceased,interment_date,interment_time,lot_id,cemetery_lot(lot_number,block_number)',
          )
          .gte('interment_date', monday.toIso8601String().substring(0, 10))
          .lt(
            'interment_date',
            monday
                .add(const Duration(days: 7))
                .toIso8601String()
                .substring(0, 10),
          );
      final existingKeys = allScheduleItems.map((item) {
        final at = item['scheduled_at']?.toString() ?? '';
        return '${item['lot_id']}|${item['deceased_name']}|${at.substring(0, at.length >= 10 ? 10 : at.length)}';
      }).toSet();
      final synced = <Map<String, dynamic>>[...scheduled];
      for (final row in List<Map<String, dynamic>>.from(burialRows)) {
        final burialId = row['burial_id'];
        final date = row['interment_date']?.toString();
        if (date == null || date.isEmpty) continue;
        final name = row['name_of_deceased'] ?? 'Unnamed interment';
        final key = '${row['lot_id']}|$name|${date.substring(0, 10)}';
        if (existingKeys.contains(key)) continue;
        final time = row['interment_time']?.toString();
        final scheduledAt = DateTime.parse(
          time == null || time.isEmpty
              ? '${date}T00:00:00Z'
              : '${date}T${time}Z',
        );
        synced.add({
          'schedule_id': 'burial-$burialId',
          'burial_id': burialId,
          'lot_id': row['lot_id'],
          'deceased_name': name,
          'scheduled_at': scheduledAt.toIso8601String(),
          'cemetery_lot': row['cemetery_lot'],
          'from_burial_record': true,
        });
      }
      synced.sort(
        (a, b) => DateTime.parse(
          a['scheduled_at'].toString(),
        ).compareTo(DateTime.parse(b['scheduled_at'].toString())),
      );
      if (mounted) setState(() => items = synced);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> add() async {
    final n = TextEditingController(),
        b = TextEditingController(),
        l = TextEditingController();
    var scheduledAt = DateTime.now().add(const Duration(hours: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule interment'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: n,
                    decoration: const InputDecoration(
                      labelText: 'Deceased name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: b,
                    decoration: const InputDecoration(labelText: 'Block'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: l,
                    decoration: const InputDecoration(labelText: 'Lot number'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Schedule details',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Date'),
                    subtitle: Text(DateFormat.yMMMMd().format(scheduledAt)),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: scheduledAt,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 5),
                        ),
                      );
                      if (selected == null) return;
                      setDialogState(() {
                        scheduledAt = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                          scheduledAt.hour,
                          scheduledAt.minute,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time_outlined),
                    title: const Text('Time'),
                    subtitle: Text(DateFormat.jm().format(scheduledAt)),
                    onTap: () async {
                      final selected = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(scheduledAt),
                      );
                      if (selected == null) return;
                      setDialogState(() {
                        scheduledAt = DateTime(
                          scheduledAt.year,
                          scheduledAt.month,
                          scheduledAt.day,
                          selected.hour,
                          selected.minute,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Add to planner'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (n.text.trim().isEmpty ||
          b.text.trim().isEmpty ||
          l.text.trim().isEmpty) {
        throw Exception('Enter the deceased name, block, and lot number.');
      }
      final lot = await Supabase.instance.client
          .from('cemetery_lot')
          .select('lot_id')
          .eq('block_number', b.text.trim())
          .eq('lot_number', l.text.trim())
          .maybeSingle();
      if (lot == null) {
        throw Exception('Lot not found. Check the block and lot number.');
      }
      await Supabase.instance.client.from('interment_schedule').insert({
        'lot_id': lot['lot_id'],
        'deceased_name': n.text.trim(),
        'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(() => week = scheduledAt);
        await load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      n.dispose();
      b.dispose();
      l.dispose();
    }
  }

  Future<void> _deleteSchedule(Map<String, dynamic> item) async {
    final burialId = item['burial_id'];
    final fromBurialRecord = burialId != null ||
        item['from_burial_record'] == true ||
        item['schedule_id'].toString().startsWith('burial-');
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove interment schedule?'),
        content: Text(
          fromBurialRecord
              ? 'The burial record will be kept, but its interment date and time will be cleared so it no longer appears in the planner.'
              : 'This removes the planned interment from the planner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;

    try {
      final client = Supabase.instance.client;
      if (fromBurialRecord) {
        final id = int.tryParse(burialId?.toString() ?? '') ??
            int.tryParse(item['schedule_id'].toString().replaceFirst('burial-', ''));
        if (id == null) throw Exception('Linked burial record was not found.');
        // The burial record is the source of truth. The database trigger then
        // removes its linked planner row as well.
        await client
            .from('burial_record')
            .update({'interment_date': null, 'interment_time': null})
            .eq('burial_id', id);
      } else {
        await client
            .from('interment_schedule')
            .delete()
            .eq('schedule_id', item['schedule_id']);
      }
      if (mounted) await load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final ds = List.generate(7, (i) => monday.add(Duration(days: i)));
    final today = DateUtils.dateOnly(DateTime.now());
    final borderColor = Theme.of(c).colorScheme.outlineVariant;
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
                : Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        for (var index = 0; index < ds.length; index++)
                          Expanded(
                            child: _buildDayColumn(
                              ds[index],
                              isToday: DateUtils.isSameDay(ds[index], today),
                              showRightBorder: index < ds.length - 1,
                              borderColor: borderColor,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayColumn(
    DateTime day, {
    required bool isToday,
    required bool showRightBorder,
    required Color borderColor,
  }) {
    final scheduled = items.where((item) {
      final date = DateTime.parse(item['scheduled_at']).toLocal();
      return DateUtils.isSameDay(date, day);
    }).toList();
    return Container(
      decoration: BoxDecoration(
        border: showRightBorder
            ? Border(right: BorderSide(color: borderColor))
            : null,
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: isToday
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Column(
              children: [
                Text(DateFormat.E().format(day)),
                const SizedBox(height: 2),
                Text(
                  DateFormat.d().format(day),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: scheduled.isEmpty
                ? const SizedBox.expand()
                : ListView.separated(
                    padding: const EdgeInsets.all(6),
                    itemCount: scheduled.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 6),
                    itemBuilder: (_, index) {
                      final item = scheduled[index];
                      final time = DateFormat.jm().format(
                        DateTime.parse(item['scheduled_at']).toLocal(),
                      );
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                                child: Text(
                                  '$time\n${item['deceased_name']}',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove from planner',
                              onPressed: () => _deleteSchedule(item),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
