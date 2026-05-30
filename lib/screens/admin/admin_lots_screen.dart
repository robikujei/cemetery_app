import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminLotsScreen extends ConsumerStatefulWidget {
  const AdminLotsScreen({
    super.key,
    this.onMenuPressed,
    this.onLogoutPressed,
  });

  final VoidCallback? onMenuPressed;
  final VoidCallback? onLogoutPressed;

  @override
  ConsumerState<AdminLotsScreen> createState() => _AdminLotsScreenState();
}

class _AdminLotsScreenState extends ConsumerState<AdminLotsScreen> {
  List<Map<String, dynamic>> _lots = [];
  List<Map<String, dynamic>> _filteredLots = [];
  List<Map<String, dynamic>> _burialRecords = [];
  List<Map<String, dynamic>> _lotOwners = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _filterStatus = 'All';

  // Form controllers
  final _lotNumberController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedStatus;

  // For Occupied - burial record selection
  int? _selectedBurialId;

  // For Reserved - lot owner selection
  String? _selectedOwnerId;
  int? _selectedInstallmentMonths;

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
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      final burials = await supabase
          .from('burial_record')
          .select('burial_id, name_of_deceased, lot_id');

      final owners = await supabase
          .from('users')
          .select('user_id, name, email')
          .eq('role', 'lot_owner');

      final lots = await supabase
          .from('cemetery_lot')
          .select('lot_id, lot_number, price, status, section_id')
          .order('lot_number');

      final lotsWithDetails = <Map<String, dynamic>>[];
      for (var lot in lots) {
        final lotId = lot['lot_id'];

        final burialRecord = await supabase
            .from('burial_record')
            .select('burial_id, name_of_deceased')
            .eq('lot_id', lotId)
            .maybeSingle();

        final ownership = await supabase
            .from('lot_ownership')
            .select('user_id, total_months, months_paid, user:user_id (name)')
            .eq('lot_id', lotId)
            .maybeSingle();

        var lotWithDetails = Map<String, dynamic>.from(lot);
        if (burialRecord != null) {
          lotWithDetails['burial_record'] = burialRecord;
        }
        if (ownership != null) {
          lotWithDetails['ownership'] = ownership;
        }
        lotsWithDetails.add(lotWithDetails);
      }

      setState(() {
        _burialRecords = List<Map<String, dynamic>>.from(burials);
        _lotOwners = List<Map<String, dynamic>>.from(owners);
        _lots = lotsWithDetails;
        _filteredLots = List<Map<String, dynamic>>.from(lotsWithDetails);
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
        final matchesSearch =
            _searchQuery.isEmpty ||
            lot['lot_number'].toString().toLowerCase().contains(
              _searchQuery.toLowerCase(),
            );

        final matchesStatus =
            _filterStatus == 'All' || lot['status'] == _filterStatus;

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _showAddEditDialog([Map<String, dynamic>? lot]) async {
    _isEditing = lot != null;

    _selectedBurialId = null;
    _selectedOwnerId = null;
    _selectedInstallmentMonths = null;

    if (lot != null) {
      _editingId = lot['lot_id'].toString();
      _lotNumberController.text = lot['lot_number'] ?? '';
      _priceController.text = lot['price']?.toString() ?? '';
      _selectedStatus = lot['status'];

      if (lot['burial_record'] != null) {
        _selectedBurialId = lot['burial_record']['burial_id'];
      }
      if (lot['ownership'] != null) {
        _selectedOwnerId = lot['ownership']['user_id'];
        _selectedInstallmentMonths = lot['ownership']['total_months'];
      }
    } else {
      _editingId = null;
      _lotNumberController.clear();
      _priceController.clear();
      _selectedStatus = 'Available';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFFBF9F6),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
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
                    _isEditing ? Icons.edit_rounded : Icons.add_rounded,
                    color: const Color(0xFF335538),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Lot' : 'Add New Lot',
                    style: const TextStyle(
                      color: Color(0xFF1B1C1A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _lotNumberController,
                    decoration: _fieldDecoration(
                      labelText: 'Lot Number *',
                      icon: Icons.numbers_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceController,
                    decoration: _fieldDecoration(
                      labelText: 'Price (PHP) *',
                      icon: Icons.payments_outlined,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    decoration: _fieldDecoration(
                      labelText: 'Status *',
                      icon: Icons.info_outline_rounded,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Available',
                        child: Text('Available'),
                      ),
                      DropdownMenuItem(
                        value: 'Occupied',
                        child: Text('Occupied'),
                      ),
                      DropdownMenuItem(
                        value: 'Reserved',
                        child: Text('Reserved'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedStatus = value;
                        _selectedBurialId = null;
                        _selectedOwnerId = null;
                        _selectedInstallmentMonths = null;
                      });
                    },
                  ),

                  if (_selectedStatus == 'Occupied')
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedBurialId,
                          decoration: _fieldDecoration(
                            labelText: 'Select Deceased Person *',
                            icon: Icons.person_outline_rounded,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Select a deceased person'),
                            ),
                            ..._burialRecords.map(
                              (burial) => DropdownMenuItem(
                                value: burial['burial_id'],
                                child: Text(
                                  burial['name_of_deceased'] ?? 'Unknown',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              _selectedBurialId = value;
                            });
                          },
                        ),
                      ],
                    ),

                  if (_selectedStatus == 'Reserved')
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedOwnerId,
                          decoration: _fieldDecoration(
                            labelText: 'Select Lot Owner *',
                            icon: Icons.person_outline_rounded,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Select a lot owner'),
                            ),
                            ..._lotOwners.map(
                              (owner) => DropdownMenuItem(
                                value: owner['user_id'],
                                child: Text(
                                  '${owner['name']} (${owner['email']})',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              _selectedOwnerId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedInstallmentMonths,
                          decoration: _fieldDecoration(
                            labelText: 'Installment Terms *',
                            icon: Icons.calendar_month_rounded,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 12,
                              child: Text('12 months (1 year)'),
                            ),
                            DropdownMenuItem(
                              value: 24,
                              child: Text('24 months (2 years)'),
                            ),
                            DropdownMenuItem(
                              value: 36,
                              child: Text('36 months (3 years)'),
                            ),
                            DropdownMenuItem(
                              value: 48,
                              child: Text('48 months (4 years)'),
                            ),
                            DropdownMenuItem(
                              value: 60,
                              child: Text('60 months (5 years)'),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              _selectedInstallmentMonths = value;
                            });
                          },
                        ),
                      ],
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
                    await _saveLot();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF335538),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(_isEditing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: labelText,
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
    );
  }

  bool _validateForm() {
    if (_lotNumberController.text.trim().isEmpty) {
      _showError('Lot number is required');
      return false;
    }
    if (_priceController.text.trim().isEmpty) {
      _showError('Price is required');
      return false;
    }
    if (_selectedStatus == 'Occupied' && _selectedBurialId == null) {
      _showError('Please select a deceased person for occupied lot');
      return false;
    }
    if (_selectedStatus == 'Reserved' && _selectedOwnerId == null) {
      _showError('Please select a lot owner for reserved lot');
      return false;
    }
    if (_selectedStatus == 'Reserved' && _selectedInstallmentMonths == null) {
      _showError('Please select installment terms');
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
        'price': double.parse(_priceController.text.trim()),
        'status': _selectedStatus,
      };

      if (_isEditing && _editingId != null) {
        await supabase
            .from('cemetery_lot')
            .update(data)
            .eq('lot_id', int.parse(_editingId!));

        if (_selectedStatus == 'Occupied' && _selectedBurialId != null) {
          await supabase
              .from('burial_record')
              .update({'lot_id': int.parse(_editingId!)})
              .eq('burial_id', _selectedBurialId!);
        }

        if (_selectedStatus == 'Reserved' && _selectedOwnerId != null) {
          final existingOwnership = await supabase
              .from('lot_ownership')
              .select('ownership_id')
              .eq('lot_id', int.parse(_editingId!))
              .maybeSingle();

          if (existingOwnership != null) {
            await supabase
                .from('lot_ownership')
                .update({
                  'user_id': _selectedOwnerId,
                  'total_months': _selectedInstallmentMonths,
                })
                .eq('lot_id', int.parse(_editingId!));
          } else {
            await supabase.from('lot_ownership').insert({
              'user_id': _selectedOwnerId,
              'lot_id': int.parse(_editingId!),
              'total_months': _selectedInstallmentMonths ?? 24,
              'months_paid': 0,
              'start_date': DateTime.now().toIso8601String(),
              'status': 'Active',
            });
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lot updated!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final result = await supabase
            .from('cemetery_lot')
            .insert(data)
            .select();
        final newLotId = result.first['lot_id'].toString();

        if (_selectedStatus == 'Occupied' && _selectedBurialId != null) {
          await supabase
              .from('burial_record')
              .update({'lot_id': int.parse(newLotId)})
              .eq('burial_id', _selectedBurialId!);
        }

        if (_selectedStatus == 'Reserved' && _selectedOwnerId != null) {
          await supabase.from('lot_ownership').insert({
            'user_id': _selectedOwnerId,
            'lot_id': int.parse(newLotId),
            'total_months': _selectedInstallmentMonths ?? 24,
            'months_paid': 0,
            'start_date': DateTime.now().toIso8601String(),
            'status': 'Active',
          });
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lot added!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadData();
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFBF9F6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFBA1A1A)),
            SizedBox(width: 10),
            Text('Delete Lot'),
          ],
        ),
        content: Text('Are you sure you want to delete Lot $lotNumber?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF424841),
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBA1A1A),
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
        await supabase
            .from('cemetery_lot')
            .delete()
            .eq('lot_id', int.parse(id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lot deleted!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
        _applyFilters();
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Available':
        return Colors.green;
      case 'Occupied':
        return Colors.red;
      case 'Reserved':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return 'N/A';
    return 'PHP ${amount.toStringAsFixed(2)}';
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
                        _filteredLots.isEmpty
                            ? _buildEmptyState()
                            : Column(
                                children: List.generate(
                                  _filteredLots.length,
                                  (index) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom: index == _filteredLots.length - 1 ? 0 : 16,
                                    ),
                                    child: _buildLotCard(_filteredLots[index]),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeaderSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lots Management',
              style: TextStyle(
                color: Color(0xFF335538),
                fontSize: 28,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage cemetery lots, availability, reservations, ownership, and prices.',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.58),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        );
        final addButton = FilledButton.icon(
          onPressed: () => _showAddEditDialog(),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF335538),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add New Lot'),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: addButton,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            addButton,
          ],
        );
      },
    );
  }

  Widget _buildSearchFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3F0),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;
          final searchField = TextField(
            decoration: InputDecoration(
              hintText: 'Search by lot number',
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
            onChanged: (value) {
              _searchQuery = value;
              _applyFilters();
            },
          );
          final statusFilter = DropdownButtonFormField<String>(
              initialValue: _filterStatus,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFC7E4F3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            );

          if (isNarrow) {
            return Column(
              children: [
                searchField,
                const SizedBox(height: 12),
                statusFilter,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              SizedBox(width: 190, child: statusFilter),
            ],
          );
        },
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
        'No lots found',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF424841), fontSize: 16),
      ),
    );
  }

  Widget _buildLotCard(Map<String, dynamic> lot) {
    final burial = lot['burial_record'];
    final ownership = lot['ownership'];
    final status = lot['status']?.toString() ?? 'Unknown';
    final statusColor = _getStatusColor(status);

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
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(Icons.location_on_rounded, color: statusColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lot ${lot['lot_number'] ?? 'N/A'}',
                      style: const TextStyle(
                        color: Color(0xFF1B1C1A),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _LotInfoChip(
                          icon: Icons.info_outline_rounded,
                          label: status,
                          color: statusColor,
                        ),
                        _LotInfoChip(
                          icon: Icons.payments_outlined,
                          label: _formatCurrency(lot['price']),
                          color: const Color(0xFF335538),
                        ),
                        if (burial != null)
                          _LotInfoChip(
                            icon: Icons.person_outline_rounded,
                            label: 'Occupant: ${burial['name_of_deceased']}',
                            color: const Color(0xFFBA1A1A),
                          ),
                        if (ownership != null && status == 'Reserved')
                          _LotInfoChip(
                            icon: Icons.assignment_ind_outlined,
                            label: 'Reserved for ${ownership['user']?['name'] ?? 'Unknown'} (${ownership['total_months']} months)',
                            color: const Color(0xFFB67C33),
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
                  onPressed: () => _showAddEditDialog(lot),
                  icon: const Icon(Icons.edit_rounded),
                  tooltip: 'Edit',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF5F3F0),
                    foregroundColor: const Color(0xFF47626F),
                  ),
                ),
                if (status == 'Available')
                  IconButton(
                    onPressed: () => _deleteLot(
                      lot['lot_id'].toString(),
                      lot['lot_number'],
                    ),
                    icon: const Icon(Icons.delete_rounded),
                    tooltip: 'Delete',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFFDAD6),
                      foregroundColor: const Color(0xFFBA1A1A),
                    ),
                  ),
              ],
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

class _LotInfoChip extends StatelessWidget {
  const _LotInfoChip({
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
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



