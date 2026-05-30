import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/audit_service.dart';

class AdminBurialRecordsScreen extends ConsumerStatefulWidget {
  const AdminBurialRecordsScreen({
    super.key,
    this.onMenuPressed,
    this.onLogoutPressed,
  });

  final VoidCallback? onMenuPressed;
  final VoidCallback? onLogoutPressed;

  @override
  ConsumerState<AdminBurialRecordsScreen> createState() => _AdminBurialRecordsScreenState();
}

class _AdminBurialRecordsScreenState extends ConsumerState<AdminBurialRecordsScreen> {
  List<Map<String, dynamic>> _burialRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  bool _isLoading = true;
  String? _errorMessage;
  
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

  InputDecoration _recordFieldDecoration({
    required String labelText,
    required IconData icon,
    String? hintText,
    String? helperText,
    String? errorText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: Icon(icon, color: const Color(0xFF335538)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFC2C8BF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFC2C8BF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF335538), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.4),
      ),
    );
  }

  void _showValidationErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFBF9F6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFDAD6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.error_outline, color: Color(0xFFBA1A1A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF335538),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
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

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFFBF9F6),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC5EDC6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _isEditing ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
                    color: const Color(0xFF335538),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Burial Record' : 'Add Burial Record',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: _recordFieldDecoration(
                      labelText: 'Name of Deceased *',
                      errorText: _nameError,
                      icon: Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _birthDateController,
                    decoration: _recordFieldDecoration(
                      labelText: 'Birth Date (YYYY-MM-DD)',
                      hintText: 'Optional',
                      errorText: _birthDateError,
                      helperText: 'Example: 1950-01-15',
                      icon: Icons.cake_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _deathDateController,
                    decoration: _recordFieldDecoration(
                      labelText: 'Death Date (YYYY-MM-DD) *',
                      errorText: _deathDateError,
                      helperText: 'Example: 2024-05-10',
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<String>(
                    initialValue: _selectedLotId,
                    decoration: _recordFieldDecoration(
                      labelText: 'Cemetery Lot *',
                      errorText: _lotError,
                      icon: Icons.location_on_outlined,
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC7E4F3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Color(0xFF2F4A57),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Death date must be after birth date and cannot be in the future.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2F4A57),
                              height: 1.3,
                            ),
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
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF424841),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
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
                  backgroundColor: const Color(0xFF335538),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      
      if (!mounted) return;
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
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record added!'), backgroundColor: Colors.green),
      );
    }
    
    await _loadData();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
    );
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<void> _deleteRecord(String id, String name) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFFFBF9F6),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFDAD6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFBA1A1A)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Delete Record',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text('Delete $name?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF424841),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFBA1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: const Text('Delete'),
        ),
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
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record deleted!'), backgroundColor: Colors.green),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      backgroundColor: const Color(0xFFFBF9F6),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderSection(),
                        const SizedBox(height: 24),
                        _buildSearchFilterBar(),
                        const SizedBox(height: 24),
                        _filteredRecords.isEmpty
                            ? _buildEmptyState()
                            : Column(
                                children: [
                                  ...List.generate(
                                    _filteredRecords.length,
                                    (index) => Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index == _filteredRecords.length - 1 ? 0 : 16,
                                      ),
                                      child: _buildRecordCard(_filteredRecords[index]),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Center(
                                    child: OutlinedButton(
                                      onPressed: _loadData,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF1B1C1A),
                                        side: const BorderSide(color: Color(0xFFC2C8BF)),
                                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                        shape: const StadiumBorder(),
                                      ),
                                      child: const Text('Load More Records'),
                                    ),
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Burial Records',
                style: TextStyle(
                  color: Color(0xFF335538),
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage and organize historical and current interment data.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.58),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: () => _showAddEditDialog(),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF335538),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add New Burial'),
        ),
      ],
    );
  }

  Widget _buildSearchFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3F0),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or lot',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: Color(0xFFC2C8BF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: Color(0xFFC2C8BF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: Color(0xFF335538), width: 1.4),
                ),
              ),
              onChanged: _filterRecords,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFC7E4F3),
              foregroundColor: const Color(0xFF2F4A57),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.filter_list_rounded),
            label: const Text('Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
      ),
      child: const Text(
        'No records found',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF424841),
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final lot = record['cemetery_lot'] ?? {};
    final section = lot['section'] ?? {};
    final deathDate = _formatDate(record['death_date']);
    final birthDate = _formatDate(record['birth_date']);
    final initials = _recordInitials(record['name_of_deceased'] ?? 'Unknown');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E2DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFC5EDC6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xFF2C4E32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['name_of_deceased'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Color(0xFF1B1C1A),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.calendar_today_rounded,
                          label: 'Born: $birthDate',
                          color: const Color(0xFF47626F),
                        ),
                        _InfoChip(
                          icon: Icons.event_busy_rounded,
                          label: 'Died: $deathDate',
                          color: const Color(0xFF5A4B3F),
                        ),
                        _InfoChip(
                          icon: Icons.location_on_rounded,
                          label: 'Lot ${lot['lot_number'] ?? 'N/A'} • Section ${section['name'] ?? 'N/A'}',
                          color: const Color(0xFF335538),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                IconButton(
                  onPressed: () => _showAddEditDialog(record),
                  icon: const Icon(Icons.edit_rounded),
                  tooltip: 'Edit',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF5F3F0),
                    foregroundColor: const Color(0xFF47626F),
                  ),
                ),
                IconButton(
                  onPressed: () => _deleteRecord(
                    record['burial_id'].toString(),
                    record['name_of_deceased'] ?? 'this record',
                  ),
                  icon: const Icon(Icons.delete_rounded),
                  tooltip: 'Delete',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFFFDAD6),
                    foregroundColor: const Color(0xFFBA1A1A),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_vert_rounded),
                  tooltip: 'More',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF5F3F0),
                    foregroundColor: const Color(0xFF727971),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _recordInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

