import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'visitor_qr_with_grave_screen.dart';

class VisitorSearchScreen extends ConsumerStatefulWidget {
  const VisitorSearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<VisitorSearchScreen> createState() => _VisitorSearchScreenState();
}

class _VisitorSearchScreenState extends ConsumerState<VisitorSearchScreen> {
  late final TextEditingController _queryCtrl;
  String _query = '';
  List<Map<String, dynamic>> _allGraves = [];
  List<Map<String, dynamic>> _filteredGraves = [];
  bool _isLoading = true;
  String _searchType = 'name'; // name, lot, section

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    _queryCtrl = TextEditingController(text: initial);
    _query = initial;
    _loadAllGraves();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllGraves() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      
      // Load all burial records with lot and section info
      final allBurials = await supabase
          .from('burial_record')
          .select('''
            burial_id,
            name_of_deceased,
            birth_date,
            death_date,
            burial_date,
            lot_id,
            cemetery_lot!inner (
              lot_id,
              lot_number,
              status,
              section:section_id (
                section_id,
                name,
                branch:branch_id (name)
              )
            )
          ''')
          .order('name_of_deceased');
      
      setState(() {
        _allGraves = List<Map<String, dynamic>>.from(allBurials);
        _filteredGraves = List<Map<String, dynamic>>.from(allBurials);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading graves: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _filterGraves(String query) {
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _filteredGraves = List.from(_allGraves);
      } else {
        _filteredGraves = _allGraves.where((grave) {
          final name = grave['name_of_deceased']?.toLowerCase() ?? '';
          final lotNumber = grave['cemetery_lot']?['lot_number']?.toLowerCase() ?? '';
          final sectionName = grave['cemetery_lot']?['section']?['name']?.toLowerCase() ?? '';
          
          if (_searchType == 'name') {
            return name.contains(query.toLowerCase());
          } else if (_searchType == 'lot') {
            return lotNumber.contains(query.toLowerCase());
          } else {
            return sectionName.contains(query.toLowerCase());
          }
        }).toList();
      }
    });
  }

  void _generateQRForGrave(Map<String, dynamic> burial, Map<String, dynamic> lot, Map<String, dynamic> section) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitorQrWithGraveScreen(
          burialId: burial['burial_id'],
          deceasedName: burial['name_of_deceased'],
          lotNumber: lot['lot_number'],
          sectionName: section['name'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Graves'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllGraves,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search bar and filter
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _queryCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search by ${_searchType == 'name' ? 'name' : _searchType == 'lot' ? 'lot number' : 'section'}...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _query.isEmpty ? null : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _queryCtrl.clear();
                                _filterGraves('');
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onChanged: _filterGraves,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: DropdownButton<String>(
                          value: _searchType,
                          items: const [
                            DropdownMenuItem(value: 'name', child: Text('Name')),
                            DropdownMenuItem(value: 'lot', child: Text('Lot #')),
                            DropdownMenuItem(value: 'section', child: Text('Section')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _searchType = value!;
                              _filterGraves(_query);
                            });
                          },
                          underline: const SizedBox(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Results count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_filteredGraves.length} graves found',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Graves list
                Expanded(
                  child: _filteredGraves.isEmpty
                      ? const Center(child: Text('No graves found'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filteredGraves.length,
                          itemBuilder: (context, index) {
                            final grave = _filteredGraves[index];
                            final lot = grave['cemetery_lot'] ?? {};
                            final section = lot['section'] ?? {};
                            final branch = section['branch'] ?? {};
                            final deathDate = grave['death_date'] != null
                                ? DateFormat('MMM d, y').format(DateTime.parse(grave['death_date']))
                                : 'Unknown';
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF4B6E4F).withOpacity(0.1),
                                      child: Icon(Icons.person, color: const Color(0xFF4B6E4F)),
                                    ),
                                    title: Text(
                                      grave['name_of_deceased'] ?? 'Unknown',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Lot ${lot['lot_number']} • ${section['name']} • ${branch['name']}'),
                                        Text('Died: $deathDate'),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF4B6E4F)),
                                    onTap: () => _showGraveDetails(grave, lot, section, branch),
                                  ),
                                  // QR Code Button
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                    child: ElevatedButton.icon(
                                      onPressed: () => _generateQRForGrave(grave, lot, section),
                                      icon: const Icon(Icons.qr_code, size: 18),
                                      label: const Text('Generate QR Code for this Grave'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4B6E4F),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(double.infinity, 40),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
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

  void _showGraveDetails(Map<String, dynamic> burial, Map<String, dynamic> lot, 
      Map<String, dynamic> section, Map<String, dynamic> branch) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              burial['name_of_deceased'] ?? 'Unknown',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.location_on, 'Lot ${lot['lot_number']}'),
            _buildInfoRow(Icons.map, 'Section: ${section['name']}'),
            _buildInfoRow(Icons.store, 'Branch: ${branch['name']}'),
            if (burial['death_date'] != null)
              _buildInfoRow(Icons.calendar_today, 'Died: ${DateFormat('MMM d, y').format(DateTime.parse(burial['death_date']))}'),
            if (burial['burial_date'] != null)
              _buildInfoRow(Icons.calendar_today, 'Buried: ${DateFormat('MMM d, y').format(DateTime.parse(burial['burial_date']))}'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _generateQRForGrave(burial, lot, section);
                },
                icon: const Icon(Icons.qr_code),
                label: const Text('Generate QR Code'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4B6E4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}