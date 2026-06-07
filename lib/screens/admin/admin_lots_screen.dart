import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_delete_service.dart';
import '../../services/admin_grave_service.dart';
import '../../utils/lot_formatters.dart';
import '../../widgets/app_date_field.dart';

const _lotColumnsSelect =
    'lot_id, lot_number, lot_label, block_number, lot_class_type, price, status, qgis_feature_id, polygon_geo';

class AdminLotsScreen extends ConsumerStatefulWidget {
  const AdminLotsScreen({super.key, this.onMenuPressed, this.onLogoutPressed});

  final VoidCallback? onMenuPressed;
  final VoidCallback? onLogoutPressed;

  @override
  ConsumerState<AdminLotsScreen> createState() => _AdminLotsScreenState();
}

class _AdminLotsScreenState extends ConsumerState<AdminLotsScreen> {
  List<Map<String, dynamic>> _lots = [];
  List<Map<String, dynamic>> _filteredLots = [];
  List<Map<String, dynamic>> _lotOwners = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _filterStatus = 'All';

  // Form controllers
  final _blockNumberController = TextEditingController();
  final _lotNumberController = TextEditingController();
  final _lotLabelController = TextEditingController();
  final _lotClassTypeController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedStatus;

  // For Reserved - lot owner selection
  String? _selectedOwnerId;
  int? _selectedInstallmentMonths;

  String? _editingId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _blockNumberController.dispose();
    _lotNumberController.dispose();
    _lotLabelController.dispose();
    _lotClassTypeController.dispose();
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

      final owners = await supabase
          .from('users')
          .select('user_id, name, email')
          .eq('role', 'lot_owner');

      final lots = await supabase
          .from('cemetery_lot')
          .select(_lotColumnsSelect)
          .order('block_number')
          .order('lot_number');
      final gravesByLotId = await AdminGraveService.loadGravesByLotIds(
        (lots as List).map((lot) => lot['lot_id']),
      );

      final lotsWithDetails = <Map<String, dynamic>>[];
      for (var lot in lots) {
        final lotId = lot['lot_id'];

        final burialRecords = await supabase
            .from('burial_record')
            .select('burial_id, name_of_deceased')
            .eq('lot_id', lotId)
            .order('name_of_deceased');

        final ownership = await supabase
            .from('lot_ownership')
            .select('user_id, total_months, months_paid, user:user_id (name)')
            .eq('lot_id', lotId)
            .maybeSingle();

        var lotWithDetails = Map<String, dynamic>.from(lot);
        final lotBurials = List<Map<String, dynamic>>.from(
          burialRecords as List,
        );
        if (lotBurials.isNotEmpty) {
          lotWithDetails['burial_record'] = lotBurials.first;
          lotWithDetails['burial_records'] = lotBurials;
        }
        if (ownership != null) {
          lotWithDetails['ownership'] = ownership;
        }
        lotWithDetails['graves'] = gravesByLotId[lotId?.toString()] ?? [];
        lotsWithDetails.add(lotWithDetails);
      }

      setState(() {
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
        final query = _searchQuery.toLowerCase();
        final matchesSearch =
            query.isEmpty || lotSearchText(lot).contains(query);

        final matchesStatus =
            _filterStatus == 'All' || lot['status'] == _filterStatus;

        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _refreshLots() async {
    await _loadData();
    if (!mounted || _errorMessage != null) return;
    _applyFilters();
  }

  bool _isValidDateText(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return false;
    return DateTime.tryParse(text) != null;
  }

  bool _isValidTimeText(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    return RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').hasMatch(text);
  }

  String? _blankToNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _showEditDialog(Map<String, dynamic> lot) async {
    _selectedOwnerId = null;
    _selectedInstallmentMonths = null;

    _editingId = lot['lot_id'].toString();
    _blockNumberController.text = lotText(lot, 'block_number');
    _lotNumberController.text = lotText(lot, 'lot_number');
    _lotLabelController.text = lotText(lot, 'lot_label');
    _lotClassTypeController.text = lotText(lot, 'lot_class_type');
    _priceController.text = lot['price']?.toString() ?? '';
    _selectedStatus = lot['status'];

    if (lot['ownership'] != null) {
      _selectedOwnerId = lot['ownership']['user_id'];
      _selectedInstallmentMonths = lot['ownership']['total_months'];
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
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Color(0xFF335538),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Edit Lot',
                    style: TextStyle(
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
                    controller: _blockNumberController,
                    decoration: _fieldDecoration(
                      labelText: 'Block',
                      icon: Icons.grid_view_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lotNumberController,
                    decoration: _fieldDecoration(
                      labelText: 'Lot Number *',
                      icon: Icons.numbers_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lotLabelController,
                    decoration: _fieldDecoration(
                      labelText: 'Lot Label',
                      icon: Icons.label_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lotClassTypeController,
                    decoration: _fieldDecoration(
                      labelText: 'Lot Class / Type',
                      icon: Icons.category_outlined,
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
                        _selectedOwnerId = null;
                        _selectedInstallmentMonths = null;
                      });
                    },
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddGraveDialog(Map<String, dynamic> lot) async {
    final lotId = int.tryParse(lot['lot_id']?.toString() ?? '');
    if (lotId == null) {
      _showError('This lot is missing a valid ID');
      return;
    }

    final existingGraves = List<Map<String, dynamic>>.from(
      lot['graves'] as List? ?? [],
    );
    final graveLabelController = TextEditingController(
      text: AdminGraveService.nextGraveLabel(existingGraves),
    );
    final deceasedNameController = TextEditingController();
    final birthDateController = TextEditingController();
    final deathDateController = TextEditingController();
    final religionController = TextEditingController();
    final intermentDateController = TextEditingController();
    final intermentTimeController = TextEditingController();
    final notesController = TextEditingController();
    var graveMode = 'new';
    int? selectedBurialId;
    String? selectedLotType =
        AdminGraveService.lotTypes.contains(lot['lot_class_type']?.toString())
        ? lot['lot_class_type'].toString()
        : null;
    final existingBurials = await Supabase.instance.client
        .from('burial_record')
        .select('burial_id, name_of_deceased, death_date, lot_id')
        .order('name_of_deceased');
    if (!mounted) return;
    final burialOptions = List<Map<String, dynamic>>.from(
      existingBurials as List,
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                child: const Icon(
                  Icons.add_location_alt_rounded,
                  color: Color(0xFF335538),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add Grave to Lot ${lotReference(lot)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: graveLabelController,
                    decoration: _fieldDecoration(
                      labelText: 'Grave / Slot Label *',
                      icon: Icons.label_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: graveMode,
                    decoration: _fieldDecoration(
                      labelText: 'Deceased Record',
                      icon: Icons.person_pin_circle_outlined,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'new',
                        child: Text('Create new deceased record'),
                      ),
                      DropdownMenuItem(
                        value: 'existing',
                        child: Text('Link existing deceased record'),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        graveMode = value ?? 'new';
                        selectedBurialId = null;
                      });
                    },
                  ),
                  if (graveMode == 'existing') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedBurialId,
                      decoration: _fieldDecoration(
                        labelText: 'Existing Deceased *',
                        icon: Icons.person_search_rounded,
                      ),
                      items: burialOptions.map((burial) {
                        final lotText = burial['lot_id'] == null
                            ? 'unassigned'
                            : 'already assigned';
                        return DropdownMenuItem<int>(
                          value: int.tryParse(burial['burial_id'].toString()),
                          child: Text(
                            '${burial['name_of_deceased'] ?? 'Unknown'} ($lotText)',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedBurialId = value);
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: deceasedNameController,
                      decoration: _fieldDecoration(
                        labelText: 'Name of Deceased *',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppDateField(
                            controller: birthDateController,
                            label: 'Born',
                            icon: Icons.cake_outlined,
                            helperText: 'YYYY-MM-DD',
                            decoration: _fieldDecoration(
                              labelText: 'Born',
                              icon: Icons.cake_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppDateField(
                            controller: deathDateController,
                            label: 'Died *',
                            icon: Icons.event_busy_outlined,
                            helperText: 'YYYY-MM-DD',
                            decoration: _fieldDecoration(
                              labelText: 'Died *',
                              icon: Icons.event_busy_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppDateField(
                            controller: intermentDateController,
                            label: 'Interment Date',
                            icon: Icons.calendar_today_outlined,
                            helperText: 'YYYY-MM-DD',
                            decoration: _fieldDecoration(
                              labelText: 'Interment Date',
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: intermentTimeController,
                            decoration: _fieldDecoration(
                              labelText: 'Interment Time',
                              icon: Icons.schedule_outlined,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: religionController,
                      decoration: _fieldDecoration(
                        labelText: 'Religion',
                        icon: Icons.church_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedLotType,
                      decoration: _fieldDecoration(
                        labelText: 'Lot Type',
                        icon: Icons.category_outlined,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Select lot type'),
                        ),
                        ...AdminGraveService.lotTypes.map(
                          (type) => DropdownMenuItem<String?>(
                            value: type,
                            child: Text(type),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => selectedLotType = value);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: _fieldDecoration(
                      labelText: 'Grave Notes',
                      icon: Icons.notes_outlined,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF424841),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF335538),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Add Grave'),
            ),
          ],
        ),
      ),
    );

    final graveLabel = graveLabelController.text.trim();
    final deceasedName = deceasedNameController.text.trim();
    final birthDate = birthDateController.text.trim();
    final deathDate = deathDateController.text.trim();
    final religion = religionController.text.trim();
    final intermentDate = intermentDateController.text.trim();
    final intermentTime = intermentTimeController.text.trim();
    final notes = notesController.text.trim();
    graveLabelController.dispose();
    deceasedNameController.dispose();
    birthDateController.dispose();
    deathDateController.dispose();
    religionController.dispose();
    intermentDateController.dispose();
    intermentTimeController.dispose();
    notesController.dispose();

    if (saved != true) return;
    if (graveLabel.isEmpty) {
      _showError('Grave label is required');
      return;
    }
    if (graveMode == 'existing' && selectedBurialId == null) {
      _showError('Please select an existing deceased record');
      return;
    }
    if (graveMode == 'new') {
      if (deceasedName.isEmpty || deathDate.isEmpty) {
        _showError('Name of deceased and death date are required');
        return;
      }
      if (!_isValidDateText(birthDate) ||
          !_isValidDateText(deathDate) ||
          !_isValidDateText(intermentDate)) {
        _showError('Dates must use YYYY-MM-DD format');
        return;
      }
      if (!_isValidTimeText(intermentTime)) {
        _showError('Interment time must use HH:mm format');
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      if (graveMode == 'existing') {
        await AdminGraveService.addGrave(
          lotId: lotId,
          graveLabel: graveLabel,
          status: 'Occupied',
          burialId: selectedBurialId,
          notes: notes,
        );
      } else {
        await AdminGraveService.createBurialAndGrave(
          lotId: lotId,
          graveLabel: graveLabel,
          deceasedName: deceasedName,
          birthDate: _blankToNull(birthDate),
          deathDate: deathDate,
          intermentDate: _blankToNull(intermentDate),
          intermentTime: _blankToNull(intermentTime),
          religion: _blankToNull(religion),
          lotType: selectedLotType,
          notes: notes,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grave and deceased record saved!'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      _showError('Unable to add grave: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  String _defaultLotLabel({
    required String blockNumber,
    required String lotNumber,
  }) {
    if (blockNumber.isNotEmpty && lotNumber.isNotEmpty) {
      return '$blockNumber-$lotNumber';
    }
    return lotNumber;
  }

  Future<void> _saveLot() async {
    if (_editingId == null) {
      _showError('Select a lot to edit');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final blockNumber = _blockNumberController.text.trim();
      final lotNumber = _lotNumberController.text.trim();
      final lotLabel = _lotLabelController.text.trim().isEmpty
          ? _defaultLotLabel(blockNumber: blockNumber, lotNumber: lotNumber)
          : _lotLabelController.text.trim();
      final lotClassType = _lotClassTypeController.text.trim();
      final data = {
        'block_number': blockNumber.isEmpty ? null : blockNumber,
        'lot_number': lotNumber,
        'lot_label': lotLabel.isEmpty ? lotNumber : lotLabel,
        'lot_class_type': lotClassType.isEmpty ? null : lotClassType,
        'price': double.parse(_priceController.text.trim()),
        'status': _selectedStatus,
      };

      final lotId = int.parse(_editingId!);

      await supabase.from('cemetery_lot').update(data).eq('lot_id', lotId);

      if (_selectedStatus == 'Reserved' && _selectedOwnerId != null) {
        final existingOwnership = await supabase
            .from('lot_ownership')
            .select('ownership_id')
            .eq('lot_id', lotId)
            .maybeSingle();

        if (existingOwnership != null) {
          await supabase
              .from('lot_ownership')
              .update({
                'user_id': _selectedOwnerId,
                'total_months': _selectedInstallmentMonths,
              })
              .eq('lot_id', lotId);
        } else {
          await supabase.from('lot_ownership').insert({
            'user_id': _selectedOwnerId,
            'lot_id': lotId,
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
        content: Text(
          'Delete Lot $lotNumber? This also removes its marker from the map.',
        ),
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
        await AdminDeleteService.deleteLot(int.parse(id));
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
                                  bottom: index == _filteredLots.length - 1
                                      ? 0
                                      : 16,
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
        final refreshButton = OutlinedButton.icon(
          onPressed: _refreshLots,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF335538),
            side: const BorderSide(color: Color(0xFFC2C8BF)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: refreshButton),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            refreshButton,
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
              hintText: 'Search by lot, block, class/type, or status',
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
                borderSide: const BorderSide(
                  color: Color(0xFF335538),
                  width: 1.4,
                ),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
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
              children: [searchField, const SizedBox(height: 12), statusFilter],
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
    final graves = List<Map<String, dynamic>>.from(
      lot['graves'] as List? ?? [],
    );
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
                      'Lot ${lotReference(lot)}',
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
                        if (lotMeta(lot).isNotEmpty)
                          _LotInfoChip(
                            icon: Icons.grid_view_rounded,
                            label: lotMeta(lot),
                            color: const Color(0xFF47626F),
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
                            label:
                                'Reserved for ${ownership['user']?['name'] ?? 'Unknown'} (${ownership['total_months']} months)',
                            color: const Color(0xFFB67C33),
                          ),
                      ],
                    ),
                    if (graves.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildGravesList(graves),
                    ],
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
                  onPressed: () => _showAddGraveDialog(lot),
                  icon: const Icon(Icons.add_location_alt_rounded),
                  tooltip: 'Add grave',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFC5EDC6),
                    foregroundColor: const Color(0xFF335538),
                  ),
                ),
                IconButton(
                  onPressed: () => _showEditDialog(lot),
                  icon: const Icon(Icons.edit_rounded),
                  tooltip: 'Edit',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF5F3F0),
                    foregroundColor: const Color(0xFF47626F),
                  ),
                ),
                if (status == 'Available')
                  IconButton(
                    onPressed: () =>
                        _deleteLot(lot['lot_id'].toString(), lotReference(lot)),
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

  Widget _buildGravesList(List<Map<String, dynamic>> graves) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Graves (${graves.length})',
          style: const TextStyle(
            color: Color(0xFF424841),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: graves.map((grave) {
            final status = grave['status']?.toString() ?? 'Available';
            final burial = grave['burial'];
            final deceasedName = burial is Map
                ? burial['name_of_deceased']?.toString()
                : null;
            final deathDate = burial is Map
                ? burial['death_date']?.toString()
                : null;
            final details = [
              grave['grave_label']?.toString() ?? 'Grave',
              if (deceasedName != null && deceasedName.isNotEmpty)
                deceasedName
              else
                status.toUpperCase(),
              if (deathDate != null && deathDate.isNotEmpty) 'Died $deathDate',
            ].join(' - ');
            return _LotInfoChip(
              icon: Icons.church_outlined,
              label: details,
              color: _getStatusColor(status),
            );
          }).toList(),
        ),
      ],
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
