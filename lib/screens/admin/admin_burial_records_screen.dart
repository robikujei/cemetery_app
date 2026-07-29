import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/admin_delete_service.dart';
import '../../services/audit_service.dart';
import '../../utils/lot_formatters.dart';
import '../../widgets/app_date_field.dart';
import '../../utils/lot_pricing.dart';

class AdminBurialRecordsScreen extends ConsumerStatefulWidget {
  const AdminBurialRecordsScreen({
    super.key,
    this.onMenuPressed,
    this.onLogoutPressed,
    this.initialLot,
    this.openAddForm = false,
    this.closeAfterCreate = false,
  });

  final VoidCallback? onMenuPressed;
  final VoidCallback? onLogoutPressed;
  final Map<String, dynamic>? initialLot;
  final bool openAddForm;
  final bool closeAfterCreate;

  @override
  ConsumerState<AdminBurialRecordsScreen> createState() =>
      _AdminBurialRecordsScreenState();
}

class _AdminBurialRecordsScreenState
    extends ConsumerState<AdminBurialRecordsScreen> {
  static final _burialCategories = lotPriceCatalog
      .map((lot) => lot.type)
      .toList(growable: false);

  List<Map<String, dynamic>> _burialRecords = [];
  List<Map<String, dynamic>> _filteredRecords = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Form controllers for add/edit
  final _applicationDateController = TextEditingController();
  final _nameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _deathDateController = TextEditingController();
  final _religionController = TextEditingController();
  final _intermentDateController = TextEditingController();
  final _intermentTimeController = TextEditingController();
  final _informantNameController = TextEditingController();
  final _informantRelationshipController = TextEditingController();
  final _informantAddressController = TextEditingController();
  final _informantWorkController = TextEditingController();
  final _informantCellphoneController = TextEditingController();
  final _informantIdPresentedController = TextEditingController();
  final _informantIdNumberController = TextEditingController();
  final _informantPlaceIssuedController = TextEditingController();
  final _bldgNoController = TextEditingController();
  final _nicheNoController = TextEditingController();
  final _levelController = TextEditingController();
  final _lotLocationNoController = TextEditingController();
  final _registeredLotOwnerController = TextEditingController();
  final _registeredOwnerContactController = TextEditingController();
  final _orNumberController = TextEditingController();
  final _intermentTotalController = TextEditingController();
  final _paymentDateController = TextEditingController();
  String? _selectedInformantId;
  String? _selectedBurialCategory;
  bool _deathCertificateSubmitted = false;
  bool _ownershipCertificateSubmitted = false;
  bool _authorityDocumentSubmitted = false;
  List<Map<String, dynamic>> _informants = [];
  bool _informantsTableAvailable = true;

  // Error messages for validation
  String? _nameError;
  String? _deathDateError;
  String? _birthDateError;
  String? _applicationDateError;
  String? _intermentDateError;
  String? _intermentTimeError;

  bool _isEditing = false;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _loadData().then((_) {
      if (mounted && widget.openAddForm) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showAddEditDialog();
        });
      }
    });
  }

  @override
  void dispose() {
    _applicationDateController.dispose();
    _nameController.dispose();
    _birthDateController.dispose();
    _deathDateController.dispose();
    _religionController.dispose();
    _intermentDateController.dispose();
    _intermentTimeController.dispose();
    _informantNameController.dispose();
    _informantRelationshipController.dispose();
    _informantAddressController.dispose();
    _informantWorkController.dispose();
    _informantCellphoneController.dispose();
    _informantIdPresentedController.dispose();
    _informantIdNumberController.dispose();
    _informantPlaceIssuedController.dispose();
    _bldgNoController.dispose();
    _nicheNoController.dispose();
    _levelController.dispose();
    _lotLocationNoController.dispose();
    _registeredLotOwnerController.dispose();
    _registeredOwnerContactController.dispose();
    _orNumberController.dispose();
    _intermentTotalController.dispose();
    _paymentDateController.dispose();
    super.dispose();
  }

  bool _isMissingTableError(PostgrestException error) {
    return error.code == 'PGRST205' || error.message.contains('schema cache');
  }

  Future<({List<Map<String, dynamic>> items, bool tableAvailable})>
  _fetchInformants(SupabaseClient supabase) async {
    try {
      final informants = await supabase
          .from('burial_informants')
          .select(
            'informant_id, full_name, relationship_to_deceased, address, work, cellphone_no, id_presented, id_number, place_issued',
          )
          .order('full_name');
      return (
        items: List<Map<String, dynamic>>.from(informants),
        tableAvailable: true,
      );
    } on PostgrestException catch (error) {
      if (_isMissingTableError(error)) {
        return (items: <Map<String, dynamic>>[], tableAvailable: false);
      }
      rethrow;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // Fetch burial records without embedding burial_informants
      // (the FK relationship may not be visible to PostgREST).
      final records = await supabase
          .from('burial_record')
          .select('''
            *,
            cemetery_lot (
              lot_id,
              lot_number,
              lot_label,
              block_number,
              lot_class_type
            )
          ''')
          .order('death_date', ascending: false);

      final informantsResult = await _fetchInformants(supabase);
      final informantList = informantsResult.items;
      final informantMap = <String, Map<String, dynamic>>{};
      for (final inf in informantList) {
        informantMap[inf['informant_id'].toString()] = inf;
      }

      // Attach the informant object to each record (mirrors the old join).
      final enrichedRecords = List<Map<String, dynamic>>.from(records).map((r) {
        final mutable = Map<String, dynamic>.from(r);
        final infId = mutable['informant_id'];
        if (infId != null && informantMap.containsKey(infId.toString())) {
          mutable['informant'] = informantMap[infId.toString()];
        }
        return mutable;
      }).toList();

      setState(() {
        _burialRecords = enrichedRecords;
        _filteredRecords = List<Map<String, dynamic>>.from(enrichedRecords);
        _informants = informantList;
        _informantsTableAvailable = informantsResult.tableAvailable;
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

  bool _isValidTimeFormat(String timeStr) {
    if (timeStr.isEmpty) return true;
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(timeStr);
    return match != null;
  }

  String _dateText(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    if (text.isEmpty) return '';
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(text));
    } catch (_) {
      return text.length >= 10 ? text.substring(0, 10) : text;
    }
  }

  String? _dateOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _textOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  double? _moneyOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
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
      _applicationDateError = null;
      _intermentDateError = null;
      _intermentTimeError = null;
    });

    if (_nameController.text.trim().isEmpty) {
      _showValidationErrorDialog(
        'Missing Information',
        'Please enter the name of the deceased.',
      );
      setState(() => _nameError = 'Name of deceased is required');
      return false;
    }

    final deathDateStr = _deathDateController.text;
    if (deathDateStr.isEmpty) {
      _showValidationErrorDialog(
        'Missing Information',
        'Death date is required.',
      );
      setState(() => _deathDateError = 'Death date is required');
      return false;
    }

    if (!_isValidDateFormat(deathDateStr)) {
      _showValidationErrorDialog(
        'Invalid Date Format',
        'Death date must be in YYYY-MM-DD format.\nExample: 2024-05-10',
      );
      setState(() => _deathDateError = 'Invalid date format or value');
      return false;
    }

    final deathDate = _parseDate(deathDateStr)!;
    if (deathDate.isAfter(DateTime.now())) {
      _showValidationErrorDialog(
        'Invalid Date',
        'Death date cannot be in the future.',
      );
      setState(() => _deathDateError = 'Death date cannot be in the future');
      return false;
    }

    final birthDateStr = _birthDateController.text;
    DateTime? birthDate;
    if (birthDateStr.isNotEmpty) {
      if (!_isValidDateFormat(birthDateStr)) {
        _showValidationErrorDialog(
          'Invalid Date Format',
          'Birth date must be in YYYY-MM-DD format.\nExample: 1950-01-15',
        );
        setState(() => _birthDateError = 'Invalid date format or value');
        return false;
      }

      birthDate = _parseDate(birthDateStr)!;
      if (birthDate.isAfter(DateTime.now())) {
        _showValidationErrorDialog(
          'Invalid Date',
          'Birth date cannot be in the future.',
        );
        setState(() => _birthDateError = 'Birth date cannot be in the future');
        return false;
      }

      if (deathDate.isBefore(birthDate)) {
        _showValidationErrorDialog(
          'Invalid Date Relationship',
          'Death date cannot be earlier than birth date.',
        );
        setState(() => _deathDateError = 'Death date must be after birth date');
        setState(
          () => _birthDateError = 'Birth date must be before death date',
        );
        return false;
      }
    }

    final applicationDateStr = _applicationDateController.text.trim();
    if (!_isValidDateFormat(applicationDateStr)) {
      _showValidationErrorDialog(
        'Invalid Date Format',
        'Application date must be in YYYY-MM-DD format.',
      );
      setState(() => _applicationDateError = 'Invalid date format or value');
      return false;
    }

    final intermentDateStr = _intermentDateController.text.trim();
    if (!_isValidDateFormat(intermentDateStr)) {
      _showValidationErrorDialog(
        'Invalid Date Format',
        'Interment date must be in YYYY-MM-DD format.',
      );
      setState(() => _intermentDateError = 'Invalid date format or value');
      return false;
    }

    final intermentTimeStr = _intermentTimeController.text.trim();
    if (!_isValidTimeFormat(intermentTimeStr)) {
      _showValidationErrorDialog(
        'Invalid Time Format',
        'Interment time must be in 24-hour HH:mm format.\nExample: 14:30',
      );
      setState(() => _intermentTimeError = 'Use HH:mm format');
      return false;
    }

    if (_hasInformantDetails && _informantNameController.text.trim().isEmpty) {
      _showValidationErrorDialog(
        'Missing Informant Name',
        'Please enter the informant full name or clear the informant fields.',
      );
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
          final lotText = lotSearchText(record['cemetery_lot']);
          final informant = record['informant'];
          final informantName = informant is Map
              ? informant['full_name']?.toString().toLowerCase() ?? ''
              : '';
          final category =
              record['burial_category']?.toString().toLowerCase() ?? '';
          final religion = record['religion']?.toString().toLowerCase() ?? '';
          final normalizedQuery = query.toLowerCase();
          return name.contains(query.toLowerCase()) ||
              lotText.contains(normalizedQuery) ||
              informantName.contains(normalizedQuery) ||
              category.contains(normalizedQuery) ||
              religion.contains(normalizedQuery);
        }).toList();
      }
    });
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF335538),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? helper,
    String? error,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _recordFieldDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        errorText: error,
        icon: icon,
      ),
    );
  }

  Widget _fieldRow(List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  void _applyInformantToForm(Map<String, dynamic> informant) {
    _informantNameController.text = informant['full_name']?.toString() ?? '';
    _informantRelationshipController.text =
        informant['relationship_to_deceased']?.toString() ?? '';
    _informantAddressController.text = informant['address']?.toString() ?? '';
    _informantWorkController.text = informant['work']?.toString() ?? '';
    _informantCellphoneController.text =
        informant['cellphone_no']?.toString() ?? '';
    _informantIdPresentedController.text =
        informant['id_presented']?.toString() ?? '';
    _informantIdNumberController.text =
        informant['id_number']?.toString() ?? '';
    _informantPlaceIssuedController.text =
        informant['place_issued']?.toString() ?? '';
  }

  Future<void> _showAddEditDialog([Map<String, dynamic>? record]) async {
    _isEditing = record != null;

    _nameError = null;
    _deathDateError = null;
    _birthDateError = null;
    _applicationDateError = null;
    _intermentDateError = null;
    _intermentTimeError = null;

    if (record != null) {
      final informant = record['informant'] is Map
          ? Map<String, dynamic>.from(record['informant'])
          : <String, dynamic>{};
      _editingId = record['burial_id'].toString();
      _applicationDateController.text = _dateText(record['application_date']);
      _nameController.text = record['name_of_deceased'] ?? '';
      _birthDateController.text = _dateText(record['birth_date']);
      _deathDateController.text = _dateText(record['death_date']);
      _religionController.text = record['religion']?.toString() ?? '';
      _intermentDateController.text = _dateText(
        record['interment_date'] ?? record['burial_date'],
      );
      final intermentTime = record['interment_time']?.toString() ?? '';
      _intermentTimeController.text = intermentTime.length >= 5
          ? intermentTime.substring(0, 5)
          : intermentTime;
      _selectedBurialCategory = record['burial_category']?.toString();
      if (!_burialCategories.contains(_selectedBurialCategory)) {
        _selectedBurialCategory = null;
      }
      _selectedInformantId =
          record['informant_id']?.toString() ??
          informant['informant_id']?.toString();
      _applyInformantToForm(informant);
      _bldgNoController.text = record['bldg_no']?.toString() ?? '';
      _nicheNoController.text = record['niche_no']?.toString() ?? '';
      _levelController.text = record['level']?.toString() ?? '';
      _lotLocationNoController.text =
          record['lot_location_no']?.toString() ?? '';
      _registeredLotOwnerController.text =
          record['registered_lot_owner']?.toString() ?? '';
      _registeredOwnerContactController.text =
          record['registered_owner_contact_no']?.toString() ?? '';
      _orNumberController.text =
          record['interment_or_number']?.toString() ?? '';
      _intermentTotalController.text =
          record['interment_total']?.toString() ?? '';
      _paymentDateController.text = _dateText(record['interment_payment_date']);
      _deathCertificateSubmitted =
          record['death_certificate_submitted'] == true;
      _ownershipCertificateSubmitted =
          record['ownership_certificate_submitted'] == true;
      _authorityDocumentSubmitted =
          record['authority_document_submitted'] == true;
    } else {
      _editingId = null;
      _applicationDateController.text = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now());
      _nameController.clear();
      _birthDateController.clear();
      _deathDateController.clear();
      _religionController.clear();
      _intermentDateController.clear();
      _intermentTimeController.clear();
      final initialLotType = widget.initialLot?['lot_class_type']?.toString();
      _selectedBurialCategory = _burialCategories.contains(initialLotType)
          ? initialLotType
          : null;
      _selectedInformantId = null;
      _informantNameController.clear();
      _informantRelationshipController.clear();
      _informantAddressController.clear();
      _informantWorkController.clear();
      _informantCellphoneController.clear();
      _informantIdPresentedController.clear();
      _informantIdNumberController.clear();
      _informantPlaceIssuedController.clear();
      _bldgNoController.clear();
      _nicheNoController.clear();
      _levelController.clear();
      _lotLocationNoController.text = widget.initialLot == null
          ? ''
          : lotReference(widget.initialLot, fallback: '');
      _registeredLotOwnerController.clear();
      _registeredOwnerContactController.clear();
      _orNumberController.clear();
      _intermentTotalController.clear();
      _paymentDateController.clear();
      _deathCertificateSubmitted = false;
      _ownershipCertificateSubmitted = false;
      _authorityDocumentSubmitted = false;
    }

    if (!mounted) return;
    final dialogResult = await showDialog<bool>(
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
                    _isEditing
                        ? Icons.edit_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: const Color(0xFF335538),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditing
                        ? 'Edit Interment Application'
                        : 'Add Interment Application',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sectionTitle('Application'),
                    AppDateField(
                      controller: _applicationDateController,
                      label: 'Application Date',
                      icon: Icons.event_note_outlined,
                      helperText: 'YYYY-MM-DD',
                      errorText: _applicationDateError,
                      decoration: _recordFieldDecoration(
                        labelText: 'Application Date',
                        icon: Icons.event_note_outlined,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Informant'),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedInformantId,
                      decoration: _recordFieldDecoration(
                        labelText: 'Use Existing Informant',
                        icon: Icons.manage_accounts_outlined,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('New informant'),
                        ),
                        ..._informants.map(
                          (informant) => DropdownMenuItem<String?>(
                            value: informant['informant_id'].toString(),
                            child: Text(
                              '${informant['full_name'] ?? 'Unnamed'}'
                              '${informant['cellphone_no'] == null ? '' : ' (${informant['cellphone_no']})'}',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedInformantId = value;
                          if (value == null) {
                            _informantNameController.clear();
                            _informantRelationshipController.clear();
                            _informantAddressController.clear();
                            _informantWorkController.clear();
                            _informantCellphoneController.clear();
                            _informantIdPresentedController.clear();
                            _informantIdNumberController.clear();
                            _informantPlaceIssuedController.clear();
                          } else {
                            final selected = _informants.firstWhere(
                              (item) =>
                                  item['informant_id'].toString() == value,
                              orElse: () => {},
                            );
                            _applyInformantToForm(selected);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      controller: _informantNameController,
                      label: 'Full Name',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _fieldRow([
                      _textField(
                        controller: _informantRelationshipController,
                        label: 'Relationship to Deceased',
                        icon: Icons.family_restroom_rounded,
                      ),
                      _textField(
                        controller: _informantCellphoneController,
                        label: 'Cellphone No.',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _textField(
                      controller: _informantAddressController,
                      label: 'Address',
                      icon: Icons.home_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    _fieldRow([
                      _textField(
                        controller: _informantWorkController,
                        label: 'Work',
                        icon: Icons.work_outline_rounded,
                      ),
                      _textField(
                        controller: _informantIdPresentedController,
                        label: 'ID Presented',
                        icon: Icons.badge_outlined,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _fieldRow([
                      _textField(
                        controller: _informantIdNumberController,
                        label: 'ID Number',
                        icon: Icons.numbers_rounded,
                      ),
                      _textField(
                        controller: _informantPlaceIssuedController,
                        label: 'Place Issued',
                        icon: Icons.place_outlined,
                      ),
                    ]),
                    const SizedBox(height: 18),
                    _sectionTitle('Deceased'),
                    _textField(
                      controller: _nameController,
                      label: 'Name of Deceased *',
                      icon: Icons.person_outline_rounded,
                      error: _nameError,
                    ),
                    const SizedBox(height: 12),
                    _fieldRow([
                      AppDateField(
                        controller: _birthDateController,
                        label: 'Born',
                        icon: Icons.cake_outlined,
                        helperText: 'YYYY-MM-DD',
                        errorText: _birthDateError,
                        decoration: _recordFieldDecoration(
                          labelText: 'Born',
                          icon: Icons.cake_outlined,
                        ),
                      ),
                      AppDateField(
                        controller: _deathDateController,
                        label: 'Died *',
                        icon: Icons.event_busy_rounded,
                        helperText: 'YYYY-MM-DD',
                        errorText: _deathDateError,
                        decoration: _recordFieldDecoration(
                          labelText: 'Died *',
                          icon: Icons.event_busy_rounded,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _textField(
                      controller: _religionController,
                      label: 'Religion',
                      icon: Icons.church_outlined,
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Schedule of Interment'),
                    _fieldRow([
                      AppDateField(
                        controller: _intermentDateController,
                        label: 'Date',
                        icon: Icons.calendar_today_outlined,
                        helperText: 'YYYY-MM-DD',
                        errorText: _intermentDateError,
                        decoration: _recordFieldDecoration(
                          labelText: 'Date',
                          icon: Icons.calendar_today_outlined,
                        ),
                      ),
                      _textField(
                        controller: _intermentTimeController,
                        label: 'Time',
                        icon: Icons.schedule_outlined,
                        helper: 'HH:mm',
                        error: _intermentTimeError,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedBurialCategory,
                      decoration: _recordFieldDecoration(
                        labelText: 'Lot Type',
                        icon: Icons.category_outlined,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Select lot type'),
                        ),
                        ..._burialCategories.map(
                          (category) => DropdownMenuItem<String?>(
                            value: category,
                            child: Text(category),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => _selectedBurialCategory = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Lot Location on Paper Form'),
                    _fieldRow([
                      _textField(
                        controller: _bldgNoController,
                        label: 'Bldg No.',
                        icon: Icons.apartment_rounded,
                      ),
                      _textField(
                        controller: _nicheNoController,
                        label: 'Niche No.',
                        icon: Icons.inventory_2_outlined,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _fieldRow([
                      _textField(
                        controller: _levelController,
                        label: 'Level',
                        icon: Icons.layers_outlined,
                      ),
                      _textField(
                        controller: _lotLocationNoController,
                        label: 'Lot No.',
                        icon: Icons.location_on_outlined,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _fieldRow([
                      _textField(
                        controller: _registeredLotOwnerController,
                        label: 'Registered Lot Owner',
                        icon: Icons.assignment_ind_outlined,
                      ),
                      _textField(
                        controller: _registeredOwnerContactController,
                        label: 'Owner Contact No.',
                        icon: Icons.phone_android_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC7E4F3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 18,
                            color: Color(0xFF2F4A57),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Assign the exact cemetery lot from Map Manager by selecting the lot polygon and choosing Assign Deceased.',
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
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3EB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            color: Color(0xFF335538),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'The interment fee is already included in the '
                              'lot payment recorded when the lot owner is '
                              'assigned.',
                              style: TextStyle(
                                color: Color(0xFF335538),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('Requirements Submitted'),
                    CheckboxListTile(
                      value: _deathCertificateSubmitted,
                      onChanged: (value) => setDialogState(
                        () => _deathCertificateSubmitted = value ?? false,
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Death Certificate'),
                    ),
                    CheckboxListTile(
                      value: _ownershipCertificateSubmitted,
                      onChanged: (value) => setDialogState(
                        () => _ownershipCertificateSubmitted = value ?? false,
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Certificate of Ownership / Purchase Profile',
                      ),
                    ),
                    CheckboxListTile(
                      value: _authorityDocumentSubmitted,
                      onChanged: (value) => setDialogState(
                        () => _authorityDocumentSubmitted = value ?? false,
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Authority / Affidavit / Certification',
                      ),
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
                    Navigator.pop(context, true);
                    await _saveRecord();
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
                child: Text(_isEditing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted &&
        widget.closeAfterCreate &&
        dialogResult != true &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  bool get _hasInformantDetails {
    return [
      _informantNameController,
      _informantRelationshipController,
      _informantAddressController,
      _informantWorkController,
      _informantCellphoneController,
      _informantIdPresentedController,
      _informantIdNumberController,
      _informantPlaceIssuedController,
    ].any((controller) => controller.text.trim().isNotEmpty);
  }

  Future<int?> _saveInformantIfNeeded(SupabaseClient supabase) async {
    if (!_hasInformantDetails) return null;

    if (!_informantsTableAvailable) {
      throw Exception(
        'Informant details are unavailable until the burial_informants '
        'database table is created. Run '
        'cemetery_app/supabase/add_burial_interment_fields.sql in the '
        'Supabase SQL editor.',
      );
    }

    final fullName = _informantNameController.text.trim();
    if (fullName.isEmpty) {
      throw Exception(
        'Informant full name is required when informant details are entered.',
      );
    }

    final data = {
      'full_name': fullName,
      'relationship_to_deceased': _textOrNull(_informantRelationshipController),
      'address': _textOrNull(_informantAddressController),
      'work': _textOrNull(_informantWorkController),
      'cellphone_no': _textOrNull(_informantCellphoneController),
      'id_presented': _textOrNull(_informantIdPresentedController),
      'id_number': _textOrNull(_informantIdNumberController),
      'place_issued': _textOrNull(_informantPlaceIssuedController),
    };

    final existingId = int.tryParse(_selectedInformantId ?? '');
    if (existingId != null) {
      await supabase
          .from('burial_informants')
          .update(data)
          .eq('informant_id', existingId);
      return existingId;
    }

    final inserted = await supabase
        .from('burial_informants')
        .insert(data)
        .select('informant_id')
        .single();
    return int.tryParse(inserted['informant_id'].toString());
  }

  Future<void> _saveRecord() async {
    if (!_validateForm()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final informantId = await _saveInformantIfNeeded(supabase);
      final intermentDate = _dateOrNull(_intermentDateController);
      final data = {
        'application_date': _dateOrNull(_applicationDateController),
        'informant_id': informantId,
        'name_of_deceased': _nameController.text.trim(),
        'birth_date': _birthDateController.text.isEmpty
            ? null
            : _birthDateController.text,
        'death_date': _deathDateController.text,
        'religion': _textOrNull(_religionController),
        'burial_date': intermentDate,
        'interment_date': intermentDate,
        'interment_time': _textOrNull(_intermentTimeController),
        'burial_category': _selectedBurialCategory,
        'bldg_no': _textOrNull(_bldgNoController),
        'niche_no': _textOrNull(_nicheNoController),
        'level': _textOrNull(_levelController),
        'lot_location_no': _textOrNull(_lotLocationNoController),
        'registered_lot_owner': _textOrNull(_registeredLotOwnerController),
        'registered_owner_contact_no': _textOrNull(
          _registeredOwnerContactController,
        ),
        'interment_or_number': _textOrNull(_orNumberController),
        'interment_total': _moneyOrNull(_intermentTotalController),
        'interment_payment_date': _dateOrNull(_paymentDateController),
        'death_certificate_submitted': _deathCertificateSubmitted,
        'ownership_certificate_submitted': _ownershipCertificateSubmitted,
        'authority_document_submitted': _authorityDocumentSubmitted,
      };
      if (!_isEditing && widget.initialLot?['lot_id'] != null) {
        data['lot_id'] = widget.initialLot!['lot_id'];
      }

      if (_isEditing && _editingId != null) {
        await supabase
            .from('burial_record')
            .update(data)
            .eq('burial_id', int.parse(_editingId!));

        await AuditService.log(
          action: 'UPDATE',
          entityType: 'burial',
          entityId: _editingId,
          details: 'Updated burial for ${_nameController.text.trim()}',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Record updated!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final result = await supabase
            .from('burial_record')
            .insert(data)
            .select();
        final newId = result.first['burial_id'].toString();

        await AuditService.log(
          action: 'CREATE',
          entityType: 'burial',
          entityId: newId,
          details: 'Created burial for ${_nameController.text.trim()}',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Record added!'),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.closeAfterCreate) {
          Navigator.of(context).pop(int.tryParse(newId));
          return;
        }
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
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFBA1A1A),
              ),
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
        content: Text(
          'Delete $name? Visitor logs for this burial will be detached so the record can be removed.',
        ),
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
        await AdminDeleteService.deleteBurialRecord(int.parse(id));

        await AuditService.log(
          action: 'DELETE',
          entityType: 'burial',
          entityId: id,
          details: 'Deleted burial for $name',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Record deleted!'),
            backgroundColor: Colors.green,
          ),
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
      appBar: widget.closeAfterCreate
          ? AppBar(
              backgroundColor: const Color(0xFFFBF9F6),
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                tooltip: 'Back to map',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: const Text('Add Deceased'),
            )
          : null,
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
                                    bottom: index == _filteredRecords.length - 1
                                        ? 0
                                        : 16,
                                  ),
                                  child: _buildRecordCard(
                                    _filteredRecords[index],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: OutlinedButton(
                                  onPressed: _loadData,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1B1C1A),
                                    side: const BorderSide(
                                      color: Color(0xFFC2C8BF),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 14,
                                    ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
                hintText: 'Search by deceased, informant, category, or lot',
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
        style: TextStyle(color: Color(0xFF424841), fontSize: 16),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final lot = record['cemetery_lot'] ?? {};
    final deathDate = _formatDate(record['death_date']);
    final birthDate = _formatDate(record['birth_date']);
    final intermentDate = _formatDate(
      (record['interment_date'] ?? record['burial_date'])?.toString(),
    );
    final informant = record['informant'];
    final informantName = informant is Map
        ? informant['full_name']?.toString()
        : null;
    final category = record['burial_category']?.toString();
    final religion = record['religion']?.toString();
    final hasLinkedLot = lot is Map && lot['lot_id'] != null;
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
                          label: hasLinkedLot
                              ? 'Lot ${lotReference(lot)} - ${lotBlockLabel(lot)}'
                              : 'Unassigned lot',
                          color: const Color(0xFF335538),
                        ),
                        if (!hasLinkedLot)
                          _InfoChip(
                            icon: Icons.map_rounded,
                            label: 'Assign on map',
                            color: const Color(0xFF335538),
                          ),
                        if (intermentDate != 'N/A')
                          _InfoChip(
                            icon: Icons.event_available_rounded,
                            label: 'Interment: $intermentDate',
                            color: const Color(0xFF47626F),
                          ),
                        if (category != null && category.isNotEmpty)
                          _InfoChip(
                            icon: Icons.category_rounded,
                            label: category,
                            color: const Color(0xFF6D4C41),
                          ),
                        if (religion != null && religion.isNotEmpty)
                          _InfoChip(
                            icon: Icons.church_rounded,
                            label: religion,
                            color: const Color(0xFF5D5685),
                          ),
                        if (informantName != null && informantName.isNotEmpty)
                          _InfoChip(
                            icon: Icons.assignment_ind_rounded,
                            label: 'Informant: $informantName',
                            color: const Color(0xFF2F4A57),
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
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
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
