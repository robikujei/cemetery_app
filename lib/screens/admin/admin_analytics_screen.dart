import '../../core/app_colors.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/analytics_data.dart';
import '../../services/cemetery_analytics.dart';
import '../../services/audit_service.dart';
import '../../utils/csv_download.dart';
import '../../utils/lot_formatters.dart';
import '../../utils/map_feature_geometry.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _HotspotLegendItem extends StatelessWidget {
  const _HotspotLegendItem({
    required this.color,
    required this.label,
    this.borderColor,
  });
  final Color color;
  final Color? borderColor;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor ?? color),
        ),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  AnalyticsData? _data;
  bool _loading = false, _exporting = false;
  DateTimeRange? _range;
  DateTime _visitorMonth = DateTime(DateTime.now().year, DateTime.now().month);
  double _epsilon = 15, _medium = 30, _high = 70;
  int _minPoints = 5;
  String _report = 'Burial records';
  SpatialResult _spatial = const SpatialResult([], [], 0, 0);
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  static const _mockEnabled = bool.fromEnvironment(
    'MOCK_ANALYTICS',
    defaultValue: false,
  );
  static const _accent = AppColors.brand;
  static const _types = [
    'Burial records',
    'Burial records (detailed)',
    'Visitor logs',
    'Visitor trends',
    'Lot inventory',
    'Lot sales',
    'Payments',
    'Lot demand',
    'Hotspot analysis',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    if (_mockEnabled) return;
    var channel = Supabase.instance.client.channel('reports-monitoring');
    for (final table in [
      'cemetery_lot',
      'burial_record',
      'visitor_log',
      'lot_ownership',
      'transaction_history',
      'cemetery_map_features',
    ]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) {
          _refreshTimer?.cancel();
          _refreshTimer = Timer(const Duration(seconds: 1), _load);
        },
      );
    }
    _channel = channel.subscribe();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final data = _mockEnabled
        ? AnalyticsData.mock()
        : await AnalyticsData.load(Supabase.instance.client);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _calculate();
    });
  }

  void _calculate() {
    _spatial =
        _data?.spatial(
          start: _range?.start,
          end: _range?.end,
          epsilon: _epsilon,
          minPoints: _minPoints,
        ) ??
        const SpatialResult([], [], 0, 0);
  }

  bool _included(Object? value) => inPeriod(value, _range?.start, _range?.end);
  List<BlockDemand> get _demand => classifyDemand(_data!.lots, _data!.sales);
  Map<DateTime, int> get _visitorDays => visitorTrend(
    _data!.visitors,
    TrendInterval.daily,
    start: _range?.start,
    end: _range?.end,
  );
  Widget _densitySummary() {
    final areas = _data!.mappedLotAreas();
    final counts = <String, int>{};
    for (final point in _spatial.points) {
      counts[point.block] = (counts[point.block] ?? 0) + 1;
    }
    final densities = {
      for (final e in areas.entries)
        e.key: (counts[e.key] ?? 0) * 10000 / e.value,
    };
    final values = densities.values.toList();
    final mean = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;
    final variance = values.isEmpty
        ? 0.0
        : values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
              values.length;
    final threshold = mean + 2 * math.sqrt(variance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Block density uses burials per hectare of mapped lot footprint; walkways and unmapped land are excluded. '
          'The paper’s mean + 2 standard deviations rule is an exploratory comparison, not a significance test.',
        ),
        Text(
          values.length < 3
              ? 'At least three mapped blocks are needed for density comparison.'
              : 'High-density threshold: ${threshold.toStringAsFixed(1)} burials per mapped hectare.',
        ),
        _table(
          [
            'Block',
            'Burials',
            'Mapped m²',
            'Burials/hectare',
            'Above threshold',
          ],
          densities.entries
              .map(
                (e) => [
                  e.key,
                  counts[e.key] ?? 0,
                  areas[e.key]!.toStringAsFixed(1),
                  e.value.toStringAsFixed(1),
                  values.length < 3
                      ? 'Not assessed'
                      : e.value > threshold
                      ? 'Yes'
                      : 'No',
                ],
              )
              .toList(),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (range != null && mounted) {
      setState(() {
        _range = range;
        _calculate();
      });
    }
  }

  Widget _visitorCalendar() {
    final monthStart = DateTime(_visitorMonth.year, _visitorMonth.month);
    final monthEnd = DateTime(_visitorMonth.year, _visitorMonth.month + 1);
    final days = _visitorDays;
    final counts = <DateTime, int>{
      for (
        var day = monthStart;
        day.isBefore(monthEnd);
        day = day.add(const Duration(days: 1))
      )
        day: days[day] ?? 0,
    };
    final maxCount = counts.values.fold<int>(0, math.max);
    final firstOffset = monthStart.weekday - 1;
    final cellCount = firstOffset + counts.length;
    final totalCells = ((cellCount + 6) ~/ 7) * 7;
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);

    Color colorFor(int count) {
      if (count == 0)
        return Theme.of(context).colorScheme.surfaceContainerHighest;
      final opacity = 0.20 + (0.80 * count / maxCount);
      return _accent.withValues(alpha: opacity);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() {
                _visitorMonth = DateTime(
                  _visitorMonth.year,
                  _visitorMonth.month - 1,
                );
              }),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(monthStart),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed:
                  monthStart.isBefore(
                    DateTime(DateTime.now().year, DateTime.now().month),
                  )
                  ? () => setState(() {
                      _visitorMonth = DateTime(
                        _visitorMonth.year,
                        _visitorMonth.month + 1,
                      );
                    })
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 7 * 56,
            child: Column(
              children: [
                Row(
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .map(
                        (label) => SizedBox(
                          width: 56,
                          child: Text(label, textAlign: TextAlign.center),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 6),
                Wrap(
                  children: List.generate(totalCells, (index) {
                    if (index < firstOffset || index >= cellCount) {
                      return const SizedBox(width: 56, height: 56);
                    }
                    final day = monthStart.add(
                      Duration(days: index - firstOffset),
                    );
                    final count = counts[day] ?? 0;
                    return SizedBox(
                      width: 56,
                      height: 56,
                      child: Tooltip(
                        message:
                            '${DateFormat.yMMMd().format(day)}: $count visitor ${count == 1 ? 'entry' : 'entries'}',
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorFor(count),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                  color: count > 0
                                      ? Colors.white
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$total visitor entries this month. Darker dates have more entries.',
        ),
      ],
    );
  }

  Widget _card(String title, Widget child) => Card(
    color: Theme.of(context).colorScheme.surface,
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
  Widget _table(List<String> headers, List<List<Object?>> rows) {
    if (rows.isEmpty) return const Text('No matching records.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
        rows: rows
            .take(100)
            .map(
              (row) => DataRow(
                cells: row
                    .map((c) => DataCell(Text(c?.toString() ?? '—')))
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const Center(child: CircularProgressIndicator());
    final data = _data!;
    final demands = _demand;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_loading) const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  _range == null
                      ? 'All dates'
                      : '${DateFormat.yMMMd().format(_range!.start)} – ${DateFormat.yMMMd().format(_range!.end)}',
                ),
              ),
              if (_range != null)
                TextButton(
                  onPressed: () => setState(() {
                    _range = null;
                    _calculate();
                  }),
                  child: const Text('Clear dates'),
                ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: 'Refresh data',
                icon: const Icon(Icons.refresh),
              ),
              Text('Updated ${DateFormat.Hm().format(data.loadedAt!)}'),
              if (_mockEnabled)
                const Chip(
                  avatar: Icon(Icons.science_outlined, size: 16),
                  label: Text('Demo data'),
                ),
            ],
          ),
          if (_mockEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Showing sample reports and analytics. This data is local and is not connected to Supabase.',
              ),
            ),
          const SizedBox(height: 12),
          if (data.errors.isNotEmpty)
            _card(
              'Some data could not be loaded',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Affected reports are unavailable. Refresh to retry.',
                  ),
                  ...data.errors.entries.map(
                    (e) => Text('${e.key}: ${e.value}'),
                  ),
                ],
              ),
            ),
          _card(
            'Export reports',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: _report,
                      items: _types
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _report = value!),
                    ),
                    FilledButton.icon(
                      onPressed: _loading || _exporting ? null : _export,
                      icon: const Icon(Icons.download),
                      label: Text(_exporting ? 'Exporting…' : 'Download CSV'),
                    ),
                  ],
                ),
                const Text(
                  'Dates include the whole end day. Inventory and demand show the current state; '
                  'sales use ownership start dates, payments use payment dates, and burials use interment/burial dates. '
                  'Visitor dates use Philippine time. Tables show up to 100 rows; exports include all matching rows.',
                ),
              ],
            ),
          ),
          if (!data.errors.containsKey('transaction_history'))
            _card(
              'Recorded payments',
              Text(
                'PHP ${NumberFormat('#,##0.00').format(data.payments.where((p) => _included(p['payment_date'])).fold<double>(0, (s, p) => s + number(p['amount'])))} '
                'across ${data.payments.where((p) => _included(p['payment_date'])).length} transactions in this period.',
              ),
            ),
          if (!data.errors.containsKey('visitor_log'))
            _card(
              'Visitor calendar',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily visitor entries are shown as a calendar heatmap. Use the arrows to review earlier months; CSV export remains available for full detail.',
                  ),
                  const SizedBox(height: 12),
                  _visitorCalendar(),
                ],
              ),
            ),
          if (!data.errors.containsKey('cemetery_lot') &&
              !data.errors.containsKey('lot_ownership'))
            _card(
              'Current lot demand',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Demand indicator = lots occupied or sold ÷ total lots in each block. '
                    'A sold and occupied lot counts once. This describes current uptake, not future sales.',
                  ),
                  Wrap(
                    spacing: 24,
                    children: [
                      SizedBox(
                        width: 230,
                        child: Column(
                          children: [
                            Text('Medium from ${_medium.round()}%'),
                            Slider(
                              value: _medium,
                              min: 5,
                              max: 65,
                              divisions: 12,
                              onChanged: (v) => setState(() => _medium = v),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: Column(
                          children: [
                            Text('High from ${_high.round()}%'),
                            Slider(
                              value: _high,
                              min: 70,
                              max: 100,
                              divisions: 6,
                              onChanged: (v) => setState(() => _high = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    children: ['High', 'Medium', 'Low']
                        .map(
                          (level) => Chip(
                            avatar: CircleAvatar(
                              backgroundColor: level == 'High'
                                  ? Colors.red
                                  : level == 'Medium'
                                  ? Colors.orange
                                  : _accent,
                              radius: 5,
                            ),
                            label: Text(
                              '$level: ${demands.where((d) => d.level(medium: _medium, high: _high) == level).length} blocks',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  _table(
                    [
                      'Block',
                      'Lots',
                      'Occupied',
                      'Available',
                      'Sold',
                      'Uptake',
                      'Demand',
                    ],
                    demands
                        .map(
                          (d) => [
                            d.block,
                            d.lots,
                            d.occupied,
                            d.available,
                            d.sold,
                            '${d.score.toStringAsFixed(1)}%',
                            d.level(medium: _medium, high: _high),
                          ],
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          if (!data.errors.containsKey('cemetery_lot') &&
              !data.errors.containsKey('burial_record'))
            _card(
              'Spatial burial hotspots',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Each bubble represents one DBSCAN burial cluster. The number is the '
                    'burial-record count; isolated records are counted below but not drawn.',
                  ),
                  Wrap(
                    spacing: 24,
                    children: [
                      SizedBox(
                        width: 260,
                        child: Column(
                          children: [
                            Text('Radius: ${_epsilon.round()} metres'),
                            Slider(
                              value: _epsilon,
                              min: 5,
                              max: 100,
                              divisions: 19,
                              onChanged: (v) => setState(() {
                                _epsilon = v;
                                _calculate();
                              }),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: Column(
                          children: [
                            Text(
                              'Minimum nearby burials: $_minPoints (including itself)',
                            ),
                            Slider(
                              value: _minPoints.toDouble(),
                              min: 2,
                              max: 30,
                              divisions: 28,
                              onChanged: (v) => setState(() {
                                _minPoints = v.round();
                                _calculate();
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_spatial.clusterCount} clusters · ${_spatial.noiseCount} isolated records · '
                    '${_spatial.excluded} records excluded for missing geographic locations.',
                  ),
                  if (_range != null)
                    const Text(
                      'Records without a burial/interment date are excluded from this date range.',
                    ),
                  const SizedBox(height: 12),
                  _hotspotMap(),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: const [
                      _HotspotLegendItem(
                        color: Color(0x55F44336),
                        borderColor: Color(0xFFF44336),
                        label: 'Hotspot cluster area',
                      ),
                      _HotspotLegendItem(
                        color: Color(0xFFF44336),
                        label: 'Cluster count marker',
                      ),
                      _HotspotLegendItem(
                        color: Color(0xFF689F38),
                        label: 'Isolated burial record',
                      ),
                    ],
                  ),
                  _densitySummary(),
                  const SizedBox(height: 12),
                  _table(
                    ['Cluster', 'Burials', 'Blocks'],
                    [
                      for (var c = 0; c < _spatial.clusterCount; c++)
                        [
                          c + 1,
                          _spatial.labels.where((l) => l == c).length,
                          {
                            for (var i = 0; i < _spatial.points.length; i++)
                              if (_spatial.labels[i] == c)
                                _spatial.points[i].block,
                          }.join(', '),
                        ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _hotspotMap() {
    final positions = _data!.lots
        .map(_data!.position)
        .whereType<LatLng>()
        .toList();
    if (positions.isEmpty) {
      return const Text(
        'Import geographic lot polygons or QGIS coordinates to display the analysis map.',
      );
    }
    final points = _spatial.points;
    final clusterSizes = <int, int>{};
    for (final label in _spatial.labels) {
      if (label >= 0) clusterSizes[label] = (clusterSizes[label] ?? 0) + 1;
    }
    Color intensityColor(int label) {
      if (label < 0) return Colors.blueGrey;
      final size = clusterSizes[label] ?? 1;
      if (size >= 25) return Colors.red;
      if (size >= 15) return Colors.deepOrange;
      if (size >= 8) return Colors.amber.shade700;
      if (size >= 5) return Colors.lightGreen.shade700;
      return Colors.lightBlue.shade700;
    }

    final membersByCluster = <int, List<int>>{};
    for (var index = 0; index < _spatial.labels.length; index++) {
      final label = _spatial.labels[index];
      if (label >= 0) (membersByCluster[label] ??= []).add(index);
    }
    final clusterCircles = <CircleMarker>[];
    final clusterMarkers = <Marker>[];
    final clusterForLot = <String, int>{};
    for (var index = 0; index < points.length; index++) {
      final label = _spatial.labels[index];
      if (label >= 0) clusterForLot[points[index].lotId] = label;
    }
    final lotsById = {
      for (final lot in _data!.lots) lot['lot_id']?.toString(): lot,
    };
    final hotspotPolygons = <Polygon<String>>[];
    for (final entry in clusterForLot.entries) {
      final lot = lotsById[entry.key];
      if (lot == null) continue;
      final color = intensityColor(entry.value);
      hotspotPolygons.addAll(
        lotPolygonsFromRings(
          geoJsonPolygonRings(lot['polygon_geo']),
          lotId: entry.key,
          status: lot['status']?.toString() ?? 'Occupied',
          fillColorOverride: color.withValues(alpha: 0.56),
          strokeColorOverride: color,
        ),
      );
    }
    for (final entry in membersByCluster.entries) {
      final members = entry.value;
      final size = members.length;
      final center = LatLng(
        members.fold<double>(0, (sum, i) => sum + points[i].lat) / size,
        members.fold<double>(0, (sum, i) => sum + points[i].lng) / size,
      );
      final color = intensityColor(entry.key);
      clusterCircles.add(
        CircleMarker(
          point: center,
          radius: (18 + size * 0.8).clamp(20, 42).toDouble(),
          color: color.withValues(alpha: 0.20),
          borderColor: color.withValues(alpha: 0.75),
          borderStrokeWidth: 2,
        ),
      );
      clusterMarkers.add(
        Marker(
          point: center,
          width: 42,
          height: 42,
          child: Tooltip(
            message: 'Cluster ${entry.key + 1}: $size burial records',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showHotspotDetails(members.first),
                customBorder: const CircleBorder(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$size',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 420,
      child: FlutterMap(
        key: ValueKey(_data!.loadedAt),
        options: MapOptions(
          initialCenter: positions.first,
          initialZoom: 18,
          initialCameraFit: positions.length > 1
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(positions),
                  padding: const EdgeInsets.all(30),
                  maxZoom: 19,
                )
              : null,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'cemetery_app',
          ),
          // Only render polygons that belong to a cluster. This keeps the
          // cemetery context without drawing thousands of unrelated lots.
          PolygonLayer(polygons: hotspotPolygons),
          CircleLayer(circles: clusterCircles),
          MarkerLayer(markers: clusterMarkers),
          const RichAttributionWidget(
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
        ],
      ),
    );
  }

  void _showHotspotDetails(int pointIndex) {
    if (pointIndex < 0 || pointIndex >= _spatial.points.length) return;
    final point = _spatial.points[pointIndex];
    final clusterIndex = _spatial.labels[pointIndex];
    final memberIndexes = clusterIndex < 0
        ? [pointIndex]
        : [
            for (var i = 0; i < _spatial.labels.length; i++)
              if (_spatial.labels[i] == clusterIndex) i,
          ];
    final blocks = {
      for (final i in memberIndexes) _spatial.points[i].block,
    }.where((block) => block.trim().isNotEmpty).toList()..sort();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clusterIndex < 0
                    ? 'Isolated burial location'
                    : 'Hotspot cluster ${clusterIndex + 1}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _hotspotDetailRow('Burial records', '${memberIndexes.length}'),
              _hotspotDetailRow(
                'Blocks',
                blocks.isEmpty ? 'Not assigned' : blocks.join(', '),
              ),
              _hotspotDetailRow('Selected lot', point.lotId),
              _hotspotDetailRow('Selected block', point.block),
              _hotspotDetailRow(
                'Coordinates',
                '${point.lat.toStringAsFixed(6)}, ${point.lng.toStringAsFixed(6)}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hotspotDetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  List<List<Object?>> _burialSummaryRows(
    AnalyticsData data,
    Map<String, Map<String, dynamic>> lots,
  ) {
    final burials = data.burials
        .where(
          (record) =>
              _included(record['interment_date'] ?? record['burial_date']),
        )
        .toList();
    final categories = <String, int>{};
    final blocks = <String, int>{};
    final months = <String, int>{};
    final lotIds = <String>{};
    var unassignedLots = 0;

    for (final burial in burials) {
      final category = burial['burial_category']?.toString().trim();
      final categoryLabel = category == null || category.isEmpty
          ? 'Unspecified'
          : category;
      categories[categoryLabel] = (categories[categoryLabel] ?? 0) + 1;

      final lotId = burial['lot_id']?.toString();
      final lot = lotId == null ? null : lots[lotId];
      if (lot == null) {
        unassignedLots++;
        blocks['Unassigned'] = (blocks['Unassigned'] ?? 0) + 1;
      } else {
        lotIds.add(lotId!);
        final block = blockOf(lot);
        blocks[block] = (blocks[block] ?? 0) + 1;
      }

      final date = cemeteryDate(
        burial['interment_date'] ?? burial['burial_date'],
      );
      if (date != null) {
        final month = DateFormat('yyyy-MM').format(date);
        months[month] = (months[month] ?? 0) + 1;
      }
    }

    final selectedRange = _range == null
        ? 'All available records'
        : '${DateFormat('yyyy-MM-dd').format(_range!.start)} to ${DateFormat('yyyy-MM-dd').format(_range!.end)}';
    final categoryRows = categories.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final blockRows = blocks.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final monthRows = months.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final rows = <List<Object?>>[
      ['Burial statistics', 'Value'],
      ['Selected date range', selectedRange],
      ['Total burial records', burials.length],
      ['Records with assigned lots', burials.length - unassignedLots],
      ['Records without assigned lots', unassignedLots],
      ['Distinct lots represented', lotIds.length],
      [],
      ['Burial category', 'Records'],
      ...categoryRows.map((entry) => <Object?>[entry.key, entry.value]),
    ];
    rows.addAll([
      [],
      ['Block', 'Burial records'],
      ...blockRows.map((entry) => <Object?>[entry.key, entry.value]),
      [],
      ['Interment/burial month', 'Burial records'],
      ...monthRows.map((entry) => <Object?>[entry.key, entry.value]),
    ]);
    return rows;
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final data = _data!;
      final requiredTables = switch (_report) {
        'Burial records' ||
        'Burial records (detailed)' => ['burial_record', 'cemetery_lot'],
        'Visitor logs' || 'Visitor trends' => ['visitor_log'],
        'Lot inventory' => ['cemetery_lot'],
        'Lot sales' => ['lot_ownership', 'cemetery_lot'],
        'Payments' => ['transaction_history'],
        'Lot demand' => ['cemetery_lot', 'lot_ownership'],
        _ => ['cemetery_lot', 'burial_record'],
      };
      if (requiredTables.any(data.errors.containsKey)) {
        throw StateError('Required data is unavailable. Refresh and retry.');
      }
      final lots = {for (final l in data.lots) l['lot_id'].toString(): l};
      final List<List<Object?>> rows;
      switch (_report) {
        case 'Burial records':
          rows = _burialSummaryRows(data, lots);
          break;
        case 'Burial records (detailed)':
          rows = [
            [
              'ID',
              'Deceased',
              'Lot',
              'Birth date',
              'Death date',
              'Burial date',
              'Interment date',
            ],
            ...data.burials
                .where(
                  (r) => _included(r['interment_date'] ?? r['burial_date']),
                )
                .map(
                  (r) => [
                    r['burial_id'],
                    r['name_of_deceased'],
                    lotReference(lots[r['lot_id'].toString()] ?? {}),
                    r['birth_date'],
                    r['death_date'],
                    r['burial_date'],
                    r['interment_date'],
                  ],
                ),
          ];
        case 'Visitor logs':
          rows = [
            ['ID', 'Visitor ID', 'Burial ID', 'Time in', 'Time out', 'Method'],
            ...data.visitors
                .where((r) => _included(r['time_in']))
                .map(
                  (r) => [
                    r['log_id'],
                    r['user_id'],
                    r['burial_id'],
                    r['time_in'],
                    r['time_out'],
                    r['method'],
                  ],
                ),
          ];
        case 'Visitor trends':
          rows = [
            ['Period start (Asia/Manila)', 'Interval', 'Entries'],
            ..._visitorDays.entries.map(
              (e) => [DateFormat('yyyy-MM-dd').format(e.key), 'daily', e.value],
            ),
          ];
        case 'Lot inventory':
          rows = [
            ['ID', 'Lot', 'Block', 'Status', 'Listed price'],
            ...data.lots.map(
              (r) => [
                r['lot_id'],
                lotReference(r),
                blockOf(r),
                r['status'],
                r['price'],
              ],
            ),
          ];
        case 'Lot sales':
          rows = [
            [
              'Ownership ID',
              'Lot',
              'Owner ID',
              'Start date',
              'Status',
              'Current listed lot price (not historical sale value)',
            ],
            ...data.sales
                .where((r) => _included(r['start_date']))
                .map(
                  (r) => [
                    r['ownership_id'],
                    lotReference(lots[r['lot_id'].toString()] ?? {}),
                    r['user_id'],
                    r['start_date'],
                    r['status'],
                    lots[r['lot_id'].toString()]?['price'],
                  ],
                ),
          ];
        case 'Payments':
          rows = [
            [
              'Transaction ID',
              'Ownership ID',
              'Amount',
              'Payment date',
              'Notes',
            ],
            ...data.payments
                .where((r) => _included(r['payment_date']))
                .map(
                  (r) => [
                    r['transaction_id'],
                    r['ownership_id'],
                    r['amount'],
                    r['payment_date'],
                    r['notes'],
                  ],
                ),
          ];
        case 'Lot demand':
          rows = [
            [
              'Block',
              'Lots',
              'Occupied',
              'Available',
              'Sold',
              'Used or sold',
              'Uptake %',
              'Demand',
              'Medium cutoff %',
              'High cutoff %',
            ],
            ..._demand.map(
              (d) => [
                d.block,
                d.lots,
                d.occupied,
                d.available,
                d.sold,
                d.usedOrSold,
                d.score.toStringAsFixed(2),
                d.level(medium: _medium, high: _high),
                _medium,
                _high,
              ],
            ),
          ];
        default:
          rows = [
            [
              'Burial ID',
              'Lot ID',
              'Block',
              'Latitude',
              'Longitude',
              'Cluster (noise = -1)',
              'Radius metres',
              'MinPts',
              'Excluded missing locations',
            ],
            for (var i = 0; i < _spatial.points.length; i++)
              [
                _spatial.points[i].id,
                _spatial.points[i].lotId,
                _spatial.points[i].block,
                _spatial.points[i].lat,
                _spatial.points[i].lng,
                _spatial.labels[i] < 0 ? -1 : _spatial.labels[i] + 1,
                _epsilon,
                _minPoints,
                _spatial.excluded,
              ],
          ];
      }
      final name =
          '${_report.toLowerCase().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      await downloadCsv(encodeCsv(rows), name);
      await AuditService.log(
        action: 'EXPORT_REPORT',
        entityType: 'report',
        details:
            '$_report: ${rows.length - 1} rows; dates ${_range?.start} to ${_range?.end}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${rows.length - 1} rows.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
