import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/audit_service.dart';

class AdminBurialRecordsScreen extends ConsumerStatefulWidget {
  const AdminBurialRecordsScreen({super.key});

  @override
  ConsumerState<AdminBurialRecordsScreen> createState() => _AdminBurialRecordsScreenState();
}

class _AdminBurialRecordsScreenState extends ConsumerState<AdminBurialRecordsScreen> {
  List<Map<String, dynamic>> _burialRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  
  // Form controllers for add/edit
  final _nameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();
  String? _selectedLotId;
  List<Map<String, dynamic>> _availableLots = [];
  
  // Error messages for validation
  String? _nameError;
  String? _deathDateError;
  String? _birthDateError;
  String? _lotError;
  
  bool _isEditing = false;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthDateController.dispose();
    _deathDateController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      
      final records = await supabase
          .from('burial_record')
          .select('''
            *,
            cemetery_lot (
              lot_id,
              lot_number,
              section:section_id (
                name
              )
            )
          ''')
          .order('death_date', ascending: false);
      
      final lots = await supabase
          .from('cemetery_lot')
          .select('lot_id, lot_number, section:section_id(name), status');
      
      setState(() {
        _burialRecords = List<Map<String, dynamic>>.from(records);
        _filteredRecords = List<Map<String, dynamic>>.from(records);
        _availableLots = List<Map<String, dynamic>>.from(lots);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  bool _isValidDateFormat(String dateStr) {
    if (dateStr.isEmpty) return true;
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(dateStr)) return false;
    
    final date = _parseDate(dateStr);
    if (date == null) return false;
    
    if (date.year < 1900 || date.year > DateTime.now().year + 1) return false;
    
    return true;
  }

  void _showValidationErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _validateForm() {
    setState(() {
      _nameError = null;
      _deathDateError = null;
      _birthDateError = null;
      _lotError = null;
    });
    
    if (_nameController.text.trim().isEmpty) {
      _showValidationErrorDialog('Missing Information', 'Please enter the name of the deceased.');
      setState(() => _nameError = 'Name of deceased is required');
      return false;
    }
    
    final deathDateStr = _deathDateController.text;
    if (deathDateStr.isEmpty) {
      _showValidationErrorDialog('Missing Information', 'Death date is required.');
      setState(() => _deathDateError = 'Death date is required');
      return false;
    }
    
    if (!_isValidDateFormat(deathDateStr)) {
      _showValidationErrorDialog(
        'Invalid Date Format', 
        'Death date must be in YYYY-MM-DD format.\nExample: 2024-05-10'
      );
      setState(() => _deathDateError = 'Invalid date format or value');
      return false;
    }
    
    final deathDate = _parseDate(deathDateStr)!;
    if (deathDate.isAfter(DateTime.now())) {
      _showValidationErrorDialog('Invalid Date', 'Death date cannot be in the future.');
      setState(() => _deathDateError = 'Death date cannot be in the future');
      return false;
    }
    
    final birthDateStr = _birthDateController.text;
    DateTime? birthDate;
    if (birthDateStr.isNotEmpty) {
      if (!_isValidDateFormat(birthDateStr)) {
        _showValidationErrorDialog(
          'Invalid Date Format', 
          'Birth date must be in YYYY-MM-DD format.\nExample: 1950-01-15'
        );
        setState(() => _birthDateError = 'Invalid date format or value');
        return false;
      }
      
      birthDate = _parseDate(birthDateStr)!;
      if (birthDate.isAfter(DateTime.now())) {
        _showValidationErrorDialog('Invalid Date', 'Birth date cannot be in the future.');
        setState(() => _birthDateError = 'Birth date cannot be in the future');
        return false;
      }
      
      if (deathDate.isBefore(birthDate)) {
        _showValidationErrorDialog(
          'Invalid Date Relationship', 
          'Death date cannot be earlier than birth date.'
        );
        setState(() => _deathDateError = 'Death date must be after birth date');
        setState(() => _birthDateError = 'Birth date must be before death date');
        return false;
      }
    }
    
    if (_selectedLotId == null) {
      _showValidationErrorDialog('Missing Information', 'Please select a cemetery lot.');
      setState(() => _lotError = 'Please select a cemetery lot');
      return false;
    }
    
    return true;
  }

  void _filterRecords(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredRecords = List.from(_burialRecords);
      } else {
        _filteredRecords = _burialRecords.where((record) {
          final name = record['name_of_deceased']?.toLowerCase() ?? '';
          final lotNumber = record['cemetery_lot']?['lot_number']?.toLowerCase() ?? '';
          return name.contains(query.toLowerCase()) || 
                 lotNumber.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _showAddEditDialog([Map<String, dynamic>? record]) async {
    _isEditing = record != null;
    
    _nameError = null;
    _deathDateError = null;
    _birthDateError = null;
    _lotError = null;
    
    // Store the original lot ID for editing
    String? originalLotId;
    
    if (record != null) {
      _editingId = record['burial_id'].toString();
      _nameController.text = record['name_of_deceased'] ?? '';
      _birthDateController.text = record['birth_date'] != null 
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(record['birth_date']))
          : '';
      _deathDateController.text = record['death_date'] != null
          ? DateFormat('yyyy-MM-dd').format(DateTime.parse(record['death_date']))
          : '';
      originalLotId = record['lot_id']?.toString();
      _selectedLotId = originalLotId;
    } else {
      _editingId = null;
      _nameController.clear();
      _birthDateController.clear();
      _deathDateController.clear();
      _selectedLotId = null;
    }

    final supabase = Supabase.instance.client;
    
    // Get all lots (including occupied ones for editing)
    List<Map<String, dynamic>> allLots;
    if (_isEditing) {
      // For editing, get all lots so we can show the currently selected one
      allLots = await supabase
          .from('cemetery_lot')
          .select('lot_id, lot_number, section:section_id(name), status');
    } else {
      // For adding, only show available lots
      allLots = await supabase
          .from('cemetery_lot')
          .select('lot_id, lot_number, section:section_id(name), status')
          .eq('status', 'Available');
    }
    _availableLots = List<Map<String, dynamic>>.from(allLots);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(_isEditing ? Icons.edit : Icons.person_add, 
                     color: const Color(0xFF4B6E4F)),
                const SizedBox(width: 8),
                Text(_isEditing ? 'Edit Burial Record' : 'Add Burial Record'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Name of Deceased *',
                      border: const OutlineInputBorder(),
                      errorText: _nameError,
                      prefixIcon: const Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _birthDateController,
                    decoration: InputDecoration(
                      labelText: 'Birth Date (YYYY-MM-DD)',
                      hintText: 'Optional',
                      border: const OutlineInputBorder(),
                      errorText: _birthDateError,
                      helperText: 'Example: 1950-01-15',
                      prefixIcon: const Icon(Icons.cake),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _deathDateController,
                    decoration: InputDecoration(
                      labelText: 'Death Date (YYYY-MM-DD) *',
                      border: const OutlineInputBorder(),
                      errorText: _deathDateError,
                      helperText: 'Example: 2024-05-10',
                      prefixIcon: const Icon(Icons.calendar_today),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<String>(
                    value: _selectedLotId,
                    decoration: InputDecoration(
                      labelText: 'Cemetery Lot *',
                      border: const OutlineInputBorder(),
                      errorText: _lotError,
                      prefixIcon: const Icon(Icons.location_on),
                    ),
                    items: [
                      if (_selectedLotId == null)
                        const DropdownMenuItem(value: null, child: Text('Select a lot')),
                      ..._availableLots.map((lot) {
                        final lotNumber = lot['lot_number'] ?? 'N/A';
                        final sectionName = lot['section']?['name'] ?? 'N/A';
                        final status = lot['status'] ?? 'Available';
                        return DropdownMenuItem(
                          value: lot['lot_id'].toString(),
                          child: Text('Lot $lotNumber - Section $sectionName${_isEditing && status != 'Available' ? ' (Currently Occupied)' : ''}'),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedLotId = value;
                        _lotError = null;
                      });
                    },
                  ),
                  
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Death date must be after birth date and cannot be in the future.',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_validateForm()) {
                    Navigator.pop(context);
                    await _saveRecord();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4B6E4F),
                  foregroundColor: Colors.white,
                ),
                child: Text(_isEditing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveRecord() async {
  if (!_validateForm()) return;

  setState(() => _isLoading = true);

  try {
    final supabase = Supabase.instance.client;
    final data = {
      'name_of_deceased': _nameController.text.trim(),
      'birth_date': _birthDateController.text.isEmpty ? null : _birthDateController.text,
      'death_date': _deathDateController.text,
      'lot_id': int.parse(_selectedLotId!),
    };

    if (_isEditing && _editingId != null) {
      await supabase.from('burial_record').update(data).eq('burial_id', int.parse(_editingId!));
      
      await AuditService.log(
        action: 'UPDATE',
        entityType: 'burial',
        entityId: _editingId,
        details: 'Updated burial for ${_nameController.text.trim()}',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record updated!'), backgroundColor: Colors.green),
      );
    } else {
      final result = await supabase.from('burial_record').insert(data).select();
      final newId = result.first['burial_id'].toString();
      
      await supabase.from('cemetery_lot').update({'status': 'Occupied'}).eq('lot_id', int.parse(_selectedLotId!));
      
      await AuditService.log(
        action: 'CREATE',
        entityType: 'burial',
        entityId: newId,
        details: 'Created burial for ${_nameController.text.trim()}',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record added!'), backgroundColor: Colors.green),
      );
    }
    
    await _loadData();
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}

  Future<void> _deleteRecord(String id, String name) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Record'),
      content: Text('Delete $name?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ),
  );

  if (confirm == true) {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final record = await supabase.from('burial_record').select('lot_id').eq('burial_id', int.parse(id)).single();
      await supabase.from('burial_record').delete().eq('burial_id', int.parse(id));
      if (record['lot_id'] != null) {
        await supabase.from('cemetery_lot').update({'status': 'Available'}).eq('lot_id', record['lot_id']);
      }
      
      await AuditService.log(
        action: 'DELETE',
        entityType: 'burial',
        entityId: id,
        details: 'Deleted burial for $name',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record deleted!'), backgroundColor: Colors.green),
      );
      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, y').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Burial Records'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color(0xFF4B6E4F),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name or lot number...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onChanged: _filterRecords,
                      ),
                    ),
                    Expanded(
                      child: _filteredRecords.isEmpty
                          ? const Center(child: Text('No records found'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredRecords.length,
                              itemBuilder: (context, index) {
                                final record = _filteredRecords[index];
                                final lot = record['cemetery_lot'] ?? {};
                                final section = lot['section'] ?? {};
                                final deathDate = _formatDate(record['death_date']);
                                final birthDate = _formatDate(record['birth_date']);
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF4B6E4F).withOpacity(0.1),
                                      child: const Icon(Icons.person, color: Color(0xFF4B6E4F)),
                                    ),
                                    title: Text(
                                      record['name_of_deceased'] ?? 'Unknown',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Lot ${lot['lot_number'] ?? 'N/A'} • Section ${section['name'] ?? 'N/A'}'),
                                        Text('Died: $deathDate${birthDate != 'N/A' ? ' • Born: $birthDate' : ''}'),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                          onPressed: () => _showAddEditDialog(record),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => _deleteRecord(
                                            record['burial_id'].toString(),
                                            record['name_of_deceased'] ?? 'this record',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage!),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4B6E4F),
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}