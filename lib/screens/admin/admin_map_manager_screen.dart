import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _C {
  static const background = Color(0xFFFBF9F6);
  static const primary = Color(0xFF335538);
  static const primaryContainer = Color(0xFF4B6E4F);
  static const primaryFixed = Color(0xFFC5EDC6);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF5F3F0);
  static const onSurface = Color(0xFF1B1C1A);
  static const onSurfaceVariant = Color(0xFF424841);
  static const outline = Color(0xFF727971);
  static const outlineVariant = Color(0xFFC2C8BF);
  static const secondary = Color(0xFF47626F);
  static const secondaryContainer = Color(0xFFC7E4F3);
  static const onSecondaryContainer = Color(0xFF4B6673);
  static const entrance = Color(0xFFA64DB3);
  static const error = Color(0xFFBA1A1A);
  static const white = Color(0xFFFFFFFF);
}

enum _MapMode { select, plotLot, addNode, connectNodes, setEntrance }

class AdminMapManagerScreen extends ConsumerStatefulWidget {
  const AdminMapManagerScreen({super.key, this.onMenuPressed});

  final VoidCallback? onMenuPressed;

  @override
  ConsumerState<AdminMapManagerScreen> createState() =>
      _AdminMapManagerScreenState();
}

class _AdminMapManagerScreenState extends ConsumerState<AdminMapManagerScreen> {
  static final LatLng _tagumMapCenter = LatLng(7.3793125, 125.753328125);
  static const double _initialZoom = 18;
  static const double _mapLatSpan = 0.0036;
  static const double _mapLngSpan = 0.0046;

  final _mapController = MapController();
  final _mapKey = GlobalKey();
  final _lotNumberController = TextEditingController();
  final _priceController = TextEditingController();

  _MapMode _mode = _MapMode.select;
  double _currentZoom = _initialZoom;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _mapReady = false;

  List<Map<String, dynamic>> _lotMarkers = [];
  List<Map<String, dynamic>> _pathNodes = [];
  List<Map<String, dynamic>> _pathEdges = [];

  double? _entranceXPercent;
  double? _entranceYPercent;
  int? _pendingConnectNodeId;
  Map<String, dynamic>? _selectedMarker;
  Map<String, dynamic>? _selectedNode;
  LatLng? _lastPointer;
  LatLng _currentCenter = _tagumMapCenter;
  int? _draggingNodeId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _lotNumberController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  InputDecoration _mapFieldDecoration({
    required String labelText,
    required IconData icon,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: labelText,
      suffixText: suffixText,
      prefixIcon: Icon(icon, color: _C.primary),
      filled: true,
      fillColor: _C.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _C.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _C.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _C.primary, width: 1.4),
      ),
    );
  }

  Widget _mapDialogTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _C.primaryFixed,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _C.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final supabase = Supabase.instance.client;
      final results = await Future.wait([
        supabase
            .from('cemetery_map')
            .select('entrance_x_percent, entrance_y_percent')
            .order('uploaded_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        supabase
            .from('lot_markers')
            .select(
              'marker_id, lot_id, x_percent, y_percent, cemetery_lot(lot_id, lot_number, price, status, section_id)',
            )
            .order('marker_id'),
        supabase.from('path_nodes').select('*').order('node_id'),
        supabase.from('path_edges').select('*').order('edge_id'),
      ]);

      final mapConfig = results[0] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _entranceXPercent = (mapConfig?['entrance_x_percent'] as num?)
            ?.toDouble();
        _entranceYPercent = (mapConfig?['entrance_y_percent'] as num?)
            ?.toDouble();
        _lotMarkers = List<Map<String, dynamic>>.from(results[1] as List);
        _pathNodes = List<Map<String, dynamic>>.from(results[2] as List);
        _pathEdges = List<Map<String, dynamic>>.from(results[3] as List);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Unable to load map data: $e', error: true);
    }
  }

  Future<void> _saveEntrance(LatLng point) async {
    final (xPercent, yPercent) = _latLngToPercent(point);
    setState(() => _isSaving = true);
    try {
      await _upsertEntrancePercent(xPercent, yPercent);

      setState(() {
        _entranceXPercent = xPercent;
        _entranceYPercent = yPercent;
        _mode = _MapMode.select;
      });
      _snack('Entrance set.');
    } catch (e) {
      _snack('Unable to set entrance: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _upsertEntrancePercent(double xPercent, double yPercent) async {
    final supabase = Supabase.instance.client;
    final latestMap = await supabase
        .from('cemetery_map')
        .select('map_id')
        .order('uploaded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (latestMap == null) {
      await supabase.from('cemetery_map').insert({
        'map_image_url': null,
        'entrance_x_percent': xPercent,
        'entrance_y_percent': yPercent,
        'uploaded_at': DateTime.now().toIso8601String(),
      });
    } else {
      await supabase
          .from('cemetery_map')
          .update({
            'entrance_x_percent': xPercent,
            'entrance_y_percent': yPercent,
          })
          .eq('map_id', latestMap['map_id']);
    }
  }

  Future<void> _deleteEntrance() async {
    if (_entranceXPercent == null || _entranceYPercent == null) {
      _snack('No entrance is currently set.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entrance'),
        content: const Text('Remove the saved cemetery entrance from the map?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: _C.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final latestMap = await Supabase.instance.client
          .from('cemetery_map')
          .select('map_id')
          .order('uploaded_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (latestMap != null) {
        await Supabase.instance.client
            .from('cemetery_map')
            .update({'entrance_x_percent': null, 'entrance_y_percent': null})
            .eq('map_id', latestMap['map_id']);
      }

      setState(() {
        _entranceXPercent = null;
        _entranceYPercent = null;
        if (_mode == _MapMode.setEntrance) _mode = _MapMode.select;
      });
      _snack('Entrance deleted.');
    } catch (e) {
      _snack('Unable to delete entrance: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addNode(LatLng point) async {
    final (xPercent, yPercent) = _latLngToPercent(point);
    setState(() => _isSaving = true);
    try {
      final inserted = await Supabase.instance.client
          .from('path_nodes')
          .insert({
            'x_percent': xPercent,
            'y_percent': yPercent,
            'node_type': 'normal',
          })
          .select()
          .single();

      setState(() {
        _pathNodes.add(Map<String, dynamic>.from(inserted));
        _selectedNode = Map<String, dynamic>.from(inserted);
        _selectedMarker = null;
      });
      _snack('Route node added.');
    } catch (e) {
      _snack('Unable to add node: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _connectNodes(int fromNodeId, int toNodeId) async {
    if (fromNodeId == toNodeId) return;
    final fromNode = _pathNodes.firstWhere((n) => n['node_id'] == fromNodeId);
    final toNode = _pathNodes.firstWhere((n) => n['node_id'] == toNodeId);
    final distance = _coordinateDistanceMeters(
      _nodeToLatLng(fromNode),
      _nodeToLatLng(toNode),
    );

    setState(() => _isSaving = true);
    try {
      final existing = await Supabase.instance.client
          .from('path_edges')
          .select('edge_id')
          .or(
            'and(from_node_id.eq.$fromNodeId,to_node_id.eq.$toNodeId),and(from_node_id.eq.$toNodeId,to_node_id.eq.$fromNodeId)',
          )
          .maybeSingle();

      if (existing != null) {
        _snack('Those nodes are already connected.');
        return;
      }

      final inserted = await Supabase.instance.client
          .from('path_edges')
          .insert({
            'from_node_id': fromNodeId,
            'to_node_id': toNodeId,
            'distance_meters': distance,
          })
          .select()
          .single();

      setState(() {
        _pathEdges.add(Map<String, dynamic>.from(inserted));
        _pendingConnectNodeId = null;
      });
      _snack('Nodes connected.');
    } catch (e) {
      _snack('Unable to connect nodes: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteNode(Map<String, dynamic> node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Node'),
        content: const Text('Remove this route node and its connections?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: _C.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final nodeId = node['node_id'];
      await Supabase.instance.client
          .from('path_edges')
          .delete()
          .or('from_node_id.eq.$nodeId,to_node_id.eq.$nodeId');
      await Supabase.instance.client
          .from('path_nodes')
          .delete()
          .eq('node_id', nodeId);
      setState(() {
        _pathNodes.removeWhere((n) => n['node_id'] == nodeId);
        _pathEdges.removeWhere(
          (e) => e['from_node_id'] == nodeId || e['to_node_id'] == nodeId,
        );
        if (_pendingConnectNodeId == nodeId) _pendingConnectNodeId = null;
        if (_selectedNode?['node_id'] == nodeId) _selectedNode = null;
      });
      _snack('Node deleted.');
    } catch (e) {
      _snack('Unable to delete node: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAllNodes() async {
    if (_pathNodes.isEmpty && _pathEdges.isEmpty) {
      _snack('There are no route nodes to delete.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Nodes'),
        content: Text(
          'Remove all ${_pathNodes.length} route nodes and '
          '${_pathEdges.length} connections? Lots and entrance will stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All', style: TextStyle(color: _C.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('path_edges')
          .delete()
          .neq('edge_id', -1);
      await Supabase.instance.client
          .from('path_nodes')
          .delete()
          .neq('node_id', -1);

      setState(() {
        _pathNodes = [];
        _pathEdges = [];
        _selectedNode = null;
        _pendingConnectNodeId = null;
        if (_mode == _MapMode.connectNodes) _mode = _MapMode.select;
      });
      _snack('All route nodes deleted.');
    } catch (e) {
      _snack('Unable to delete route nodes: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editNode(Map<String, dynamic> node) async {
    final nodeId = node['node_id'] as int;
    final xController = TextEditingController(
      text: ((node['x_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    final yController = TextEditingController(
      text: ((node['y_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    final typeController = TextEditingController(
      text: node['node_type']?.toString() ?? 'normal',
    );

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _C.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: _mapDialogTitle('Edit Node #$nodeId', Icons.alt_route_rounded),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: xController,
                decoration: _mapFieldDecoration(
                  labelText: 'X Percent',
                  icon: Icons.open_with_rounded,
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: yController,
                decoration: _mapFieldDecoration(
                  labelText: 'Y Percent',
                  icon: Icons.open_with_rounded,
                  suffixText: '%',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typeController,
                decoration: _mapFieldDecoration(
                  labelText: 'Node Type',
                  icon: Icons.category_outlined,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: _C.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: _C.primary,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Save Node'),
          ),
        ],
      ),
    );

    final xInput = xController.text.trim();
    final yInput = yController.text.trim();
    final typeInput = typeController.text.trim();
    xController.dispose();
    yController.dispose();
    typeController.dispose();
    if (updated != true) return;

    final xPercent = double.tryParse(xInput);
    final yPercent = double.tryParse(yInput);
    final nodeType = typeInput.isEmpty ? 'normal' : typeInput;

    if (xPercent == null || yPercent == null) {
      _snack('Node coordinates must be valid numbers.', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final savedNode = await Supabase.instance.client
          .from('path_nodes')
          .update({
            'x_percent': xPercent.clamp(0, 100),
            'y_percent': yPercent.clamp(0, 100),
            'node_type': nodeType,
          })
          .eq('node_id', nodeId)
          .select()
          .single();
      final normalizedNode = Map<String, dynamic>.from(savedNode);

      final updatedEdges = <Map<String, dynamic>>[];
      for (final edge in _pathEdges.where(
        (edge) =>
            edge['from_node_id'] == nodeId || edge['to_node_id'] == nodeId,
      )) {
        final fromId = edge['from_node_id'] as int;
        final toId = edge['to_node_id'] as int;
        final fromNode = fromId == nodeId ? normalizedNode : _nodeById(fromId);
        final toNode = toId == nodeId ? normalizedNode : _nodeById(toId);
        if (fromNode == null || toNode == null) continue;

        final distance = _coordinateDistanceMeters(
          _nodeToLatLng(fromNode),
          _nodeToLatLng(toNode),
        );
        final savedEdge = await Supabase.instance.client
            .from('path_edges')
            .update({'distance_meters': distance})
            .eq('edge_id', edge['edge_id'])
            .select()
            .single();
        updatedEdges.add(Map<String, dynamic>.from(savedEdge));
      }

      setState(() {
        final nodeIndex = _pathNodes.indexWhere((n) => n['node_id'] == nodeId);
        if (nodeIndex != -1) _pathNodes[nodeIndex] = normalizedNode;
        _selectedNode = normalizedNode;
        for (final updatedEdge in updatedEdges) {
          final edgeIndex = _pathEdges.indexWhere(
            (edge) => edge['edge_id'] == updatedEdge['edge_id'],
          );
          if (edgeIndex != -1) _pathEdges[edgeIndex] = updatedEdge;
        }
      });
      _snack('Node updated.');
    } catch (e) {
      _snack('Unable to update node: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _startNodeDrag(Map<String, dynamic> node) {
    setState(() {
      _draggingNodeId = node['node_id'] as int;
      _selectedNode = node;
      _selectedMarker = null;
      _pendingConnectNodeId = null;
      _mode = _MapMode.select;
    });
  }

  void _dragNodeToGlobalPosition(int nodeId, Offset globalPosition) {
    final point = _latLngFromGlobalPosition(globalPosition);
    if (point == null) return;
    final (xPercent, yPercent) = _latLngToPercent(point);

    setState(() {
      final index = _pathNodes.indexWhere((node) => node['node_id'] == nodeId);
      if (index == -1) return;

      final updatedNode = Map<String, dynamic>.from(_pathNodes[index])
        ..['x_percent'] = xPercent
        ..['y_percent'] = yPercent;
      _pathNodes[index] = updatedNode;
      _selectedNode = updatedNode;
      _lastPointer = point;
    });
  }

  Future<void> _finishNodeDrag(int nodeId) async {
    setState(() => _draggingNodeId = null);

    final node = _nodeById(nodeId);
    if (node == null) return;

    setState(() => _isSaving = true);
    try {
      final xPercent = (node['x_percent'] as num).toDouble();
      final yPercent = (node['y_percent'] as num).toDouble();
      final savedNode = await Supabase.instance.client
          .from('path_nodes')
          .update({'x_percent': xPercent, 'y_percent': yPercent})
          .eq('node_id', nodeId)
          .select()
          .single();
      final normalizedNode = Map<String, dynamic>.from(savedNode);

      final updatedEdges = <Map<String, dynamic>>[];
      for (final edge in _pathEdges.where(
        (edge) =>
            edge['from_node_id'] == nodeId || edge['to_node_id'] == nodeId,
      )) {
        final fromId = edge['from_node_id'] as int;
        final toId = edge['to_node_id'] as int;
        final fromNode = fromId == nodeId ? normalizedNode : _nodeById(fromId);
        final toNode = toId == nodeId ? normalizedNode : _nodeById(toId);
        if (fromNode == null || toNode == null) continue;

        final distance = _coordinateDistanceMeters(
          _nodeToLatLng(fromNode),
          _nodeToLatLng(toNode),
        );
        final savedEdge = await Supabase.instance.client
            .from('path_edges')
            .update({'distance_meters': distance})
            .eq('edge_id', edge['edge_id'])
            .select()
            .single();
        updatedEdges.add(Map<String, dynamic>.from(savedEdge));
      }

      setState(() {
        final nodeIndex = _pathNodes.indexWhere((n) => n['node_id'] == nodeId);
        if (nodeIndex != -1) _pathNodes[nodeIndex] = normalizedNode;
        _selectedNode = normalizedNode;

        for (final updatedEdge in updatedEdges) {
          final edgeIndex = _pathEdges.indexWhere(
            (edge) => edge['edge_id'] == updatedEdge['edge_id'],
          );
          if (edgeIndex != -1) _pathEdges[edgeIndex] = updatedEdge;
        }
      });
      _snack('Node moved.');
    } catch (e) {
      _snack('Unable to move node: $e', error: true);
      _loadAll();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createLotAt(LatLng point) async {
    final (xPercent, yPercent) = _latLngToPercent(point);
    _lotNumberController.clear();
    _priceController.clear();
    String selectedStatus = 'Available';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _C.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: _mapDialogTitle('Add Lot', Icons.add_location_alt_outlined),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _lotNumberController,
                  decoration: _mapFieldDecoration(
                    labelText: 'Lot Number',
                    icon: Icons.numbers_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _priceController,
                  decoration: _mapFieldDecoration(
                    labelText: 'Price',
                    icon: Icons.payments_outlined,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: _mapFieldDecoration(
                    labelText: 'Status',
                    icon: Icons.info_outline_rounded,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Available',
                      child: Text('Available'),
                    ),
                    DropdownMenuItem(
                      value: 'Reserved',
                      child: Text('Reserved'),
                    ),
                    DropdownMenuItem(
                      value: 'Occupied',
                      child: Text('Occupied'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedStatus = value!),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Map position: ${xPercent.toStringAsFixed(1)}%, ${yPercent.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: _C.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: _C.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Create Lot'),
            ),
          ],
        ),
      ),
    );

    if (created != true) return;
    if (_lotNumberController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty) {
      _snack('Lot number and price are required.', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final lotPoint = _percentToLatLng(xPercent, yPercent);
      final lot = await Supabase.instance.client
          .from('cemetery_lot')
          .insert({
            'lot_number': _lotNumberController.text.trim(),
            'price': double.parse(_priceController.text.trim()),
            'status': selectedStatus,
            'x_coord': lotPoint.longitude,
            'y_coord': lotPoint.latitude,
          })
          .select('lot_id, lot_number, price, status, section_id')
          .single();

      final marker = await Supabase.instance.client
          .from('lot_markers')
          .insert({
            'lot_id': lot['lot_id'],
            'x_percent': xPercent,
            'y_percent': yPercent,
          })
          .select('marker_id, lot_id, x_percent, y_percent')
          .single();

      final newMarker = Map<String, dynamic>.from(marker);
      newMarker['cemetery_lot'] = Map<String, dynamic>.from(lot);
      setState(() {
        _lotMarkers.add(newMarker);
        _selectedMarker = newMarker;
        _mode = _MapMode.select;
      });
      _snack('Lot added.');
    } catch (e) {
      _snack('Unable to add lot: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editLot(Map<String, dynamic> marker) async {
    final lot = Map<String, dynamic>.from(marker['cemetery_lot'] ?? {});
    final lotId = lot['lot_id'];
    if (lotId == null) {
      _snack('This marker is missing lot details.', error: true);
      return;
    }

    final lotNumberController = TextEditingController(
      text: lot['lot_number']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: lot['price']?.toString() ?? '',
    );
    final xController = TextEditingController(
      text: ((marker['x_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    final yController = TextEditingController(
      text: ((marker['y_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    String selectedStatus = lot['status']?.toString() ?? 'Available';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _C.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: _mapDialogTitle(
            'Edit Lot ${lot['lot_number'] ?? ''}'.trim(),
            Icons.edit_location_alt_outlined,
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: lotNumberController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Lot Number',
                      icon: Icons.numbers_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Price',
                      icon: Icons.payments_outlined,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: _mapFieldDecoration(
                      labelText: 'Status',
                      icon: Icons.info_outline_rounded,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Available',
                        child: Text('Available'),
                      ),
                      DropdownMenuItem(
                        value: 'Reserved',
                        child: Text('Reserved'),
                      ),
                      DropdownMenuItem(
                        value: 'Occupied',
                        child: Text('Occupied'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedStatus = value!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: xController,
                          decoration: _mapFieldDecoration(
                            labelText: 'X Percent',
                            icon: Icons.open_with_rounded,
                            suffixText: '%',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: yController,
                          decoration: _mapFieldDecoration(
                            labelText: 'Y Percent',
                            icon: Icons.open_with_rounded,
                            suffixText: '%',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: _C.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Save Lot'),
            ),
          ],
        ),
      ),
    );

    final lotNumber = lotNumberController.text.trim();
    final priceInput = priceController.text.trim();
    final xInput = xController.text.trim();
    final yInput = yController.text.trim();
    lotNumberController.dispose();
    priceController.dispose();
    xController.dispose();
    yController.dispose();
    if (saved != true) return;

    final price = double.tryParse(priceInput);
    final xPercent = double.tryParse(xInput);
    final yPercent = double.tryParse(yInput);
    if (lotNumber.isEmpty ||
        price == null ||
        xPercent == null ||
        yPercent == null) {
      _snack('Lot number, price, and position are required.', error: true);
      return;
    }

    final normalizedX = xPercent.clamp(0, 100).toDouble();
    final normalizedY = yPercent.clamp(0, 100).toDouble();
    setState(() => _isSaving = true);
    try {
      final updatedLot = await Supabase.instance.client
          .from('cemetery_lot')
          .update({
            'lot_number': lotNumber,
            'price': price,
            'status': selectedStatus,
            'x_coord': _percentToLatLng(normalizedX, normalizedY).longitude,
            'y_coord': _percentToLatLng(normalizedX, normalizedY).latitude,
          })
          .eq('lot_id', lotId)
          .select('lot_id, lot_number, price, status, section_id')
          .single();

      final updatedMarker = await Supabase.instance.client
          .from('lot_markers')
          .update({'x_percent': normalizedX, 'y_percent': normalizedY})
          .eq('marker_id', marker['marker_id'])
          .select('marker_id, lot_id, x_percent, y_percent')
          .single();

      final normalizedMarker = Map<String, dynamic>.from(updatedMarker);
      normalizedMarker['cemetery_lot'] = Map<String, dynamic>.from(updatedLot);

      setState(() {
        final index = _lotMarkers.indexWhere(
          (m) => m['marker_id'] == marker['marker_id'],
        );
        if (index != -1) _lotMarkers[index] = normalizedMarker;
        _selectedMarker = normalizedMarker;
        _selectedNode = null;
      });
      _snack('Lot updated.');
    } catch (e) {
      _snack('Unable to update lot: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteLot(Map<String, dynamic> marker) async {
    final lot = marker['cemetery_lot'] ?? {};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Lot ${lot['lot_number'] ?? ''}'.trim()),
        content: const Text(
          'This removes the map marker and its lot record. Records linked to this lot may prevent deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: _C.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('lot_markers')
          .delete()
          .eq('marker_id', marker['marker_id']);
      if (marker['lot_id'] != null) {
        await Supabase.instance.client
            .from('cemetery_lot')
            .delete()
            .eq('lot_id', marker['lot_id']);
      }

      setState(() {
        _lotMarkers.removeWhere((m) => m['marker_id'] == marker['marker_id']);
        if (_selectedMarker?['marker_id'] == marker['marker_id']) {
          _selectedMarker = null;
        }
      });
      _snack('Lot deleted.');
    } catch (e) {
      _snack('Unable to delete lot: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    _lastPointer = point;
    if (_mode == _MapMode.setEntrance) {
      _saveEntrance(point);
    } else if (_mode == _MapMode.addNode) {
      _addNode(point);
    } else if (_mode == _MapMode.plotLot) {
      _createLotAt(point);
    }
  }

  void _handleNodeTap(Map<String, dynamic> node) {
    if (_mode == _MapMode.connectNodes) {
      if (_pendingConnectNodeId == null) {
        setState(() => _pendingConnectNodeId = node['node_id'] as int);
        _snack('First node selected. Tap another node to connect.');
      } else {
        _connectNodes(_pendingConnectNodeId!, node['node_id'] as int);
      }
    } else if (_mode == _MapMode.addNode) {
      _snack('Tap an empty map area to add a node.');
    } else {
      setState(() {
        _selectedNode = node;
        _selectedMarker = null;
      });
    }
  }

  void _selectMarker(Map<String, dynamic> marker) {
    setState(() {
      _selectedMarker = marker;
      _selectedNode = null;
      _mode = _MapMode.select;
    });
  }

  void _setMode(_MapMode mode) {
    setState(() {
      _mode = mode;
      if (mode != _MapMode.connectNodes) _pendingConnectNodeId = null;
    });
  }

  void _zoomBy(double delta) {
    _currentZoom = (_currentZoom + delta).clamp(14.0, 20.0);
    _moveMap(_currentCenter, _currentZoom);
  }

  void _resetView() {
    _currentZoom = _initialZoom;
    _moveMap(_tagumMapCenter, _currentZoom);
  }

  void _moveMap(LatLng center, double zoom) {
    _currentCenter = center;
    _currentZoom = zoom;
    if (_mapReady) {
      _mapController.move(center, zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: _C.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : Stack(
              children: [
                Positioned.fill(child: _buildMap()),
                _buildLeftToolbar(),
                _buildCoordinatesHud(),
                _buildBottomHint(),
                if (_isSaving)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: _C.primary,
                    ),
                  ),
                if (isDesktop)
                  _selectedNode == null
                      ? _buildActivePlotPanel()
                      : _buildActiveNodePanel(),
              ],
            ),
    );
  }

  Widget _buildMap() {
    final routePoints = _selectedMarker == null
        ? <LatLng>[]
        : _routeFromEntranceToLot(_selectedMarker!);

    return Container(
      key: _mapKey,
      color: _C.background,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _tagumMapCenter,
          initialZoom: _initialZoom,
          minZoom: 14,
          maxZoom: 20,
          onMapReady: () {
            if (mounted) {
              setState(() => _mapReady = true);
            } else {
              _mapReady = true;
            }
          },
          onTap: _handleMapTap,
          onPositionChanged: (position, hasGesture) {
            _currentZoom = position.zoom;
            _currentCenter = position.center;
            _lastPointer = position.center;
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.cemetery_app',
            maxZoom: 20,
          ),
          PolylineLayer(
            polylines: [
              ..._edgePolylines(),
              if (routePoints.length > 1)
                Polyline(
                  points: routePoints,
                  color: _C.primary,
                  strokeWidth: 5,
                ),
            ],
          ),
          MarkerLayer(markers: _mapMarkers()),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }

  List<Polyline> _edgePolylines() {
    return _pathEdges.expand((edge) {
      final from = _nodeById(edge['from_node_id']);
      final to = _nodeById(edge['to_node_id']);
      if (from == null || to == null) return <Polyline>[];
      return [
        Polyline(
          points: [_nodeToLatLng(from), _nodeToLatLng(to)],
          color: const Color(0xFF3147E8).withValues(alpha: 0.86),
          strokeWidth: 4,
        ),
      ];
    }).toList();
  }

  List<Marker> _mapMarkers() {
    return [
      if (_entranceXPercent != null && _entranceYPercent != null)
        Marker(
          point: _entranceLatLng,
          width: 58,
          height: 58,
          child: _mapBadge(Icons.login_rounded, _C.entrance),
        ),
      ..._lotMarkers.map((marker) {
        final selected = marker['marker_id'] == _selectedMarker?['marker_id'];
        final lot = marker['cemetery_lot'] ?? {};
        final status = lot['status']?.toString() ?? 'Available';
        return Marker(
          point: _markerToLatLng(marker),
          width: selected ? 54 : 38,
          height: selected ? 54 : 38,
          child: GestureDetector(
            onTap: () => _selectMarker(marker),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              scale: selected ? 1.2 : 1,
              child: _mapBadge(Icons.location_on_rounded, _statusColor(status)),
            ),
          ),
        );
      }),
      ..._pathNodes.map((node) {
        final selected =
            _pendingConnectNodeId == node['node_id'] ||
            _selectedNode?['node_id'] == node['node_id'];
        final dragging = _draggingNodeId == node['node_id'];
        return Marker(
          point: _nodeToLatLng(node),
          width: dragging || selected ? 40 : 28,
          height: dragging || selected ? 40 : 28,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleNodeTap(node),
            onLongPress: () => _deleteNode(node),
            onPanStart: (_) => _startNodeDrag(node),
            onPanUpdate: (details) {
              final nodeId = node['node_id'] as int;
              _dragNodeToGlobalPosition(nodeId, details.globalPosition);
            },
            onPanEnd: (_) => _finishNodeDrag(node['node_id'] as int),
            onPanCancel: () {
              final nodeId = node['node_id'] as int;
              _finishNodeDrag(nodeId);
            },
            child: Container(
              decoration: BoxDecoration(
                color: _pendingConnectNodeId == node['node_id']
                    ? Colors.orange
                    : dragging
                    ? const Color(0xFF3147E8)
                    : selected
                    ? _C.secondary
                    : const Color(0xFF6D4C41),
                shape: BoxShape.circle,
                border: Border.all(color: _C.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    ];
  }

  Widget _mapBadge(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: _C.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: _C.white, size: 20),
    );
  }

  Widget _buildLeftToolbar() {
    return Positioned(
      left: 24,
      top: 0,
      bottom: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 224),
          child: _panel(
            radius: 18,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 4, 6, 8),
                    child: Text(
                      'Map Actions',
                      style: TextStyle(
                        color: _C.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _ActionButton(
                    icon: Icons.add_location_alt_rounded,
                    label: 'Add Node',
                    selected: _mode == _MapMode.addNode,
                    onTap: () => _setMode(_MapMode.addNode),
                  ),
                  _ActionButton(
                    icon: Icons.add_business_rounded,
                    label: 'Add Lot',
                    selected: _mode == _MapMode.plotLot,
                    onTap: () => _setMode(_MapMode.plotLot),
                  ),
                  _ActionButton(
                    icon: Icons.login_rounded,
                    label: 'Add Entrance',
                    selected: _mode == _MapMode.setEntrance,
                    onTap: () => _setMode(_MapMode.setEntrance),
                  ),
                  _ActionButton(
                    icon: Icons.link_rounded,
                    label: 'Connect Nodes',
                    selected: _mode == _MapMode.connectNodes,
                    onTap: () => _setMode(_MapMode.connectNodes),
                  ),
                  const Divider(height: 18, color: _C.outlineVariant),
                  _ActionButton(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Delete All Nodes',
                    danger: true,
                    onTap: _deleteAllNodes,
                  ),
                  _ActionButton(
                    icon: Icons.wrong_location_rounded,
                    label: 'Delete Entrance',
                    danger: true,
                    enabled:
                        _entranceXPercent != null && _entranceYPercent != null,
                    onTap: _deleteEntrance,
                  ),
                  if (_selectedNode != null)
                    _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete Selected Node',
                      danger: true,
                      onTap: () => _deleteNode(_selectedNode!),
                    ),
                  if (_selectedMarker != null)
                    _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete Selected Lot',
                      danger: true,
                      onTap: () => _deleteLot(_selectedMarker!),
                    ),
                  const Divider(height: 18, color: _C.outlineVariant),
                  Row(
                    children: [
                      Expanded(
                        child: _SmallActionButton(
                          icon: Icons.zoom_in_rounded,
                          tooltip: 'Zoom In',
                          onTap: () => _zoomBy(0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SmallActionButton(
                          icon: Icons.zoom_out_rounded,
                          tooltip: 'Zoom Out',
                          onTap: () => _zoomBy(-0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SmallActionButton(
                          icon: Icons.my_location_rounded,
                          tooltip: 'Center Map',
                          onTap: _resetView,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoordinatesHud() {
    final pointer = _lastPointer ?? _currentCenter;
    final (x, y) = _latLngToPercent(pointer);
    return Positioned(
      top: 24,
      right: 24,
      child: _panel(
        alpha: 0.82,
        radius: 999,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _hudText('X:', x.toStringAsFixed(2)),
              const SizedBox(width: 14),
              _hudText('Y:', y.toStringAsFixed(2)),
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: _C.outlineVariant,
              ),
              _hudText('Status:', _modeLabel.toUpperCase(), active: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hudText(String label, String value, {bool active = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _C.outline,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: active ? _C.primary : _C.secondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomHint() {
    final selectedLot = _selectedMarker?['cemetery_lot'];
    final selectedNode = _selectedNode;
    final hasEntrance = _entranceXPercent != null && _entranceYPercent != null;
    final title = selectedNode != null
        ? 'Selected Node #${selectedNode['node_id']}'
        : selectedLot == null
        ? 'Click a lot to assign details'
        : 'Selected Lot ${selectedLot['lot_number'] ?? '--'}';
    final subtitle = selectedNode != null
        ? 'Edit its coordinates, connect it to another node, or delete it from the route network.'
        : selectedLot == null
        ? 'Plot lots, add route nodes, then connect nodes to build walkable routes.'
        : hasEntrance
        ? 'Route preview connects the entrance to the selected lot through nearby nodes.'
        : 'Set an entrance to preview visitor routes to this lot.';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _panel(
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: _C.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      color: _C.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _C.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: _C.outline,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: selectedNode != null
                        ? () => _showNodeActions(selectedNode)
                        : selectedLot == null
                        ? null
                        : () => _showLotActions(_selectedMarker!),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivePlotPanel() {
    final marker = _selectedMarker;
    final lot = marker?['cemetery_lot'] ?? {};
    final lotNumber = lot['lot_number']?.toString() ?? '--';
    final status = lot['status']?.toString() ?? 'No selection';
    final price = lot['price']?.toString() ?? '--';
    return Positioned(
      top: 96,
      right: 24,
      width: 288,
      child: _panel(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: _C.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'PLOT SELECTION',
                        style: TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Icon(
                        Icons.info_outline_rounded,
                        color: _C.white,
                        size: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    marker == null ? 'No Plot Selected' : 'Lot $lotNumber',
                    style: const TextStyle(
                      color: _C.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    marker == null
                        ? 'Tap a marker on the map'
                        : 'Marker ID: ${marker['marker_id']}',
                    style: const TextStyle(color: Color(0xDDFFFFFF)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _infoRow('Status', status, badge: marker != null),
                  const SizedBox(height: 10),
                  _infoRow('Price', price == '--' ? price : 'PHP $price'),
                  const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: marker == null ? null : () => _editLot(marker),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit Details'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.primaryContainer,
                        foregroundColor: _C.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: marker == null
                          ? null
                          : () => _moveMap(_markerToLatLng(marker), 19),
                      icon: const Icon(Icons.alt_route_rounded, size: 16),
                      label: Text(
                        _entranceXPercent == null || _entranceYPercent == null
                            ? 'Focus Lot'
                            : 'View Route',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.onSurface,
                        side: const BorderSide(color: _C.outline),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: marker == null
                          ? null
                          : () => _deleteLot(marker),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Delete Lot'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.error,
                        side: const BorderSide(color: _C.error),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveNodePanel() {
    final node = _selectedNode;
    final nodeId = node?['node_id']?.toString() ?? '--';
    final xPercent = ((node?['x_percent'] as num?)?.toDouble() ?? 0)
        .toStringAsFixed(2);
    final yPercent = ((node?['y_percent'] as num?)?.toDouble() ?? 0)
        .toStringAsFixed(2);
    final nodeType = node?['node_type']?.toString() ?? 'normal';
    final connections = node == null
        ? 0
        : _pathEdges
              .where(
                (edge) =>
                    edge['from_node_id'] == node['node_id'] ||
                    edge['to_node_id'] == node['node_id'],
              )
              .length;

    return Positioned(
      top: 96,
      right: 24,
      width: 288,
      child: _panel(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: _C.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'NODE SELECTION',
                        style: TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Icon(Icons.polyline_rounded, color: _C.white, size: 16),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Node #$nodeId',
                    style: const TextStyle(
                      color: _C.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Type: $nodeType',
                    style: const TextStyle(color: Color(0xDDFFFFFF)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _infoRow('X Position', '$xPercent%'),
                  const SizedBox(height: 10),
                  _infoRow('Y Position', '$yPercent%'),
                  const SizedBox(height: 10),
                  _infoRow('Connections', connections.toString()),
                  const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: node == null ? null : () => _editNode(node),
                      icon: const Icon(
                        Icons.edit_location_alt_rounded,
                        size: 16,
                      ),
                      label: const Text('Edit Node'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.primaryContainer,
                        foregroundColor: _C.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: node == null ? null : () => _deleteNode(node),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Delete Node'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.error,
                        side: const BorderSide(color: _C.error),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool badge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _C.outline)),
        badge
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _C.primaryFixed,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  value.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF00210A),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : Text(
                value,
                style: const TextStyle(
                  color: _C.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ],
    );
  }

  Future<void> _showLotActions(Map<String, dynamic> marker) async {
    final lot = marker['cemetery_lot'] ?? {};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _C.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lot ${lot['lot_number'] ?? '--'}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Status: ${lot['status'] ?? '--'}'),
            Text('Price: ${lot['price'] ?? '--'}'),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _moveMap(_markerToLatLng(marker), 19);
                    },
                    icon: const Icon(Icons.alt_route_rounded),
                    label: Text(
                      _entranceXPercent == null || _entranceYPercent == null
                          ? 'Focus'
                          : 'Route',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editLot(marker);
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                    style: FilledButton.styleFrom(backgroundColor: _C.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteLot(marker);
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete Lot'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _C.error,
                  side: const BorderSide(color: _C.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNodeActions(Map<String, dynamic> node) async {
    final nodeId = node['node_id'];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _C.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Node #$nodeId',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Type: ${node['node_type'] ?? 'normal'}'),
            Text(
              'Position: ${((node['x_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}%, '
              '${((node['y_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}%',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editNode(node);
                    },
                    icon: const Icon(Icons.edit_location_alt_rounded),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteNode(node);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                    style: FilledButton.styleFrom(backgroundColor: _C.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child, double radius = 18, double alpha = 1}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: _C.surfaceContainerLowest.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _C.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  List<LatLng> _routeFromEntranceToLot(Map<String, dynamic> marker) {
    if (_entranceXPercent == null || _entranceYPercent == null) return [];
    final start = _entranceLatLng;
    final end = _markerToLatLng(marker);
    if (_pathNodes.isEmpty) return [start, end];

    final startNode = _nearestNodeTo(start);
    final endNode = _nearestNodeTo(end);
    if (startNode == null || endNode == null) return [start, end];

    final nodePath = _shortestNodePath(
      startNode['node_id'] as int,
      endNode['node_id'] as int,
    );
    if (nodePath.isEmpty) {
      return [start, _nodeToLatLng(startNode), _nodeToLatLng(endNode), end];
    }
    return [
      start,
      ...nodePath.map((nodeId) => _nodeToLatLng(_nodeById(nodeId)!)),
      end,
    ];
  }

  List<int> _shortestNodePath(int startId, int endId) {
    if (startId == endId) return [startId];
    final graph = <int, List<({int nodeId, double distance})>>{};
    for (final edge in _pathEdges) {
      final from = edge['from_node_id'] as int;
      final to = edge['to_node_id'] as int;
      final fromNode = _nodeById(from);
      final toNode = _nodeById(to);
      if (fromNode == null || toNode == null) continue;
      final distance = _coordinateDistanceMeters(
        _nodeToLatLng(fromNode),
        _nodeToLatLng(toNode),
      );
      graph.putIfAbsent(from, () => []).add((nodeId: to, distance: distance));
      graph.putIfAbsent(to, () => []).add((nodeId: from, distance: distance));
    }

    final distances = <int, double>{startId: 0};
    final previous = <int, int>{};
    final visited = <int>{};

    while (true) {
      int? current;
      double best = double.infinity;
      for (final entry in distances.entries) {
        if (!visited.contains(entry.key) && entry.value < best) {
          current = entry.key;
          best = entry.value;
        }
      }
      if (current == null || current == endId) break;
      visited.add(current);
      for (final neighbor in graph[current] ?? []) {
        final nextDistance = best + neighbor.distance;
        if (nextDistance < (distances[neighbor.nodeId] ?? double.infinity)) {
          distances[neighbor.nodeId] = nextDistance;
          previous[neighbor.nodeId] = current;
        }
      }
    }

    if (!distances.containsKey(endId)) return [];
    final path = <int>[endId];
    while (path.first != startId) {
      path.insert(0, previous[path.first]!);
    }
    return path;
  }

  Map<String, dynamic>? _nearestNodeTo(LatLng point) {
    if (_pathNodes.isEmpty) return null;
    Map<String, dynamic>? nearest;
    double nearestDistance = double.infinity;
    for (final node in _pathNodes) {
      final distance = _coordinateDistanceMeters(point, _nodeToLatLng(node));
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = node;
      }
    }
    return nearest;
  }

  Map<String, dynamic>? _nodeById(int id) {
    for (final node in _pathNodes) {
      if (node['node_id'] == id) return node;
    }
    return null;
  }

  LatLng get _entranceLatLng {
    if (_entranceXPercent == null || _entranceYPercent == null) {
      return _tagumMapCenter;
    }
    return _percentToLatLng(_entranceXPercent!, _entranceYPercent!);
  }

  LatLng _markerToLatLng(Map<String, dynamic> marker) {
    return _percentToLatLng(
      (marker['x_percent'] as num).toDouble(),
      (marker['y_percent'] as num).toDouble(),
    );
  }

  LatLng _nodeToLatLng(Map<String, dynamic> node) {
    return _percentToLatLng(
      (node['x_percent'] as num).toDouble(),
      (node['y_percent'] as num).toDouble(),
    );
  }

  LatLng _percentToLatLng(double xPercent, double yPercent) {
    final latOffset = (0.5 - yPercent / 100) * _mapLatSpan;
    final lngOffset = (xPercent / 100 - 0.5) * _mapLngSpan;
    return LatLng(
      _tagumMapCenter.latitude + latOffset,
      _tagumMapCenter.longitude + lngOffset,
    );
  }

  (double, double) _latLngToPercent(LatLng point) {
    final x =
        ((point.longitude - _tagumMapCenter.longitude) / _mapLngSpan + 0.5) *
        100;
    final y =
        (0.5 - (point.latitude - _tagumMapCenter.latitude) / _mapLatSpan) * 100;
    return (x.clamp(0, 100).toDouble(), y.clamp(0, 100).toDouble());
  }

  LatLng? _latLngFromGlobalPosition(Offset globalPosition) {
    final context = _mapKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !_mapReady) return null;

    final localPosition = renderObject.globalToLocal(globalPosition);
    return _mapController.camera.screenOffsetToLatLng(localPosition);
  }

  (double, double) _latLngToLocalMeters(LatLng point) {
    const earthRadiusMeters = 6371000.0;
    final centerLatRadians = _degreesToRadians(_tagumMapCenter.latitude);
    final x =
        _degreesToRadians(point.longitude - _tagumMapCenter.longitude) *
        earthRadiusMeters *
        cos(centerLatRadians);
    final y =
        _degreesToRadians(point.latitude - _tagumMapCenter.latitude) *
        earthRadiusMeters;
    return (x, y);
  }

  double _coordinateDistanceMeters(LatLng a, LatLng b) {
    final (ax, ay) = _latLngToLocalMeters(a);
    final (bx, by) = _latLngToLocalMeters(b);
    final dx = bx - ax;
    final dy = by - ay;
    return sqrt(dx * dx + dy * dy);
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;

  Color _statusColor(String status) {
    if (status == 'Occupied') return _C.error;
    if (status == 'Reserved') return Colors.orange;
    return _C.primary;
  }

  String get _modeLabel => switch (_mode) {
    _MapMode.select => 'Active Edit',
    _MapMode.plotLot => 'Plot Lot',
    _MapMode.addNode => 'Add Node',
    _MapMode.connectNodes => 'Connect Nodes',
    _MapMode.setEntrance => 'Set Entrance',
  };

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _C.error : _C.primary,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = danger ? _C.error : _C.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: foreground,
          disabledForegroundColor: _C.outline,
          backgroundColor: selected
              ? _C.primaryFixed
              : danger
              ? _C.error.withValues(alpha: 0.08)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: _C.surfaceContainerLow,
          foregroundColor: _C.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
