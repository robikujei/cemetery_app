import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/audit_service.dart';

class AdminLotsScreen extends ConsumerStatefulWidget {
  const AdminLotsScreen({super.key});

  @override
  ConsumerState<AdminLotsScreen> createState() => _AdminLotsScreenState();
}

class _AdminLotsScreenState extends ConsumerState<AdminLotsScreen> {
  List<Map<String, dynamic>> _lots = [];
  List<Map<String, dynamic>> _filteredLots = [];
  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _filterSection = 'All';
  String _filterStatus = 'All';
  
  // Form controllers
  final _lotNumberController = TextEditingController();
  final _priceController = TextEditingController();
  final _xCoordController = TextEditingController();
  final _yCoordController = TextEditingController();
  String? _selectedSectionId;
  String? _selectedStatus;
  
  bool _isEditing = false;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _lotNumberController.dispose();
    _priceController.dispose();
    _xCoordController.dispose();
    _yCoordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      
      final sections = await supabase
          .from('section')
          .select('section_id, name');
      
      final lots = await supabase
          .from('cemetery_lot')
          .select('''
            *,
            section:section_id (
              section_id,
              name,
              branch:branch_id (name)
            )
          ''')
          .order('lot_number');
      
      final lotsWithBurial = <Map<String, dynamic>>[];
      for (var lot in lots) {
        final lotId = lot['lot_id'];
        
        final burialRecord = await supabase
            .from('burial_record')
            .select('burial_id, name_of_deceased, death_date')
            .eq('lot_id', lotId)
            .maybeSingle();
        
        var lotWithBurial = Map<String, dynamic>.from(lot);
        if (burialRecord != null) {
          lotWithBurial['burial_record'] = burialRecord;
        }
        lotsWithBurial.add(lotWithBurial);
      }
      
      setState(() {
        _sections = List<Map<String, dynamic>>.from(sections);
        _lots = lotsWithBurial;
        _filteredLots = List<Map<String, dynamic>>.from(lotsWithBurial);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredLots = _lots.where((lot) {
        final matchesSearch = _searchQuery.isEmpty ||
            lot['lot_number'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            lot['section']?['name']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) == true;
        
        final matchesSection = _filterSection == 'All' ||
            lot['section_id'].toString() == _filterSection;
        
        final matchesStatus = _filterStatus == 'All' ||
            lot['status'] == _filterStatus;
        
        return matchesSearch && matchesSection && matchesStatus;
      }).toList();
    });
  }

  Future<void> _showAddEditDialog([Map<String, dynamic>? lot]) async {
    _isEditing = lot != null;
    
    if (lot != null) {
      _editingId = lot['lot_id'].toString();
      _lotNumberController.text = lot['lot_number'] ?? '';
      _priceController.text = lot['price']?.toString() ?? '';
      _xCoordController.text = lot['x_coord']?.toString() ?? '';
      _yCoordController.text = lot['y_coord']?.toString() ?? '';
      _selectedSectionId = lot['section_id']?.toString();
      _selectedStatus = lot['status'];
    } else {
      _editingId = null;
      _lotNumberController.clear();
      _priceController.clear();
      _xCoordController.clear();
      _yCoordController.clear();
      _selectedSectionId = null;
      _selectedStatus = 'Available';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(_isEditing ? Icons.edit : Icons.add_box,
                     color: const Color(0xFF4B6E4F)),
                const SizedBox(width: 8),
                Text(_isEditing ? 'Edit Lot' : 'Add New Lot'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _lotNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Lot Number *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedSectionId,
                    decoration: const InputDecoration(
                      labelText: 'Section *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Select Section')),
                      ..._sections.map((section) => DropdownMenuItem(
                        value: section['section_id'].toString(),
                        child: Text(section['name'] ?? 'Unknown'),
                      )),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedSectionId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Price (₱) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _xCoordController,
                          decoration: const InputDecoration(
                            labelText: 'X Coordinate *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _yCoordController,
                          decoration: const InputDecoration(
                            labelText: 'Y Coordinate *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isEditing)
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.info),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Available', child: Text('Available')),
                        DropdownMenuItem(value: 'Occupied', child: Text('Occupied')),
                        DropdownMenuItem(value: 'Reserved', child: Text('Reserved')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedStatus = value;
                        });
                      },
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
                    await _saveLot();
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

  bool _validateForm() {
    if (_lotNumberController.text.trim().isEmpty) {
      _showError('Lot number is required');
      return false;
    }
    if (_selectedSectionId == null) {
      _showError('Please select a section');
      return false;
    }
    if (_priceController.text.trim().isEmpty) {
      _showError('Price is required');
      return false;
    }
    if (_xCoordController.text.trim().isEmpty) {
      _showError('X coordinate is required');
      return false;
    }
    if (_yCoordController.text.trim().isEmpty) {
      _showError('Y coordinate is required');
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

 Future<void> _saveLot() async {
  setState(() {
    _isLoading = true;
  });

  try {
    final supabase = Supabase.instance.client;
    final data = {
      'lot_number': _lotNumberController.text.trim(),
      'section_id': int.parse(_selectedSectionId!),
      'price': double.parse(_priceController.text.trim()),
      'x_coord': double.parse(_xCoordController.text.trim()),
      'y_coord': double.parse(_yCoordController.text.trim()),
      'status': _selectedStatus ?? 'Available',
    };

    if (_isEditing && _editingId != null) {
      // UPDATE
      await supabase
          .from('cemetery_lot')
          .update(data)
          .eq('lot_id', int.parse(_editingId!));
      
      await AuditService.log(
        action: 'UPDATE',
        entityType: 'lot',
        entityId: _editingId,
        details: 'Updated lot ${_lotNumberController.text.trim()}',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lot updated!'), backgroundColor: Colors.green),
      );
    } else {
      // CREATE
      final result = await supabase.from('cemetery_lot').insert(data).select();
      final newLotId = result.first['lot_id'].toString();
      
      await AuditService.log(
        action: 'CREATE',
        entityType: 'lot',
        entityId: newLotId,
        details: 'Created lot ${_lotNumberController.text.trim()}',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lot added!'), backgroundColor: Colors.green),
      );
    }
    
    await _loadData();
    _applyFilters();
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
  Future<void> _deleteLot(String id, String lotNumber) async {
  final lot = _lots.firstWhere((l) => l['lot_id'].toString() == id);
  if (lot['burial_record'] != null) {
    _showError('Cannot delete occupied lot');
    return;
  }
  
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Lot'),
      content: Text('Delete Lot $lotNumber?'),
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
      await supabase.from('cemetery_lot').delete().eq('lot_id', int.parse(id));
      
      await AuditService.log(
        action: 'DELETE',
        entityType: 'lot',
        entityId: id,
        details: 'Deleted lot $lotNumber',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lot deleted!'), backgroundColor: Colors.green),
      );
      await _loadData();
      _applyFilters();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Available': return Colors.green;
      case 'Occupied': return Colors.red;
      case 'Reserved': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return 'N/A';
    return '₱${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lots Management'),
        backgroundColor: const Color(0xFF4B6E4F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadData();
              _applyFilters();
            },
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
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Search by lot number or section...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onChanged: (value) {
                              _searchQuery = value;
                              _applyFilters();
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _filterSection,
                                  decoration: const InputDecoration(
                                    labelText: 'Section',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: 'All', child: Text('All Sections')),
                                    ..._sections.map((section) => DropdownMenuItem(
                                      value: section['section_id'].toString(),
                                      child: Text(section['name'] ?? 'Unknown'),
                                    )),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _filterSection = value ?? 'All';
                                      _applyFilters();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _filterStatus,
                                  decoration: const InputDecoration(
                                    labelText: 'Status',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'All', child: Text('All Status')),
                                    DropdownMenuItem(value: 'Available', child: Text('Available')),
                                    DropdownMenuItem(value: 'Occupied', child: Text('Occupied')),
                                    DropdownMenuItem(value: 'Reserved', child: Text('Reserved')),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _filterStatus = value ?? 'All';
                                      _applyFilters();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    Expanded(
                      child: _filteredLots.isEmpty
                          ? const Center(child: Text('No lots found'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredLots.length,
                              itemBuilder: (context, index) {
                                final lot = _filteredLots[index];
                                final section = lot['section'] ?? {};
                                final burial = lot['burial_record'];
                                final statusColor = _getStatusColor(lot['status']);
                                
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: statusColor.withOpacity(0.1),
                                      child: Icon(Icons.location_on, color: statusColor),
                                    ),
                                    title: Text(
                                      'Lot ${lot['lot_number']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Section: ${section['name'] ?? 'N/A'}'),
                                        Text('Price: ${_formatCurrency(lot['price'])}'),
                                        if (burial != null)
                                          Text('Occupant: ${burial['name_of_deceased']}',
                                               style: const TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                          onPressed: () => _showAddEditDialog(lot),
                                        ),
                                        if (lot['status'] == 'Available')
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            onPressed: () => _deleteLot(
                                              lot['lot_id'].toString(),
                                              lot['lot_number'],
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
            onPressed: () {
              _loadData();
              _applyFilters();
            },
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