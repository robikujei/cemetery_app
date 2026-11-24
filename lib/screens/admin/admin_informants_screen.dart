import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminInformantsScreen extends StatefulWidget {
  const AdminInformantsScreen({super.key});

  @override
  State<AdminInformantsScreen> createState() => _AdminInformantsScreenState();
}

class _AdminInformantsScreenState extends State<AdminInformantsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  static const _pageSize = 100;
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([int? requestedPage]) async {
    final page = requestedPage ?? _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final total = await db.from('burial_informants').count();
      final rows = await db
          .from('burial_informants')
          .select(
            'informant_id,full_name,address,work,cellphone_no,id_presented,id_number,place_issued',
          )
          .order('full_name')
          .range(page * _pageSize, page * _pageSize + _pageSize - 1);
      if (mounted)
        setState(() {
          _items = List<Map<String, dynamic>>.from(rows);
          _total = total;
          _page = page;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _loading = false;
        });
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final name = TextEditingController(
      text: item?['full_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: item?['cellphone_no']?.toString() ?? '',
    );
    final address = TextEditingController(
      text: item?['address']?.toString() ?? '',
    );
    final work = TextEditingController(text: item?['work']?.toString() ?? '');
    final idPresented = TextEditingController(
      text: item?['id_presented']?.toString() ?? '',
    );
    final idNumber = TextEditingController(
      text: item?['id_number']?.toString() ?? '',
    );
    final placeIssued = TextEditingController(
      text: item?['place_issued']?.toString() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Add informant' : 'Edit informant'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: 648,
                  child: TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Full name *'),
                  ),
                ),
                SizedBox(
                  width: 316,
                  child: TextField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Cellphone number',
                    ),
                  ),
                ),
                SizedBox(
                  width: 316,
                  child: TextField(
                    controller: work,
                    decoration: const InputDecoration(
                      labelText: 'Occupation / work',
                    ),
                  ),
                ),
                SizedBox(
                  width: 648,
                  child: TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address'),
                    maxLines: 2,
                  ),
                ),
                SizedBox(
                  width: 206,
                  child: TextField(
                    controller: idPresented,
                    decoration: const InputDecoration(
                      labelText: 'ID presented',
                    ),
                  ),
                ),
                SizedBox(
                  width: 206,
                  child: TextField(
                    controller: idNumber,
                    decoration: const InputDecoration(labelText: 'ID number'),
                  ),
                ),
                SizedBox(
                  width: 206,
                  child: TextField(
                    controller: placeIssued,
                    decoration: const InputDecoration(
                      labelText: 'Place issued',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final fullName = name.text.trim();
    final cellphone = phone.text.trim();
    final location = address.text.trim();
    final occupation = work.text.trim();
    final idType = idPresented.text.trim();
    final number = idNumber.text.trim();
    final issuer = placeIssued.text.trim();
    name.dispose();
    phone.dispose();
    address.dispose();
    work.dispose();
    idPresented.dispose();
    idNumber.dispose();
    placeIssued.dispose();
    if (saved != true || fullName.isEmpty) return;
    try {
      final db = Supabase.instance.client;
      final duplicate = await db
          .from('burial_informants')
          .select('informant_id')
          .ilike('full_name', fullName)
          .limit(1)
          .maybeSingle();
      if (duplicate != null &&
          duplicate['informant_id'].toString() !=
              item?['informant_id'].toString())
        throw Exception('An informant with this name already exists.');
      final data = {
        'full_name': fullName,
        'cellphone_no': cellphone.isEmpty ? null : cellphone,
        'address': location.isEmpty ? null : location,
        'work': occupation.isEmpty ? null : occupation,
        'id_presented': idType.isEmpty ? null : idType,
        'id_number': number.isEmpty ? null : number,
        'place_issued': issuer.isEmpty ? null : issuer,
      };
      if (item == null) {
        await db.from('burial_informants').insert(data);
      } else {
        await db
            .from('burial_informants')
            .update(data)
            .eq('informant_id', item['informant_id']);
      }
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save informant: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = _items
        .where(
          (x) => '${x['full_name']} ${x['cellphone_no']} ${x['address']}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Informant Editor',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add informant'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage shared informant profiles used by burial records.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, phone, or address',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const SizedBox(height: 12),
              Text('${shown.length} informant${shown.length == 1 ? '' : 's'}'),
              ...shown.map(
                (item) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.contact_page_outlined),
                    title: Text(item['full_name']?.toString() ?? 'Unnamed'),
                    subtitle: Text(
                      [item['cellphone_no'], item['address']]
                          .where((v) => v != null && v.toString().isNotEmpty)
                          .join(' · '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit informant',
                      onPressed: () => _edit(item),
                    ),
                  ),
                ),
              ),
              if (_total > _pageSize)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Showing ${_page * _pageSize + 1}–${((_page + 1) * _pageSize).clamp(0, _total)} of $_total',
                      ),
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _page == 0 ? null : () => _load(_page - 1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('Page ${_page + 1}'),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: (_page + 1) * _pageSize >= _total
                            ? null
                            : () => _load(_page + 1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
