import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_delete_service.dart';
import '../../services/admin_grave_service.dart';
import '../../services/lot_price_catalog_service.dart';
import '../../services/supabase_pagination_service.dart';
import '../../utils/lot_formatters.dart';
import '../../utils/lot_pricing.dart';
import '../../widgets/app_date_field.dart';

const _lotColumnsSelect =
    'lot_id, lot_number, lot_label, block_number, lot_class_type, price, status, qgis_feature_id, polygon_geo';

class AdminLotsScreen extends ConsumerStatefulWidget {
  const AdminLotsScreen({
    super.key,
    this.onMenuPressed,
    this.onLogoutPressed,
    this.initialLot,
    this.editorRequestToken = 0,
  });

  final VoidCallback? onMenuPressed;
  final VoidCallback? onLogoutPressed;
  final Map<String, dynamic>? initialLot;
  final int editorRequestToken;

  @override
  ConsumerState<AdminLotsScreen> createState() => _AdminLotsScreenState();
}

class _AdminLotsScreenState extends ConsumerState<AdminLotsScreen> {
  ColorScheme _colors(BuildContext context) => Theme.of(context).colorScheme;
  List<Map<String, dynamic>> _lots = [];
  List<Map<String, dynamic>> _filteredLots = [];
  List<Map<String, dynamic>> _lotOwners = [];
  List<LotPrice> _priceCatalog = List.of(lotPriceCatalog);
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String _filterStatus = 'All';
  static const int _pageSize = 30;
  int _currentPage = 0;

  int get _pageCount =>
      _filteredLots.isEmpty ? 1 : (_filteredLots.length / _pageSize).ceil();

  List<Map<String, dynamic>> get _pagedLots {
    final start = _currentPage * _pageSize;
    if (start >= _filteredLots.length) return const [];
    final end = (start + _pageSize).clamp(0, _filteredLots.length);
    return _filteredLots.sublist(start, end);
  }

  // Form controllers
  final _blockNumberController = TextEditingController();
  final _lotNumberController = TextEditingController();
  final _lotLabelController = TextEditingController();
  final _lotClassTypeController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedStatus;

  // For Reserved - lot owner selection
  String? _selectedOwnerId;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(AdminLotsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newLotId = widget.initialLot?['lot_id']?.toString();
    if (newLotId == null ||
        widget.editorRequestToken == oldWidget.editorRequestToken ||
        _lots.isEmpty) {
      return;
    }
    final requestedLot = _lots.firstWhere(
      (lot) => lot['lot_id']?.toString() == newLotId,
      orElse: () => <String, dynamic>{},
    );
    if (requestedLot.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEditDialog(requestedLot);
      });
    }
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

      final results = await Future.wait([
        SupabasePaginationService.selectAll(
          supabase: supabase,
          table: 'cemetery_lot',
          columns: _lotColumnsSelect,
          orderColumn: 'lot_id',
        ),
        SupabasePaginationService.selectAll(
          supabase: supabase,
          table: 'burial_record',
          columns: 'burial_id, name_of_deceased, lot_id',
          orderColumn: 'burial_id',
        ),
        SupabasePaginationService.selectAll(
          supabase: supabase,
          table: 'lot_ownership',
          columns:
              'ownership_id, lot_id, user_id, total_months, months_paid, user:user_id (name)',
          orderColumn: 'ownership_id',
        ),
        _loadRegisterDetails(),
        LotPriceCatalogService.load(),
      ]);
      final lots = List<Map<String, dynamic>>.from(results[0] as List);
      final burialRows = List<Map<String, dynamic>>.from(results[1] as List);
      final ownershipRows = List<Map<String, dynamic>>.from(results[2] as List);
      final registerDetails = List<Map<String, dynamic>>.from(
        results[3] as List,
      );
      final registerByLot = {
        for (final row in registerDetails)
          row['lot_id'].toString(): row['details'],
      };
      final gravesByLotId = await AdminGraveService.loadGravesByLotIds(
        lots.map((lot) => lot['lot_id']),
      );

      final burialsByLotId = <String, List<Map<String, dynamic>>>{};
      for (final burial in burialRows) {
        final lotId = burial['lot_id']?.toString();
        if (lotId == null) continue;
        burialsByLotId.putIfAbsent(lotId, () => []).add(burial);
      }
      final ownershipByLotId = <String, Map<String, dynamic>>{};
      for (final ownership in ownershipRows) {
        final lotId = ownership['lot_id']?.toString();
        if (lotId != null) ownershipByLotId[lotId] = ownership;
      }

      final lotsWithDetails = <Map<String, dynamic>>[];
      for (var lot in lots) {
        final lotId = lot['lot_id'];
        var lotWithDetails = Map<String, dynamic>.from(lot);
        lotWithDetails['register_details'] = registerByLot[lotId.toString()];
        final lotBurials = List<Map<String, dynamic>>.from(
          burialsByLotId[lotId?.toString()] ?? const [],
        );
        lotBurials.sort(
          (a, b) => (a['name_of_deceased'] ?? '').toString().compareTo(
            (b['name_of_deceased'] ?? '').toString(),
          ),
        );
        if (lotBurials.isNotEmpty) {
          lotWithDetails['burial_record'] = lotBurials.first;
          lotWithDetails['burial_records'] = lotBurials;
        }
        final ownership = ownershipByLotId[lotId?.toString()];
        if (ownership != null) {
          lotWithDetails['ownership'] = ownership;
        }
        lotWithDetails['graves'] = gravesByLotId[lotId?.toString()] ?? [];
        lotsWithDetails.add(lotWithDetails);
      }

      setState(() {
        _lotOwners = List<Map<String, dynamic>>.from(owners);
        _priceCatalog = List<LotPrice>.from(results[4] as List<LotPrice>);
        _lots = lotsWithDetails;
        _filteredLots = List<Map<String, dynamic>>.from(lotsWithDetails);
        _currentPage = 0;
        _isLoading = false;
      });
      final requestedLotId = widget.initialLot?['lot_id']?.toString();
      if (requestedLotId != null && mounted) {
        final requestedLot = lotsWithDetails.firstWhere(
          (lot) => lot['lot_id']?.toString() == requestedLotId,
          orElse: () => <String, dynamic>{},
        );
        if (requestedLot.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showEditDialog(requestedLot);
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoading = false;
      });
    }
  }

  LotPrice? _priceForType(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final price in _priceCatalog) {
      if (price.type.toLowerCase() == normalized) return price;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadRegisterDetails() async {
    try {
      return await SupabasePaginationService.selectAll(
        supabase: Supabase.instance.client,
        table: 'lot_register_details',
        columns: 'lot_id, details',
        orderColumn: 'lot_id',
      );
    } on PostgrestException catch (error) {
      // The register import creates this optional table.
      if (error.code == '42P01' || error.code == 'PGRST205') return [];
      rethrow;
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredLots = _lots.where((lot) {
        final query = _searchQuery.toLowerCase();
        final matchesSearch =
            query.isEmpty ||
            lotSearchText(lot).contains(query) ||
            (lot['register_details']?.toString().toLowerCase().contains(
                  query,
                ) ??
                false);

        final matchesStatus =
            _filterStatus == 'All' || lot['status'] == _filterStatus;

        return matchesSearch && matchesStatus;
      }).toList();
      _currentPage = 0;
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
    _editingId = lot['lot_id'].toString();
    _blockNumberController.text = lotText(lot, 'block_number');
    _lotNumberController.text = lotText(lot, 'lot_number');
    _lotLabelController.text = lotText(lot, 'lot_label');
    _lotClassTypeController.text = lotText(lot, 'lot_class_type');
    _priceController.text = lot['price']?.toString() ?? '';
    _selectedStatus = lot['status'];

    if (lot['ownership'] != null) {
      _selectedOwnerId = lot['ownership']['user_id'];
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: _colors(context).surfaceContainer,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _colors(context).primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    color: _colors(context).primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Edit Lot',
                    style: TextStyle(
                      color: _colors(context).onSurface,
                      fontWeight: FontWeight.w600,
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
                  DropdownButtonFormField<String>(
                    initialValue: _priceForType(
                      _lotClassTypeController.text,
                    )?.type,
                    decoration: _fieldDecoration(
                      labelText: 'Lot Class / Type',
                      icon: Icons.category_outlined,
                    ),
                    items: _priceCatalog
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.type,
                            child: Text(entry.type),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      final pricing = _priceForType(value);
                      setDialogState(() {
                        _lotClassTypeController.text = value ?? '';
                        _priceController.text =
                            pricing?.atNeed.toStringAsFixed(2) ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final pricing = _priceForType(
                        _lotClassTypeController.text,
                      );
                      return InputDecorator(
                        decoration: _fieldDecoration(
                          labelText: 'Fixed prices',
                          icon: Icons.payments_outlined,
                        ),
                        child: Text(
                          pricing == null
                              ? 'Select a lot type'
                              : 'At-need: PHP ${pricing.atNeed.toStringAsFixed(2)}  •  '
                                    'Pre-need: PHP ${pricing.preNeed.toStringAsFixed(2)}',
                        ),
                      );
                    },
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
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: _colors(context).onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (_validateForm()) {
                    Navigator.pop(context);
                    await _saveLot();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colors(context).primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Update'),
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
          backgroundColor: _colors(context).surfaceContainer,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _colors(context).primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add_location_alt_rounded,
                  color: _colors(context).primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add Grave to Lot ${lotReference(lot)}',
                  style: TextStyle(fontWeight: FontWeight.w600),
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
                        icon: Icons.grid_view_outlined,
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
                foregroundColor: _colors(context).onSurfaceVariant,
              ),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _colors(context).primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Add Grave'),
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
        SnackBar(
          content: Text('Grave and deceased record saved!'),
          backgroundColor: _colors(context).primary,
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
      prefixIcon: Icon(icon, color: _colors(context).primary),
      filled: true,
      fillColor: _colors(context).surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: _colors(context).outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: _colors(context).outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: _colors(context).primary, width: 1.4),
      ),
    );
  }

  bool _validateForm() {
    if (_lotNumberController.text.trim().isEmpty) {
      _showError('Lot number is required');
      return false;
    }
    if (_priceForType(_lotClassTypeController.text) == null) {
      _showError('Please select a valid lot type');
      return false;
    }
    if (_selectedStatus == 'Reserved' && _selectedOwnerId == null) {
      _showError('Please select a lot owner for reserved lot');
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
      final pricing = _priceForType(lotClassType)!;
      final data = {
        'block_number': blockNumber.isEmpty ? null : blockNumber,
        'lot_number': lotNumber,
        'lot_label': lotLabel.isEmpty ? lotNumber : lotLabel,
        'lot_class_type': lotClassType.isEmpty ? null : lotClassType,
        'price': pricing.atNeed,
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
                'total_months': 1,
                'months_paid': 1,
              })
              .eq('lot_id', lotId);
        } else {
          await supabase.from('lot_ownership').insert({
            'user_id': _selectedOwnerId,
            'lot_id': lotId,
            'total_months': 1,
            'months_paid': 1,
            'start_date': DateTime.now().toIso8601String(),
            'status': 'Active',
          });
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lot updated!'),
          backgroundColor: _colors(context).primary,
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
        backgroundColor: _colors(context).surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              foregroundColor: _colors(context).onSurfaceVariant,
            ),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBA1A1A),
            ),
            child: Text('Delete'),
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
          SnackBar(
            content: Text('Lot deleted!'),
            backgroundColor: _colors(context).primary,
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
        return _colors(context).primary;
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
      backgroundColor: _colors(context).surfaceContainer,
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
                            children: [
                              ...List.generate(
                                _pagedLots.length,
                                (index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: _buildLotCard(_pagedLots[index]),
                                ),
                              ),
                              _buildPaginationControls(),
                            ],
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
            Text(
              'Lots Management',
              style: TextStyle(
                color: _colors(context).primary,
                fontSize: 28,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage cemetery lots, availability, reservations, ownership, and prices.',
              style: TextStyle(
                color: _colors(context).onSurfaceVariant,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        );
        final refreshButton = OutlinedButton.icon(
          onPressed: _refreshLots,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Refresh'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _colors(context).primary,
            side: BorderSide(color: _colors(context).outlineVariant),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        final priceCatalogButton = FilledButton.icon(
          onPressed: _showPriceCatalogDialog,
          icon: const Icon(Icons.sell_outlined),
          label: const Text('Lot prices'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: priceCatalogButton),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: refreshButton),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            priceCatalogButton,
            const SizedBox(width: 12),
            refreshButton,
          ],
        );
      },
    );
  }

  Future<void> _showPriceCatalogDialog() async {
    final atNeedControllers = <String, TextEditingController>{
      for (final price in _priceCatalog)
        price.type: TextEditingController(text: price.atNeed.toStringAsFixed(2)),
    };
    final preNeedControllers = <String, TextEditingController>{
      for (final price in _priceCatalog)
        price.type: TextEditingController(text: price.preNeed.toStringAsFixed(2)),
    };

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: _colors(dialogContext).surfaceContainer,
            surfaceTintColor: Colors.transparent,
            title: const Text('Lot price catalogue'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Set the at-need and pre-need prices for each lot type. Saving updates existing lots of that type.',
                      style: TextStyle(
                        color: _colors(dialogContext).onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._priceCatalog.map(
                      (price) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              price.type,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: atNeedControllers[price.type],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'At-need price',
                                      prefixText: 'PHP ',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: preNeedControllers[price.type],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Pre-need price',
                                      prefixText: 'PHP ',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final changes = <LotPrice>[];
                  for (final price in _priceCatalog) {
                    final atNeed = double.tryParse(
                      atNeedControllers[price.type]!.text.trim(),
                    );
                    final preNeed = double.tryParse(
                      preNeedControllers[price.type]!.text.trim(),
                    );
                    if (atNeed == null || preNeed == null || atNeed < 0 || preNeed < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter valid, non-negative prices.')),
                      );
                      return;
                    }
                    if (atNeed != price.atNeed || preNeed != price.preNeed) {
                      changes.add(LotPrice(type: price.type, atNeed: atNeed, preNeed: preNeed));
                    }
                  }
                  if (changes.isEmpty) {
                    Navigator.of(dialogContext).pop();
                    return;
                  }
                  try {
                    for (final price in changes) {
                      await LotPriceCatalogService.save(price);
                    }
                    if (!mounted) return;
                    await _refreshLots();
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lot prices updated.')),
                    );
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not update lot prices: $error')),
                    );
                  }
                },
                child: const Text('Save prices'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controller in atNeedControllers.values) {
        controller.dispose();
      }
      for (final controller in preNeedControllers.values) {
        controller.dispose();
      }
    }
  }

  Widget _buildPaginationControls() {
    final firstRecord = _filteredLots.isEmpty
        ? 0
        : (_currentPage * _pageSize) + 1;
    final lastRecord = ((_currentPage + 1) * _pageSize).clamp(
      0,
      _filteredLots.length,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _colors(context).surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $firstRecord–$lastRecord of ${_filteredLots.length} lots',
              style: TextStyle(
                color: _colors(context).onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Previous page',
            onPressed: _currentPage == 0
                ? null
                : () => setState(() => _currentPage--),
            icon: Icon(Icons.chevron_left_rounded),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Page ${_currentPage + 1} of $_pageCount',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: _currentPage >= _pageCount - 1
                ? null
                : () => setState(() => _currentPage++),
            icon: Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colors(context).surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;
          final searchField = TextField(
            decoration: InputDecoration(
              hintText: 'Search lots, blocks, owners, or deceased names',
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: _colors(context).surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: _colors(context).outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: _colors(context).outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(
                  color: _colors(context).primary,
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
              fillColor: _colors(context).secondaryContainer,
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
        color: _colors(context).surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _colors(context).surfaceContainerHighest),
      ),
      child: Text(
        'No lots found',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _colors(context).onSurfaceVariant,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildLotCard(Map<String, dynamic> lot) {
    final register = lot['register_details'] as Map?;
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
        color: _colors(context).surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _colors(context).surfaceContainerHighest),
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
                      style: TextStyle(
                        color: _colors(context).onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
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
                            color: _colors(context).secondary,
                          ),
                        _LotInfoChip(
                          icon: Icons.payments_outlined,
                          label: _formatCurrency(lot['price']),
                          color: _colors(context).primary,
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
                                'Reserved for ${ownership['user']?['name'] ?? 'Unknown'}',
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
                  icon: Icon(Icons.add_location_alt_rounded),
                  tooltip: 'Add grave',
                  style: IconButton.styleFrom(
                    backgroundColor: _colors(context).primaryContainer,
                    foregroundColor: _colors(context).primary,
                  ),
                ),
                IconButton(
                  onPressed: () => _showEditDialog(lot),
                  icon: Icon(Icons.edit_rounded),
                  tooltip: 'Edit',
                  style: IconButton.styleFrom(
                    backgroundColor: _colors(context).surfaceContainerLow,
                    foregroundColor: _colors(context).secondary,
                  ),
                ),
                if (status == 'Available')
                  IconButton(
                    onPressed: () =>
                        _deleteLot(lot['lot_id'].toString(), lotReference(lot)),
                    icon: Icon(Icons.delete_rounded),
                    tooltip: 'Delete',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFFDAD6),
                      foregroundColor: const Color(0xFFBA1A1A),
                    ),
                  ),
              ],
            ),
          ),
          if (register != null && register.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Lot register', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final field in const {
              'owner_name': 'Owner / purchaser',
              'purchase_date': 'Purchase date',
              'deceased_names': 'Deceased',
              'purchase_note': 'Purchase note',
            }.entries)
              if (register[field.key] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    '${field.value}: ${register[field.key]}',
                  ),
                ),
          ],
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
          style: TextStyle(
            color: _colors(context).onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
              icon: Icons.grid_view_outlined,
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
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage!),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              _loadData();
              _applyFilters();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _colors(context).primary,
              foregroundColor: Colors.white,
            ),
            child: Text('Try Again'),
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
