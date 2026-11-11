import 'package:flutter/material.dart';

import '../../services/admin_grave_service.dart';
import '../../utils/apartment_crypt.dart';
import '../../utils/lot_formatters.dart';
import 'admin_lots_screen.dart';

class AdminApartmentCryptGridScreen extends StatefulWidget {
  const AdminApartmentCryptGridScreen({
    super.key,
    this.apartmentCrypt,
    this.onBackToMap,
  });

  final Map<String, dynamic>? apartmentCrypt;
  final VoidCallback? onBackToMap;

  @override
  State<AdminApartmentCryptGridScreen> createState() =>
      _AdminApartmentCryptGridScreenState();
}

class _AdminApartmentCryptGridScreenState
    extends State<AdminApartmentCryptGridScreen> {
  static const _cryptColumns = 20;

  // Number faces from the top-right in a serpentine pattern.
  int _slotForCell(int index) {
    final row = index ~/ _cryptColumns;
    final column = index % _cryptColumns;
    final rowStart = row * _cryptColumns;
    return row.isEven
        ? rowStart + (_cryptColumns - column)
        : rowStart + column + 1;
  }

  String _wing = 'A';
  bool _loading = false;
  String? _error;
  int _legacyRecordCount = 0;
  final Map<String, Map<String, dynamic>> _gravesBySlot = {};

  int? get _lotId =>
      int.tryParse(widget.apartmentCrypt?['lot_id']?.toString() ?? '');

  @override
  void initState() {
    super.initState();
    _loadGraves();
  }

  @override
  void didUpdateWidget(AdminApartmentCryptGridScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.apartmentCrypt?['lot_id']?.toString();
    final newId = widget.apartmentCrypt?['lot_id']?.toString();
    if (oldId != newId) {
      _wing = 'A';
      _loadGraves();
    }
  }

  Future<void> _loadGraves() async {
    final lotId = _lotId;
    if (lotId == null) {
      if (mounted) {
        setState(() {
          _gravesBySlot.clear();
          _legacyRecordCount = 0;
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final grouped = await AdminGraveService.loadGravesByLotIds([lotId]);
      final slots = <String, Map<String, dynamic>>{};
      var legacyCount = 0;
      for (final grave in grouped[lotId.toString()] ?? const []) {
        final parsed = parseApartmentCryptLabel(
          grave['grave_label']?.toString(),
        );
        if (parsed == null) {
          legacyCount++;
          continue;
        }
        slots[apartmentCryptSlotCode(parsed.wing, parsed.slot)] = grave;
      }
      if (!mounted || _lotId != lotId) return;
      setState(() {
        _gravesBySlot
          ..clear()
          ..addAll(slots);
        _legacyRecordCount = legacyCount;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || _lotId != lotId) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _editSlot(int slot) async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AdminLotsScreen(initialLot: widget.apartmentCrypt),
      ),
    );
    if (result != null) await _loadGraves();
    return;
    // Face labels remain managed by the dedicated crypt-label workflow below.
    final lotId = _lotId;
    if (lotId == null) return;
    final code = apartmentCryptSlotCode(_wing, slot);
    final existing = _gravesBySlot[code];
    final parsed = parseApartmentCryptLabel(
      existing?['grave_label']?.toString(),
    );
    final labelController = TextEditingController(
      text: parsed?.customLabel ?? '',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null ? 'Label crypt $code' : 'Edit crypt $code',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The location code $code stays fixed so this crypt always remains in the correct grid cell.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: labelController,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Custom label (optional)',
                  hintText: 'Example: Santos Family',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
              if (existing != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Status: ${existing['status'] ?? 'Available'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save label'),
          ),
        ],
      ),
    );

    final customLabel = labelController.text.trim();
    labelController.dispose();
    if (save != true || !mounted) return;

    final graveLabel = apartmentCryptLabel(
      wing: _wing,
      slot: slot,
      customLabel: customLabel,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = existing == null
          ? await AdminGraveService.addGrave(
              lotId: lotId,
              graveLabel: graveLabel,
              status: 'Available',
            )
          : await AdminGraveService.updateGraveLabel(
              graveId: int.parse(existing['grave_id'].toString()),
              graveLabel: graveLabel,
            );
      if (!mounted || _lotId != lotId) return;
      setState(() {
        _gravesBySlot[code] = saved;
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Crypt $code label saved.')));
    } catch (error) {
      if (!mounted || _lotId != lotId) return;
      setState(() {
        _loading = false;
        _error = 'Unable to save $code: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.apartmentCrypt;
    if (lot == null || _lotId == null) return _buildEmptyState(context);

    final colors = Theme.of(context).colorScheme;
    final reference = lotReference(lot, fallback: 'Apartment Crypt');
    final savedCount = _gravesBySlot.keys
        .where((code) => code.startsWith('$_wing-'))
        .length;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.onBackToMap != null)
                  IconButton.filledTonal(
                    tooltip: 'Back to cemetery map',
                    onPressed: widget.onBackToMap,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                if (widget.onBackToMap != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reference,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        'Apartment crypt grid - 20 columns by 5 levels per wing',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh crypts',
                  onPressed: _loading ? null : _loadGraves,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'A', label: Text('Wing A')),
                    ButtonSegment(value: 'B', label: Text('Wing B')),
                  ],
                  selected: {_wing},
                  onSelectionChanged: (value) =>
                      setState(() => _wing = value.first),
                ),
                Text('$savedCount of 100 crypt labels saved'),
                const _StatusLegend(),
              ],
            ),
            if (_legacyRecordCount > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$_legacyRecordCount older grave record(s) do not use an A-001/B-001 grid code and were left unchanged.',
                style: TextStyle(color: colors.error),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: _loadGraves,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InteractiveViewer(
                      minScale: 0.55,
                      maxScale: 3,
                      constrained: false,
                      alignment: Alignment.topLeft,
                      boundaryMargin: const EdgeInsets.all(100),
                      child: SizedBox(
                        // Keep every crypt face comfortably tappable on a
                        // phone. The 20-column layout can then be panned or
                        // pinch-zoomed instead of being squeezed into view.
                        width: 1344,
                        height: 420,
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 20,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                                childAspectRatio: 1.15,
                              ),
                          itemCount: 100,
                          itemBuilder: (context, index) {
                            final slot = _slotForCell(index);
                            final code = apartmentCryptSlotCode(_wing, slot);
                            return _CryptCell(
                              code: code,
                              grave: _gravesBySlot[code],
                              onTap: () => _editSlot(slot),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_loading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x22FFFFFF),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Drag to see every column; pinch to zoom. Select a cell to save or edit its label.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.apartment_rounded, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Select an apartment crypt on the map',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Its Wing A and Wing B crypt grid will open here automatically.',
                  textAlign: TextAlign.center,
                ),
                if (widget.onBackToMap != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: widget.onBackToMap,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open cemetery map'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CryptCell extends StatelessWidget {
  const _CryptCell({
    required this.code,
    required this.grave,
    required this.onTap,
  });

  final String code;
  final Map<String, dynamic>? grave;
  final VoidCallback onTap;

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = grave?['status']?.toString() ?? 'Unlabeled';
    final parsed = parseApartmentCryptLabel(grave?['grave_label']?.toString());
    final customLabel = parsed?.customLabel ?? '';
    final deceasedName = (grave?['burial'] is Map)
        ? (grave!['burial']['name_of_deceased']?.toString() ?? '')
        : '';
    final occupantLabel = _initials(deceasedName);
    final fill = switch (status.toLowerCase()) {
      'occupied' => colors.errorContainer,
      'reserved' => colors.tertiaryContainer,
      'available' => colors.primaryContainer,
      _ => colors.surfaceContainerHighest,
    };
    final foreground = switch (status.toLowerCase()) {
      'occupied' => colors.onErrorContainer,
      'reserved' => colors.onTertiaryContainer,
      'available' => colors.onPrimaryContainer,
      _ => colors.onSurfaceVariant,
    };

    return Tooltip(
      message: deceasedName.trim().isNotEmpty
          ? deceasedName.trim()
          : customLabel.isEmpty
          ? '$code - $status'
          : '$code - $customLabel - $status',
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  occupantLabel.isEmpty ? code : occupantLabel,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (occupantLabel.isNotEmpty)
                  Text(code, style: TextStyle(color: foreground, fontSize: 7)),
                if (customLabel.isNotEmpty)
                  Text(
                    customLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      children: [
        _LegendItem(color: colors.surfaceContainerHighest, label: 'Unlabeled'),
        _LegendItem(color: colors.primaryContainer, label: 'Available'),
        _LegendItem(color: colors.tertiaryContainer, label: 'Reserved'),
        _LegendItem(color: colors.errorContainer, label: 'Occupied'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
