import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_delete_service.dart';
import '../../services/admin_grave_service.dart';
import '../../services/admin_lot_owner_service.dart';
import '../../services/audit_service.dart';
import '../../services/map_feature_service.dart';
import '../../utils/lot_formatters.dart';
import '../../utils/map_feature_geometry.dart';
import '../../widgets/app_date_field.dart';

const _lotColumnsSelect =
    'lot_id, lot_number, lot_label, block_number, lot_class_type, price, status, qgis_feature_id, polygon_geo, burial_record(burial_id, name_of_deceased, birth_date, death_date, burial_date, interment_date, burial_category, lot_id)';
const _lotMarkerSelect =
    'marker_id, lot_id, x_percent, y_percent, cemetery_lot($_lotColumnsSelect)';

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
  const AdminMapManagerScreen({
    super.key,
    this.onMenuPressed,
    this.refreshToken = 0,
  });

  final VoidCallback? onMenuPressed;
  final int refreshToken;

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
  final _blockNumberController = TextEditingController();
  final _lotNumberController = TextEditingController();
  final _lotLabelController = TextEditingController();
  final _lotClassTypeController = TextEditingController();
  final _priceController = TextEditingController();
  final LayerHitNotifier<String> _lotPolygonHitNotifier = ValueNotifier(null);
  RealtimeChannel? _lotChangesChannel;

  _MapMode _mode = _MapMode.select;
  double _currentZoom = _initialZoom;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _mapReady = false;

  List<Map<String, dynamic>> _lotMarkers = [];
  List<Map<String, dynamic>> _pathNodes = [];
  List<Map<String, dynamic>> _pathEdges = [];
  List<Map<String, dynamic>> _mapFeatures = [];
  Map<String, Map<String, dynamic>> _ownershipByLotId = {};

  double? _entranceXPercent;
  double? _entranceYPercent;
  int? _pendingConnectNodeId;
  Map<String, dynamic>? _selectedMarker;
  Map<String, dynamic>? _selectedNode;
  LatLng? _lastPointer;
  LatLng _mapCenter = _tagumMapCenter;
  double _activeMapLatSpan = _mapLatSpan;
  double _activeMapLngSpan = _mapLngSpan;
  LatLng _currentCenter = _tagumMapCenter;
  int? _draggingNodeId;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeToLotChanges();
  }

  @override
  void didUpdateWidget(AdminMapManagerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    final lotChangesChannel = _lotChangesChannel;
    if (lotChangesChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(lotChangesChannel));
    }
    _blockNumberController.dispose();
    _lotNumberController.dispose();
    _lotLabelController.dispose();
    _lotClassTypeController.dispose();
    _priceController.dispose();
    _lotPolygonHitNotifier.dispose();
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
            .select(
              'entrance_x_percent, entrance_y_percent, center_lat, center_lng, lat_span, lng_span',
            )
            .order('uploaded_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        supabase
            .from('lot_markers')
            .select(_lotMarkerSelect)
            .order('marker_id'),
        supabase.from('path_nodes').select('*').order('node_id'),
        supabase.from('path_edges').select('*').order('edge_id'),
        supabase
            .from('lot_ownership')
            .select('''
              ownership_id,
              user_id,
              lot_id,
              total_months,
              months_paid,
              status,
              user:user_id (
                name,
                email,
                phone
              )
            ''')
            .order('ownership_id'),
      ]);
      final mapFeatures = await MapFeatureService.loadVisible(supabase);

      final mapConfig = results[0] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        final centerLat = (mapConfig?['center_lat'] as num?)?.toDouble();
        final centerLng = (mapConfig?['center_lng'] as num?)?.toDouble();
        if (centerLat != null && centerLng != null) {
          _mapCenter = LatLng(centerLat, centerLng);
          _currentCenter = _mapCenter;
        }
        _activeMapLatSpan =
            (mapConfig?['lat_span'] as num?)?.toDouble() ?? _mapLatSpan;
        _activeMapLngSpan =
            (mapConfig?['lng_span'] as num?)?.toDouble() ?? _mapLngSpan;
        _entranceXPercent = (mapConfig?['entrance_x_percent'] as num?)
            ?.toDouble();
        _entranceYPercent = (mapConfig?['entrance_y_percent'] as num?)
            ?.toDouble();
        _lotMarkers = List<Map<String, dynamic>>.from(results[1] as List);
        _pathNodes = List<Map<String, dynamic>>.from(results[2] as List);
        _pathEdges = List<Map<String, dynamic>>.from(results[3] as List);
        _ownershipByLotId = AdminLotOwnerService.ownershipByLotId(
          results[4] as List,
        );
        _mapFeatures = mapFeatures;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Unable to load map data: $e', error: true);
    }
  }

  void _subscribeToLotChanges() {
    _lotChangesChannel = Supabase.instance.client
        .channel('admin-map-lot-changes-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cemetery_lot',
          callback: _handleLotChange,
        )
        .subscribe();
  }

  void _handleLotChange(PostgresChangePayload payload) {
    if (!mounted) return;

    if (payload.eventType == PostgresChangeEvent.delete) {
      final deletedLotId = payload.oldRecord['lot_id'];
      if (deletedLotId != null) _removeLotMarkerByLotId(deletedLotId);
      return;
    }

    if (payload.newRecord.isEmpty) return;
    _mergeLotIntoMarker(payload.newRecord);
  }

  void _mergeLotIntoMarker(Map<String, dynamic> updatedLot) {
    final lotId = updatedLot['lot_id'];
    if (lotId == null) return;

    final index = _lotMarkers.indexWhere(
      (marker) => _sameRecordId(_markerLotId(marker), lotId),
    );
    if (index == -1) return;

    final currentMarker = Map<String, dynamic>.from(_lotMarkers[index]);
    final currentLot = Map<String, dynamic>.from(
      currentMarker['cemetery_lot'] ?? {},
    );
    currentMarker['cemetery_lot'] = {...currentLot, ...updatedLot};

    setState(() {
      _lotMarkers[index] = currentMarker;
      if (_selectedMarker != null &&
          _sameRecordId(_markerLotId(_selectedMarker!), lotId)) {
        _selectedMarker = currentMarker;
      }
    });
  }

  void _removeLotMarkerByLotId(dynamic lotId) {
    final index = _lotMarkers.indexWhere(
      (marker) => _sameRecordId(_markerLotId(marker), lotId),
    );
    if (index == -1) return;

    setState(() {
      final removed = _lotMarkers.removeAt(index);
      if (_selectedMarker != null &&
          _sameRecordId(
            _markerLotId(removed),
            _markerLotId(_selectedMarker!),
          )) {
        _selectedMarker = null;
      }
    });
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

  String _defaultLotLabel({
    required String blockNumber,
    required String lotNumber,
  }) {
    if (blockNumber.isNotEmpty && lotNumber.isNotEmpty) {
      return '$blockNumber-$lotNumber';
    }
    return lotNumber;
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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
    _blockNumberController.clear();
    _lotNumberController.clear();
    _lotLabelController.clear();
    _lotClassTypeController.clear();
    _priceController.clear();
    String selectedStatus = 'Available';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _C.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: _mapDialogTitle('Add Lot', Icons.add_location_alt_outlined),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _blockNumberController,
                  decoration: _mapFieldDecoration(
                    labelText: 'Block',
                    icon: Icons.grid_view_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotNumberController,
                  decoration: _mapFieldDecoration(
                    labelText: 'Lot Number',
                    icon: Icons.numbers_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotLabelController,
                  decoration: _mapFieldDecoration(
                    labelText: 'Lot Label',
                    icon: Icons.label_outline_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotClassTypeController,
                  decoration: _mapFieldDecoration(
                    labelText: 'Lot Class / Type',
                    icon: Icons.category_outlined,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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

    final blockNumber = _blockNumberController.text.trim();
    final lotNumber = _lotNumberController.text.trim();
    final lotLabel = _lotLabelController.text.trim().isEmpty
        ? _defaultLotLabel(blockNumber: blockNumber, lotNumber: lotNumber)
        : _lotLabelController.text.trim();
    final lotClassType = _lotClassTypeController.text.trim();

    setState(() => _isSaving = true);
    try {
      final lotPoint = _percentToLatLng(xPercent, yPercent);
      final lot = await Supabase.instance.client
          .from('cemetery_lot')
          .insert({
            'block_number': blockNumber.isEmpty ? null : blockNumber,
            'lot_number': lotNumber,
            'lot_label': lotLabel.isEmpty ? lotNumber : lotLabel,
            'lot_class_type': lotClassType.isEmpty ? null : lotClassType,
            'price': double.parse(_priceController.text.trim()),
            'status': selectedStatus,
            'x_coord': lotPoint.longitude,
            'y_coord': lotPoint.latitude,
          })
          .select(_lotColumnsSelect)
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

    final blockNumberController = TextEditingController(
      text: lot['block_number']?.toString() ?? '',
    );
    final lotNumberController = TextEditingController(
      text: lotText(lot, 'lot_number'),
    );
    final lotLabelController = TextEditingController(
      text: lotText(lot, 'lot_label'),
    );
    final lotClassTypeController = TextEditingController(
      text: lotText(lot, 'lot_class_type'),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: _mapDialogTitle(
            'Edit Lot ${lotReference(lot, fallback: '')}'.trim(),
            Icons.edit_location_alt_outlined,
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: blockNumberController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Block',
                      icon: Icons.grid_view_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lotNumberController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Lot Number',
                      icon: Icons.numbers_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lotLabelController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Lot Label',
                      icon: Icons.label_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lotClassTypeController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Lot Class / Type',
                      icon: Icons.category_outlined,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Save Lot'),
            ),
          ],
        ),
      ),
    );

    final blockNumber = blockNumberController.text.trim();
    final lotNumber = lotNumberController.text.trim();
    final lotLabel = lotLabelController.text.trim().isEmpty
        ? _defaultLotLabel(blockNumber: blockNumber, lotNumber: lotNumber)
        : lotLabelController.text.trim();
    final lotClassType = lotClassTypeController.text.trim();
    final priceInput = priceController.text.trim();
    final xInput = xController.text.trim();
    final yInput = yController.text.trim();
    blockNumberController.dispose();
    lotNumberController.dispose();
    lotLabelController.dispose();
    lotClassTypeController.dispose();
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
            'block_number': blockNumber.isEmpty ? null : blockNumber,
            'lot_number': lotNumber,
            'lot_label': lotLabel.isEmpty ? lotNumber : lotLabel,
            'lot_class_type': lotClassType.isEmpty ? null : lotClassType,
            'price': price,
            'status': selectedStatus,
            'x_coord': _percentToLatLng(normalizedX, normalizedY).longitude,
            'y_coord': _percentToLatLng(normalizedX, normalizedY).latitude,
          })
          .eq('lot_id', lotId)
          .select(_lotColumnsSelect)
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
    final lotId = lot['lot_id'] ?? marker['lot_id'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Lot ${lotReference(lot, fallback: '')}'.trim()),
        content: const Text(
          'This removes the lot, its map marker, and any linked burial or ownership records.',
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
      if (lotId == null) {
        throw Exception('This marker is missing a lot id.');
      }
      await AdminDeleteService.deleteLot(int.parse(lotId.toString()));

      setState(() {
        _lotMarkers.removeWhere((m) => m['marker_id'] == marker['marker_id']);
        if (lotId != null) _ownershipByLotId.remove(lotId.toString());
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

  Future<void> _showAssignOwnerDialog(Map<String, dynamic> marker) async {
    final lot = Map<String, dynamic>.from(marker['cemetery_lot'] ?? {});
    final lotId = int.tryParse((lot['lot_id'] ?? marker['lot_id']).toString());
    if (lotId == null) {
      _snack('This marker is missing a lot id.', error: true);
      return;
    }

    setState(() => _isSaving = true);
    late final List<Map<String, dynamic>> owners;
    Map<String, dynamic>? currentOwnership;
    try {
      final results = await Future.wait([
        AdminLotOwnerService.loadLotOwners(),
        AdminLotOwnerService.loadOwnershipForLot(lotId),
      ]);
      owners = List<Map<String, dynamic>>.from(results[0] as List);
      currentOwnership = results[1] == null
          ? null
          : Map<String, dynamic>.from(results[1] as Map);
    } catch (e) {
      _snack('Unable to load lot owners: $e', error: true);
      return;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }

    if (!mounted) return;
    final result = await showDialog<_LotOwnerAssignmentResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LotOwnerAssignmentDialog(
        lot: lot,
        owners: owners,
        currentOwnership: currentOwnership,
      ),
    );

    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      if (result.removeOwner) {
        await AdminLotOwnerService.removeOwnerFromLot(lotId);
        await AuditService.log(
          action: 'UNASSIGN_LOT_OWNER',
          entityType: 'lot_ownership',
          entityId: lotId.toString(),
          details: 'Removed owner from Lot ${lotReference(lot)}',
        );
        _snack('Lot owner removed.');
      } else if (result.existingOwnerId != null) {
        await AdminLotOwnerService.assignOwnerToLot(
          lotId: lotId,
          userId: result.existingOwnerId!,
          totalMonths: result.totalMonths,
        );
        await AuditService.log(
          action: 'ASSIGN_LOT_OWNER',
          entityType: 'lot_ownership',
          entityId: lotId.toString(),
          details:
              'Assigned existing owner to Lot ${lotReference(lot)} from map',
        );
        _snack('Lot owner assigned.');
      } else {
        final formData = result.formData;
        final profile = AdminLotOwnerService.profilePayload(formData);
        final email = formData['email']!.trim().toLowerCase();
        final userId =
            await AdminLotOwnerService.createAuthLotOwner(
              name: formData['name']!.trim(),
              email: email,
              phone: formData['phone']!.trim(),
              password: formData['password']!.trim(),
              lotOwnerProfile: profile,
            ) ??
            await AdminLotOwnerService.findUserIdByEmail(email);

        if (userId == null || userId.isEmpty) {
          throw Exception(
            'Lot owner account was created but user_id was not returned.',
          );
        }

        await AdminLotOwnerService.upsertLotOwnerDirectoryProfile(
          userId: userId,
          name: formData['name']!.trim(),
          email: email,
          phone: formData['phone']!.trim(),
          lotOwnerProfile: profile,
        );

        await AdminLotOwnerService.assignOwnerToLot(
          lotId: lotId,
          userId: userId,
          totalMonths: result.totalMonths,
          lotOwnerProfile: profile,
          lotUpdates: AdminLotOwnerService.lotUpdatesFromProfile(profile),
        );
        await AuditService.log(
          action: 'CREATE_LOT_OWNER_FROM_MAP',
          entityType: 'user',
          entityId: userId,
          details: 'Created lot owner for Lot ${lotReference(lot)} from map',
        );
        _snack('Lot owner account created and linked.');
      }

      await _refreshLotOwnership(lotId);
      await _refreshLotMarker(lotId);
    } catch (e) {
      _snack('Unable to save lot owner: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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

  Future<void> _showAssignBurialDialog(Map<String, dynamic> marker) async {
    final lot = Map<String, dynamic>.from(marker['cemetery_lot'] ?? {});
    final lotId = int.tryParse((lot['lot_id'] ?? marker['lot_id']).toString());
    if (lotId == null) {
      _snack('This marker is missing a lot id.', error: true);
      return;
    }

    setState(() => _isSaving = true);
    List<Map<String, dynamic>> burials;
    try {
      final rows = await Supabase.instance.client
          .from('burial_record')
          .select('''
            burial_id,
            name_of_deceased,
            death_date,
            burial_date,
            interment_date,
            lot_id,
            cemetery_lot (
              lot_id,
              lot_number,
              lot_label,
              block_number,
              lot_class_type
            )
          ''')
          .order('name_of_deceased');
      burials = List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      _snack('Unable to load burial records: $e', error: true);
      if (mounted) setState(() => _isSaving = false);
      return;
    }
    if (mounted) setState(() => _isSaving = false);
    if (!mounted) return;

    String? selectedBurialId;
    final assignedBurials = burials
        .where((record) => _sameRecordId(record['lot_id'], lotId))
        .toList();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _C.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: _mapDialogTitle(
            'Assign Deceased to Lot ${lotReference(lot)}',
            Icons.person_pin_circle_rounded,
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Currently Assigned',
                    style: TextStyle(
                      color: _C.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (assignedBurials.isEmpty)
                    const Text(
                      'No deceased record is linked to this lot yet.',
                      style: TextStyle(color: _C.outline),
                    )
                  else
                    ...assignedBurials.map(
                      (burial) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(
                          burial['name_of_deceased']?.toString() ?? 'Unknown',
                        ),
                        subtitle: Text(
                          'Died: ${burial['death_date'] ?? 'N/A'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Unassign from lot',
                          icon: const Icon(Icons.link_off_rounded),
                          onPressed: () => Navigator.pop(context, {
                            'action': 'unassign',
                            'burial_id': burial['burial_id'],
                          }),
                        ),
                      ),
                    ),
                  const Divider(height: 28),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBurialId,
                    decoration: _mapFieldDecoration(
                      labelText: 'Deceased Record',
                      icon: Icons.person_search_rounded,
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Select a deceased record'),
                      ),
                      ...burials.map((burial) {
                        final assignedLot = burial['cemetery_lot'];
                        final currentLotId = burial['lot_id'];
                        final status = currentLotId == null
                            ? 'unassigned'
                            : _sameRecordId(currentLotId, lotId)
                            ? 'already here'
                            : 'assigned to Lot ${lotReference(assignedLot)}';
                        return DropdownMenuItem<String>(
                          value: burial['burial_id'].toString(),
                          child: Text(
                            '${burial['name_of_deceased'] ?? 'Unknown'} ($status)',
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedBurialId = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: _C.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedBurialId == null
                  ? null
                  : () => Navigator.pop(context, {
                      'action': 'assign',
                      'burial_id': selectedBurialId,
                    }),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final burialId = int.tryParse(result['burial_id'].toString());
    if (burialId == null) {
      _snack('Selected burial record is invalid.', error: true);
      return;
    }

    if (result['action'] == 'unassign') {
      await _unassignBurialFromLot(burialId: burialId, lotId: lotId);
    } else {
      await _assignBurialToLot(burialId: burialId, lotId: lotId, lot: lot);
    }
  }

  Future<void> _assignBurialToLot({
    required int burialId,
    required int lotId,
    required Map<String, dynamic> lot,
  }) async {
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final burial = await supabase
          .from('burial_record')
          .select('burial_id, name_of_deceased, lot_id, lot_location_no')
          .eq('burial_id', burialId)
          .single();
      final oldLotId = int.tryParse(burial['lot_id']?.toString() ?? '');
      final updateData = <String, dynamic>{'lot_id': lotId};
      final existingPaperLot = burial['lot_location_no']?.toString().trim();
      if (existingPaperLot == null || existingPaperLot.isEmpty) {
        updateData['lot_location_no'] = lotReference(lot);
      }

      await supabase
          .from('burial_record')
          .update(updateData)
          .eq('burial_id', burialId);
      await supabase
          .from('cemetery_lot')
          .update({'status': 'Occupied'})
          .eq('lot_id', lotId);

      if (oldLotId != null && oldLotId != lotId) {
        await _refreshLotStatusAfterBurialChange(oldLotId);
        await _refreshLotMarker(oldLotId);
      }
      await _refreshLotMarker(lotId);

      await AuditService.log(
        action: 'UPDATE',
        entityType: 'burial',
        entityId: burialId.toString(),
        details:
            'Assigned ${burial['name_of_deceased'] ?? 'burial record'} to Lot ${lotReference(lot)}',
      );

      _snack('Deceased record assigned to lot.');
    } catch (e) {
      _snack('Unable to assign deceased: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _unassignBurialFromLot({
    required int burialId,
    required int lotId,
  }) async {
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      final burial = await supabase
          .from('burial_record')
          .select('burial_id, name_of_deceased')
          .eq('burial_id', burialId)
          .single();
      await supabase
          .from('burial_record')
          .update({'lot_id': null})
          .eq('burial_id', burialId);
      await _refreshLotStatusAfterBurialChange(lotId);
      await _refreshLotMarker(lotId);

      await AuditService.log(
        action: 'UPDATE',
        entityType: 'burial',
        entityId: burialId.toString(),
        details:
            'Unassigned ${burial['name_of_deceased'] ?? 'burial record'} from lot',
      );

      _snack('Deceased record unassigned from lot.');
    } catch (e) {
      _snack('Unable to unassign deceased: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _refreshLotStatusAfterBurialChange(int lotId) async {
    await AdminLotOwnerService.refreshLotStatus(lotId);
  }

  Future<void> _refreshLotMarker(int lotId) async {
    final marker = await Supabase.instance.client
        .from('lot_markers')
        .select(_lotMarkerSelect)
        .eq('lot_id', lotId)
        .maybeSingle();
    if (marker == null || !mounted) return;

    final normalizedMarker = Map<String, dynamic>.from(marker);
    setState(() {
      final index = _lotMarkers.indexWhere(
        (item) => _sameRecordId(item['lot_id'], lotId),
      );
      if (index != -1) _lotMarkers[index] = normalizedMarker;
      if (_selectedMarker != null &&
          _sameRecordId(_markerLotId(_selectedMarker!), lotId)) {
        _selectedMarker = normalizedMarker;
      }
    });
  }

  Future<void> _refreshLotOwnership(int lotId) async {
    final ownership = await AdminLotOwnerService.loadOwnershipForLot(lotId);
    if (!mounted) return;

    setState(() {
      if (ownership == null) {
        _ownershipByLotId.remove(lotId.toString());
      } else {
        _ownershipByLotId[lotId.toString()] = ownership;
      }
    });
  }

  Future<void> _showAddGraveDialog(Map<String, dynamic> marker) async {
    final lot = marker['cemetery_lot'] ?? {};
    final lotId = int.tryParse((lot['lot_id'] ?? marker['lot_id']).toString());
    if (lotId == null) {
      _snack('This marker is missing a lot id.', error: true);
      return;
    }

    final gravesByLotId = await AdminGraveService.loadGravesByLotIds([lotId]);
    if (!mounted) return;
    final existingGraves = gravesByLotId[lotId.toString()] ?? [];
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
          backgroundColor: _C.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: _mapDialogTitle(
            'Add Grave to Lot ${lotReference(lot)}',
            Icons.add_location_alt_rounded,
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: graveLabelController,
                    decoration: _mapFieldDecoration(
                      labelText: 'Grave / Slot Label',
                      icon: Icons.label_outline_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: graveMode,
                    decoration: _mapFieldDecoration(
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
                      decoration: _mapFieldDecoration(
                        labelText: 'Existing Deceased',
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
                      decoration: _mapFieldDecoration(
                        labelText: 'Name of Deceased',
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
                            decoration: _mapFieldDecoration(
                              labelText: 'Born',
                              icon: Icons.cake_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppDateField(
                            controller: deathDateController,
                            label: 'Died',
                            icon: Icons.event_busy_outlined,
                            helperText: 'YYYY-MM-DD',
                            decoration: _mapFieldDecoration(
                              labelText: 'Died',
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
                            decoration: _mapFieldDecoration(
                              labelText: 'Interment Date',
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: intermentTimeController,
                            decoration: _mapFieldDecoration(
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
                      decoration: _mapFieldDecoration(
                        labelText: 'Religion',
                        icon: Icons.church_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedLotType,
                      decoration: _mapFieldDecoration(
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
                    decoration: _mapFieldDecoration(
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
                foregroundColor: _C.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
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
      _snack('Grave label is required.', error: true);
      return;
    }
    if (graveMode == 'existing' && selectedBurialId == null) {
      _snack('Please select an existing deceased record.', error: true);
      return;
    }
    if (graveMode == 'new') {
      if (deceasedName.isEmpty || deathDate.isEmpty) {
        _snack('Name of deceased and death date are required.', error: true);
        return;
      }
      if (!_isValidDateText(birthDate) ||
          !_isValidDateText(deathDate) ||
          !_isValidDateText(intermentDate)) {
        _snack('Dates must use YYYY-MM-DD format.', error: true);
        return;
      }
      if (!_isValidTimeText(intermentTime)) {
        _snack('Interment time must use HH:mm format.', error: true);
        return;
      }
    }

    setState(() => _isSaving = true);
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
      await _refreshLotMarker(lotId);
      _snack('Grave and deceased record saved.');
    } catch (e) {
      _snack('Unable to add grave: $e', error: true);
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

  void _selectMarkerByLotId(String lotId) {
    final marker = _lotMarkers.cast<Map<String, dynamic>?>().firstWhere(
      (marker) => marker != null && _markerLotId(marker).toString() == lotId,
      orElse: () => null,
    );
    if (marker != null) _selectMarker(marker);
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
    _moveMap(_mapCenter, _currentZoom);
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
    final lotPolygons = lotPolygonsFromMarkers(
      _lotMarkers,
      selectedLotId: _selectedMarker == null
          ? null
          : _markerLotId(_selectedMarker!),
      includeHitValues: true,
    );
    final baseMapFeatures = _mapFeatures.where(isMapLayerFeature).toList();
    final overlayMapFeatures = _mapFeatures
        .where((feature) => !isMapLayerFeature(feature))
        .toList();
    final basePolygons = mapFeaturePolygons(baseMapFeatures);
    final basePolylines = mapFeaturePolylines(baseMapFeatures);
    final overlayPolygons = mapFeaturePolygons(overlayMapFeatures);
    final overlayPolylines = mapFeaturePolylines(overlayMapFeatures);
    final overlayPointMarkers = mapFeaturePointMarkers(overlayMapFeatures);

    return Container(
      key: _mapKey,
      color: _C.background,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _mapCenter,
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
          if (basePolygons.isNotEmpty) PolygonLayer(polygons: basePolygons),
          if (basePolylines.isNotEmpty) PolylineLayer(polylines: basePolylines),
          if (overlayPolygons.isNotEmpty)
            PolygonLayer(polygons: overlayPolygons),
          if (lotPolygons.isNotEmpty)
            _mode == _MapMode.select
                ? GestureDetector(
                    onTap: () {
                      final hitValues = _lotPolygonHitNotifier.value?.hitValues;
                      final lotId = hitValues == null || hitValues.isEmpty
                          ? null
                          : hitValues.last;
                      if (lotId != null) _selectMarkerByLotId(lotId);
                    },
                    child: PolygonLayer<String>(
                      polygons: lotPolygons,
                      hitNotifier: _lotPolygonHitNotifier,
                    ),
                  )
                : IgnorePointer(
                    child: PolygonLayer<String>(polygons: lotPolygons),
                  ),
          if (overlayPolylines.isNotEmpty)
            PolylineLayer(polylines: overlayPolylines),
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
          if (overlayPointMarkers.isNotEmpty)
            MarkerLayer(markers: overlayPointMarkers),
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
      ..._lotMarkers.where((marker) => !markerHasLotPolygon(marker)).map((
        marker,
      ) {
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
              child: _mapBadge(
                Icons.location_on_rounded,
                lotStatusFillColor(status),
                borderColor: lotStatusStrokeColor(status),
                foregroundColor: lotStatusForegroundColor(status),
              ),
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

  Widget _mapBadge(
    IconData icon,
    Color color, {
    Color? borderColor,
    Color? foregroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor ?? _C.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: foregroundColor ?? _C.white, size: 20),
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
        : 'Selected Lot ${lotReference(selectedLot)}';
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
    final lotNumber = lotReference(lot, fallback: '--');
    final meta = lotMeta(lot);
    final status = lot['status']?.toString() ?? 'No selection';
    final price = lot['price']?.toString() ?? '--';
    final assignedOwner = marker == null ? '--' : _ownerLabelForLot(lot);
    final assignedDeceased = marker == null ? '--' : _burialNamesForLot(lot);
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
                        : meta.isEmpty
                        ? 'Marker ID: ${marker['marker_id']}'
                        : meta,
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
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _infoRow('Map Details', meta),
                  ],
                  const SizedBox(height: 10),
                  _infoRow('Price', price == '--' ? price : 'PHP $price'),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Owner: $assignedOwner',
                      style: const TextStyle(
                        color: _C.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Deceased: $assignedDeceased',
                      style: const TextStyle(
                        color: _C.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
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
                    child: FilledButton.icon(
                      onPressed: marker == null
                          ? null
                          : () => _showAssignOwnerDialog(marker),
                      icon: const Icon(Icons.assignment_ind_rounded, size: 16),
                      label: const Text('Assign Owner'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.primary,
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
                    child: FilledButton.icon(
                      onPressed: marker == null
                          ? null
                          : () => _showAssignBurialDialog(marker),
                      icon: const Icon(
                        Icons.person_pin_circle_rounded,
                        size: 16,
                      ),
                      label: const Text('Assign Deceased'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.primary,
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
                    child: FilledButton.icon(
                      onPressed: marker == null
                          ? null
                          : () => _showAddGraveDialog(marker),
                      icon: const Icon(
                        Icons.add_location_alt_rounded,
                        size: 16,
                      ),
                      label: const Text('Add Grave'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.secondary,
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
    final ownerLabel = _ownerLabelForLot(lot);
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
              'Lot ${lotReference(lot)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (lotMeta(lot).isNotEmpty) Text(lotMeta(lot)),
            Text('Status: ${lot['status'] ?? '--'}'),
            Text('Owner: $ownerLabel'),
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
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAssignOwnerDialog(marker);
                },
                icon: const Icon(Icons.assignment_ind_rounded),
                label: const Text('Assign Owner'),
                style: FilledButton.styleFrom(backgroundColor: _C.primary),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAssignBurialDialog(marker);
                },
                icon: const Icon(Icons.person_pin_circle_rounded),
                label: const Text('Assign Deceased'),
                style: FilledButton.styleFrom(backgroundColor: _C.primary),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddGraveDialog(marker);
                },
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Grave'),
                style: FilledButton.styleFrom(backgroundColor: _C.secondary),
              ),
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

    final qgisRoute = shortestRouteThroughPathways(
      pathwayLines: mapFeaturePathwayLines(_mapFeatures),
      start: start,
      end: end,
    );
    if (qgisRoute.isNotEmpty) return qgisRoute;

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
      return _mapCenter;
    }
    return _percentToLatLng(_entranceXPercent!, _entranceYPercent!);
  }

  LatLng _markerToLatLng(Map<String, dynamic> marker) {
    return _percentToLatLng(
      (marker['x_percent'] as num).toDouble(),
      (marker['y_percent'] as num).toDouble(),
    );
  }

  dynamic _markerLotId(Map<String, dynamic> marker) {
    final lot = marker['cemetery_lot'];
    if (lot is Map) return lot['lot_id'];
    return marker['lot_id'];
  }

  List<Map<String, dynamic>> _burialsForLot(dynamic lot) {
    if (lot is! Map) return [];
    final burialRecord = lot['burial_record'];
    if (burialRecord is List) {
      return burialRecord
          .whereType<Map>()
          .map((record) => Map<String, dynamic>.from(record))
          .toList();
    }
    if (burialRecord is Map) {
      return [Map<String, dynamic>.from(burialRecord)];
    }
    return [];
  }

  String _burialNamesForLot(dynamic lot) {
    final burials = _burialsForLot(lot);
    if (burials.isEmpty) return 'None assigned';
    return burials
        .map((record) => record['name_of_deceased']?.toString() ?? 'Unknown')
        .join(', ');
  }

  String _ownerLabelForLot(dynamic lot) {
    if (lot is! Map) return 'None assigned';
    final lotId = lot['lot_id']?.toString();
    if (lotId == null || lotId.isEmpty) return 'None assigned';

    final ownership = _ownershipByLotId[lotId];
    if (ownership == null) return 'None assigned';
    final user = ownership['user'];
    final name = user is Map ? user['name']?.toString() : null;
    final email = user is Map ? user['email']?.toString() : null;
    if (name != null && name.trim().isNotEmpty) {
      return email == null || email.trim().isEmpty ? name : '$name ($email)';
    }
    final userId = ownership['user_id']?.toString();
    return userId == null || userId.isEmpty ? 'None assigned' : userId;
  }

  bool _sameRecordId(dynamic left, dynamic right) {
    if (left == null || right == null) return false;
    return left.toString() == right.toString();
  }

  LatLng _nodeToLatLng(Map<String, dynamic> node) {
    return _percentToLatLng(
      (node['x_percent'] as num).toDouble(),
      (node['y_percent'] as num).toDouble(),
    );
  }

  LatLng _percentToLatLng(double xPercent, double yPercent) {
    final latOffset = (0.5 - yPercent / 100) * _activeMapLatSpan;
    final lngOffset = (xPercent / 100 - 0.5) * _activeMapLngSpan;
    return LatLng(
      _mapCenter.latitude + latOffset,
      _mapCenter.longitude + lngOffset,
    );
  }

  (double, double) _latLngToPercent(LatLng point) {
    final x =
        ((point.longitude - _mapCenter.longitude) / _activeMapLngSpan + 0.5) *
        100;
    final y =
        (0.5 - (point.latitude - _mapCenter.latitude) / _activeMapLatSpan) *
        100;
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
    final centerLatRadians = _degreesToRadians(_mapCenter.latitude);
    final x =
        _degreesToRadians(point.longitude - _mapCenter.longitude) *
        earthRadiusMeters *
        cos(centerLatRadians);
    final y =
        _degreesToRadians(point.latitude - _mapCenter.latitude) *
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

class _LotOwnerAssignmentResult {
  const _LotOwnerAssignmentResult.existing({
    required this.existingOwnerId,
    required this.totalMonths,
  }) : removeOwner = false,
       formData = const {};

  const _LotOwnerAssignmentResult.create({
    required this.formData,
    required this.totalMonths,
  }) : removeOwner = false,
       existingOwnerId = null;

  const _LotOwnerAssignmentResult.remove()
    : removeOwner = true,
      existingOwnerId = null,
      totalMonths = 1,
      formData = const {};

  final bool removeOwner;
  final String? existingOwnerId;
  final int totalMonths;
  final Map<String, String> formData;
}

class _LotOwnerAssignmentDialog extends StatefulWidget {
  const _LotOwnerAssignmentDialog({
    required this.lot,
    required this.owners,
    required this.currentOwnership,
  });

  final Map<String, dynamic> lot;
  final List<Map<String, dynamic>> owners;
  final Map<String, dynamic>? currentOwnership;

  @override
  State<_LotOwnerAssignmentDialog> createState() =>
      _LotOwnerAssignmentDialogState();
}

class _LotOwnerAssignmentDialogState extends State<_LotOwnerAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controlNumberController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _occupationController;
  late final TextEditingController _ageController;
  late final TextEditingController _dateOfBirthController;
  late final TextEditingController _spouseBeneficiaryController;
  late final TextEditingController _relationshipController;
  late final TextEditingController _lotClassTypeController;
  late final TextEditingController _blockNumberController;
  late final TextEditingController _lotNumberController;
  late final TextEditingController _numberOfLotsController;
  late final TextEditingController _lotPriceController;
  late final TextEditingController _intermentFeeController;
  late final TextEditingController _certificationFeeController;
  late final TextEditingController _burialPermitFeeController;
  late final TextEditingController _totalAmountController;
  late final TextEditingController _orNumberController;
  late final TextEditingController _receiptAmountController;
  late final TextEditingController _receiptDateController;
  late final TextEditingController _approvedDateController;
  late final TextEditingController _approvedByNameController;
  late final TextEditingController _approvalSignatureController;

  String _mode = 'existing';
  String? _selectedOwnerId;
  String? _civilStatus;
  String? _gender;
  String _purchaseTerm = 'cash';

  @override
  void initState() {
    super.initState();
    final lot = widget.lot;
    final currentOwnerId = widget.currentOwnership?['user_id']?.toString();
    _mode = widget.owners.isEmpty ? 'new' : 'existing';
    _selectedOwnerId =
        currentOwnerId != null &&
            widget.owners.any(
              (owner) => owner['user_id']?.toString() == currentOwnerId,
            )
        ? currentOwnerId
        : null;
    final totalMonths = int.tryParse(
      widget.currentOwnership?['total_months']?.toString() ?? '',
    );
    if (totalMonths != null && totalMonths > 1) _purchaseTerm = 'at_need';

    _controlNumberController = TextEditingController();
    _firstNameController = TextEditingController();
    _middleNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _occupationController = TextEditingController();
    _ageController = TextEditingController();
    _dateOfBirthController = TextEditingController();
    _spouseBeneficiaryController = TextEditingController();
    _relationshipController = TextEditingController();
    _lotClassTypeController = TextEditingController(
      text: lotText(lot, 'lot_class_type'),
    );
    _blockNumberController = TextEditingController(
      text: lotText(lot, 'block_number'),
    );
    _lotNumberController = TextEditingController(
      text: lotText(lot, 'lot_number'),
    );
    _numberOfLotsController = TextEditingController(text: '1');
    _lotPriceController = TextEditingController(text: _moneyText(lot['price']));
    _intermentFeeController = TextEditingController();
    _certificationFeeController = TextEditingController();
    _burialPermitFeeController = TextEditingController();
    _totalAmountController = TextEditingController();
    _lotPriceController.addListener(_updateTotalAmount);
    _intermentFeeController.addListener(_updateTotalAmount);
    _certificationFeeController.addListener(_updateTotalAmount);
    _burialPermitFeeController.addListener(_updateTotalAmount);
    _orNumberController = TextEditingController();
    _receiptAmountController = TextEditingController();
    _receiptDateController = TextEditingController();
    _approvedDateController = TextEditingController();
    _approvedByNameController = TextEditingController();
    _approvalSignatureController = TextEditingController();
    _updateTotalAmount();
  }

  @override
  void dispose() {
    _controlNumberController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _occupationController.dispose();
    _ageController.dispose();
    _dateOfBirthController.dispose();
    _spouseBeneficiaryController.dispose();
    _relationshipController.dispose();
    _lotClassTypeController.dispose();
    _blockNumberController.dispose();
    _lotNumberController.dispose();
    _numberOfLotsController.dispose();
    _lotPriceController.removeListener(_updateTotalAmount);
    _intermentFeeController.removeListener(_updateTotalAmount);
    _certificationFeeController.removeListener(_updateTotalAmount);
    _burialPermitFeeController.removeListener(_updateTotalAmount);
    _lotPriceController.dispose();
    _intermentFeeController.dispose();
    _certificationFeeController.dispose();
    _burialPermitFeeController.dispose();
    _totalAmountController.dispose();
    _orNumberController.dispose();
    _receiptAmountController.dispose();
    _receiptDateController.dispose();
    _approvedDateController.dispose();
    _approvedByNameController.dispose();
    _approvalSignatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _C.background,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _C.outlineVariant),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Assign Owner to Lot ${lotReference(widget.lot)}',
                        style: const TextStyle(
                          color: _C.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  lotMeta(widget.lot).isEmpty
                      ? 'Create or link a lot owner account for this mapped lot.'
                      : lotMeta(widget.lot),
                  style: const TextStyle(
                    color: _C.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                if (widget.currentOwnership != null) ...[
                  const SizedBox(height: 14),
                  _currentOwnerBanner(),
                ],
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'existing',
                      icon: Icon(Icons.person_search_rounded),
                      label: Text('Existing'),
                    ),
                    ButtonSegment(
                      value: 'new',
                      icon: Icon(Icons.person_add_alt_1_rounded),
                      label: Text('New Owner'),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) {
                    setState(() => _mode = values.first);
                  },
                ),
                const SizedBox(height: 18),
                if (_mode == 'existing')
                  _existingOwnerFields()
                else
                  ..._newOwnerFields(),
                const SizedBox(height: 20),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 10,
                  overflowSpacing: 10,
                  children: [
                    if (widget.currentOwnership != null)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(
                          context,
                          const _LotOwnerAssignmentResult.remove(),
                        ),
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('Remove Owner'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _C.error,
                          side: const BorderSide(color: _C.error),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save Owner'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _C.primary,
                        foregroundColor: _C.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentOwnerBanner() {
    final ownership = widget.currentOwnership!;
    final user = ownership['user'];
    final name = user is Map ? user['name']?.toString() : null;
    final email = user is Map ? user['email']?.toString() : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.primaryFixed,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_ind_rounded, color: _C.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                name == null || name.isEmpty ? 'Current owner' : name,
                if (email != null && email.isNotEmpty) email,
                '${ownership['total_months'] ?? 1} month term',
              ].join(' - '),
              style: const TextStyle(
                color: Color(0xFF00210A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _existingOwnerFields() {
    return Column(
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _selectedOwnerId,
          isExpanded: true,
          decoration: _fieldDecoration(
            'Lot Owner',
            Icons.person_search_rounded,
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                widget.owners.isEmpty
                    ? 'No lot owners yet'
                    : 'Select a lot owner',
              ),
            ),
            ...widget.owners.map((owner) {
              final label = [
                owner['name']?.toString() ?? 'Unnamed owner',
                if ((owner['email']?.toString() ?? '').isNotEmpty)
                  owner['email'].toString(),
              ].join(' - ');
              return DropdownMenuItem<String?>(
                value: owner['user_id']?.toString(),
                child: Text(label, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          validator: (_) {
            if (_mode == 'existing' && _selectedOwnerId == null) {
              return 'Select a lot owner';
            }
            return null;
          },
          onChanged: (value) => setState(() => _selectedOwnerId = value),
        ),
        const SizedBox(height: 14),
        _purchaseTermControl(),
      ],
    );
  }

  List<Widget> _newOwnerFields() {
    return [
      const _DialogSectionTitle(
        icon: Icons.account_circle_rounded,
        title: 'Account',
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _field(
          controller: _emailController,
          label: 'Email Address',
          icon: Icons.email_rounded,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (_mode != 'new') return null;
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'Email is required';
            if (!text.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        _field(
          controller: _passwordController,
          label: 'Temporary Password',
          icon: Icons.lock_rounded,
          keyboardType: TextInputType.visiblePassword,
          obscureText: true,
          validator: (value) {
            if (_mode != 'new') return null;
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'Password is required';
            if (text.length < 6) return 'Use at least 6 characters';
            return null;
          },
        ),
      ]),
      const SizedBox(height: 18),
      const _DialogSectionTitle(
        icon: Icons.assignment_ind_rounded,
        title: "Purchaser's Profile",
      ),
      const SizedBox(height: 12),
      _field(
        controller: _controlNumberController,
        label: 'Control No.',
        icon: Icons.tag_rounded,
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _field(
          controller: _lastNameController,
          label: 'Last Name',
          icon: Icons.person_rounded,
          validator: (value) {
            if (_mode == 'new' && (value?.trim().isEmpty ?? true)) {
              return 'Last name is required';
            }
            return null;
          },
        ),
        _field(
          controller: _firstNameController,
          label: 'First Name',
          icon: Icons.person_rounded,
          validator: (value) {
            if (_mode == 'new' && (value?.trim().isEmpty ?? true)) {
              return 'First name is required';
            }
            return null;
          },
        ),
        _field(
          controller: _middleNameController,
          label: 'Middle Name',
          icon: Icons.person_outline_rounded,
        ),
        _field(
          controller: _phoneController,
          label: 'Mobile',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
        ),
      ]),
      const SizedBox(height: 12),
      _field(
        controller: _addressController,
        label: 'Address',
        icon: Icons.home_outlined,
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _field(
          controller: _occupationController,
          label: 'Occupation',
          icon: Icons.work_outline_rounded,
        ),
        _field(
          controller: _ageController,
          label: 'Age',
          icon: Icons.cake_outlined,
          keyboardType: TextInputType.number,
        ),
        DropdownButtonFormField<String>(
          initialValue: _civilStatus,
          decoration: _fieldDecoration(
            'Civil Status',
            Icons.favorite_border_rounded,
          ),
          items: const [
            DropdownMenuItem(value: 'Single', child: Text('Single')),
            DropdownMenuItem(value: 'Married', child: Text('Married')),
            DropdownMenuItem(value: 'Widowed', child: Text('Widowed')),
            DropdownMenuItem(value: 'Separated', child: Text('Separated')),
          ],
          onChanged: (value) => setState(() => _civilStatus = value),
        ),
        _dateField(
          controller: _dateOfBirthController,
          label: 'Date of Birth',
          icon: Icons.event_rounded,
          lastDate: DateTime.now(),
          onChanged: _updateAgeFromBirthDate,
        ),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: _fieldDecoration('Gender', Icons.wc_rounded),
          items: const [
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Female', child: Text('Female')),
          ],
          onChanged: (value) => setState(() => _gender = value),
        ),
        _field(
          controller: _spouseBeneficiaryController,
          label: 'Spouse / Beneficiary',
          icon: Icons.diversity_1_rounded,
        ),
        _field(
          controller: _relationshipController,
          label: 'Relationship',
          icon: Icons.handshake_outlined,
        ),
      ]),
      const SizedBox(height: 18),
      const _DialogSectionTitle(
        icon: Icons.location_on_rounded,
        title: 'Lot Details',
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _lotTypeField(),
        _field(
          controller: _blockNumberController,
          label: 'Block',
          icon: Icons.grid_view_rounded,
        ),
        _field(
          controller: _lotNumberController,
          label: 'Lot',
          icon: Icons.place_outlined,
        ),
        _field(
          controller: _numberOfLotsController,
          label: 'No. of Lots',
          icon: Icons.format_list_numbered_rounded,
          keyboardType: TextInputType.number,
        ),
      ]),
      const SizedBox(height: 18),
      const _DialogSectionTitle(icon: Icons.payments_outlined, title: 'Terms'),
      const SizedBox(height: 12),
      _purchaseTermControl(),
      const SizedBox(height: 18),
      const _DialogSectionTitle(
        icon: Icons.receipt_long_outlined,
        title: 'Amount Payable',
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _moneyField(_lotPriceController, 'Lot Price'),
        _moneyField(_intermentFeeController, 'Interment Fee'),
        _moneyField(_certificationFeeController, 'Certification Fee'),
        _moneyField(_burialPermitFeeController, 'Burial Permit Fee'),
        _field(
          controller: _totalAmountController,
          label: 'Total',
          icon: Icons.summarize_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
          readOnly: true,
        ),
      ]),
      const SizedBox(height: 18),
      const _DialogSectionTitle(
        icon: Icons.approval_outlined,
        title: 'Receipt and Approval',
      ),
      const SizedBox(height: 12),
      _fieldGrid([
        _field(
          controller: _orNumberController,
          label: 'OR #',
          icon: Icons.confirmation_number_outlined,
        ),
        _field(
          controller: _receiptAmountController,
          label: 'P',
          icon: Icons.payments_outlined,
          keyboardType: TextInputType.number,
          prefixText: 'PHP ',
        ),
        _dateField(
          controller: _receiptDateController,
          label: 'Date',
          icon: Icons.event_note_outlined,
        ),
        _dateField(
          controller: _approvedDateController,
          label: 'Approved Date',
          icon: Icons.verified_outlined,
        ),
        _field(
          controller: _approvedByNameController,
          label: 'Approved By',
          icon: Icons.badge_outlined,
        ),
        _field(
          controller: _approvalSignatureController,
          label: 'Approver Signature',
          icon: Icons.draw_outlined,
        ),
      ]),
    ];
  }

  Widget _purchaseTermControl() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'cash', label: Text('Cash')),
          ButtonSegment(value: 'at_need', label: Text('At Need')),
        ],
        selected: {_purchaseTerm},
        showSelectedIcon: false,
        onSelectionChanged: (values) {
          setState(() => _purchaseTerm = values.first);
        },
      ),
    );
  }

  Widget _lotTypeField() {
    final current = _lotClassTypeController.text.trim();
    final types = <String>[
      if (current.isNotEmpty && !AdminGraveService.lotTypes.contains(current))
        current,
      ...AdminGraveService.lotTypes,
    ];
    return DropdownButtonFormField<String?>(
      initialValue: current.isEmpty ? null : current,
      isExpanded: true,
      decoration: _fieldDecoration('Lot Class / Type', Icons.category_outlined),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Select lot type'),
        ),
        ...types.map(
          (type) => DropdownMenuItem<String?>(value: type, child: Text(type)),
        ),
      ],
      onChanged: (value) {
        _lotClassTypeController.text = value ?? '';
      },
    );
  }

  Widget _moneyField(TextEditingController controller, String label) {
    return _field(
      controller: controller,
      label: label,
      icon: Icons.payments_outlined,
      keyboardType: TextInputType.number,
      prefixText: 'PHP ',
      onChanged: (_) => _updateTotalAmount(),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? prefixText,
    bool readOnly = false,
    bool obscureText = false,
    int maxLines = 1,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      decoration: _fieldDecoration(
        label,
        icon,
      ).copyWith(prefixText: prefixText),
    );
  }

  Widget _dateField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    DateTime? lastDate,
    ValueChanged<String>? onChanged,
  }) {
    return AppDateField(
      controller: controller,
      label: label,
      icon: icon,
      lastDate: lastDate,
      validator: _validateDateText,
      onChanged: onChanged,
      decoration: _fieldDecoration(label, icon),
    );
  }

  Widget _fieldGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _C.primary),
      filled: true,
      fillColor: _C.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _C.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _C.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _C.primary, width: 1.2),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_mode == 'existing') {
      Navigator.pop(
        context,
        _LotOwnerAssignmentResult.existing(
          existingOwnerId: _selectedOwnerId!,
          totalMonths: AdminLotOwnerService.totalMonthsForPurchaseTerm(
            _purchaseTerm,
          ),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _LotOwnerAssignmentResult.create(
        formData: _formData(),
        totalMonths: AdminLotOwnerService.totalMonthsForPurchaseTerm(
          _purchaseTerm,
        ),
      ),
    );
  }

  Map<String, String> _formData() {
    _updateTotalAmount();
    final firstName = _firstNameController.text.trim();
    final middleName = _middleNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final fullName = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');

    return {
      'name': fullName,
      'email': _emailController.text,
      'phone': _phoneController.text,
      'role': 'lot_owner',
      'password': _passwordController.text,
      'linked_lot_id': widget.lot['lot_id']?.toString() ?? '',
      'control_number': _controlNumberController.text,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'address': _addressController.text,
      'occupation': _occupationController.text,
      'age': _ageController.text,
      'civil_status': _civilStatus ?? '',
      'date_of_birth': _dateOfBirthController.text,
      'gender': _gender ?? '',
      'spouse_beneficiary': _spouseBeneficiaryController.text,
      'beneficiary_relationship': _relationshipController.text,
      'lot_class_type': _lotClassTypeController.text,
      'block_number': _blockNumberController.text,
      'lot_number': _lotNumberController.text,
      'number_of_lots': _numberOfLotsController.text,
      'purchase_term': _purchaseTerm,
      'lot_price': _lotPriceController.text,
      'interment_fee': _intermentFeeController.text,
      'certification_fee': _certificationFeeController.text,
      'burial_permit_fee': _burialPermitFeeController.text,
      'total_amount': _totalAmountController.text,
      'or_number': _orNumberController.text,
      'receipt_amount': _receiptAmountController.text,
      'receipt_date': _receiptDateController.text,
      'approved_date': _approvedDateController.text,
      'approved_by_name': _approvedByNameController.text,
      'approval_signature': _approvalSignatureController.text,
    };
  }

  void _updateTotalAmount() {
    final total = [
      _lotPriceController.text,
      _intermentFeeController.text,
      _certificationFeeController.text,
      _burialPermitFeeController.text,
    ].fold<double>(0, (sum, value) => sum + (_moneyOrNull(value) ?? 0));
    _totalAmountController.text = total.toStringAsFixed(2);
  }

  void _updateAgeFromBirthDate(String value) {
    final birthDate = DateTime.tryParse(value.trim());
    if (birthDate == null) {
      setState(_ageController.clear);
      return;
    }
    final today = DateTime.now();
    var age = today.year - birthDate.year;
    final birthdayHasPassed =
        today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!birthdayHasPassed) age--;
    setState(() => _ageController.text = age.toString());
  }

  String? _validateDateText(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return 'Use YYYY-MM-DD';
    }
    return DateTime.tryParse(text) == null ? 'Invalid date' : null;
  }

  double? _moneyOrNull(String value) {
    final text = value
        .trim()
        .toUpperCase()
        .replaceAll('PHP', '')
        .replaceAll('₱', '')
        .replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String _moneyText(dynamic value) {
    if (value == null) return '';
    final numeric = value is num ? value.toDouble() : double.tryParse('$value');
    return numeric == null ? value.toString() : numeric.toStringAsFixed(2);
  }
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _C.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: _C.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
